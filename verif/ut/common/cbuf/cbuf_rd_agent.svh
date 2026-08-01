// -----------------------------------------------------------------------------
// cbuf_rd_agent : sc2buf 读口 agent（driver + sequencer + monitor，参数化 ADDR_W）
//   - driver  : 拉 en+addr 一拍即撤（连续 item 可每拍流水）；wait_data=1 时等
//               固定 6 拍延迟的 valid+data 回填 item 再 item_done
//   - monitor : en 拍把 addr 入队，valid 拍配对出队并发布 (addr,data) 事务
//               （协议固定 6 拍延迟、按序返回、无反压，队列序即配对序）
//   virtual interface 经 config_db 键 "cbuf_rd_vif"（tb 按实例作用域 set）
//   使用约束：wt 口与 wmb 口不得同拍读 bank15（cbuf 断言
//   "weight & wmb read ports hazard"，outdir .../NV_NVDLA_cbuf.v:6268），本 agent
//   无法跨实例互斥，由 sequence/virtual sequence 保证；同理 dat/wt 不得同拍同 bank
//   （:6221）、dat 口禁 bank15（:6127）、wt 口禁 bank0（:6174）
// -----------------------------------------------------------------------------
`ifndef CBUF_RD_AGENT_SVH
`define CBUF_RD_AGENT_SVH

typedef uvm_sequencer #(cbuf_rd_item) cbuf_rd_sequencer;

class cbuf_rd_driver #(
  int ADDR_W = 12
) extends uvm_driver #(cbuf_rd_item);

  typedef cbuf_rd_driver #(ADDR_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual cbuf_rd_if #(ADDR_W) vif_t;
  vif_t vif;

  localparam int RD_LATENCY = 6; // cbuf 固定读延迟（NV_NVDLA_cbuf.v:5838-5909）

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    cbuf_rd_item tr;
    if (vif == null)
      `uvm_fatal(get_type_name(), "cbuf_rd_driver has no virtual interface")
    drive_idle();
    wait (vif.rstn === 1'b1);
    repeat (2) @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(tr);
      // 先对齐一拍再驱动：get_next_item 可能在非时钟事件时刻返回（如 #delay 后
      // 启动的序列首笔），此时 clocking 驱动与本笔随后的 drive_idle 会落在同一
      // clocking 事件上（last-wins），首拍 en 丢失——统一先 @(cb) 消除该竞态
      // （代价是逐笔至少 1 拍间隔，本平台不依赖背靠背读）
      @(vif.drv_cb);
      repeat (tr.idle_before) @(vif.drv_cb);
      vif.drv_cb.rd_en   <= 1'b1;
      vif.drv_cb.rd_addr <= tr.addr[ADDR_W-1:0];
      @(vif.drv_cb);
      drive_idle();
      if (tr.wait_data) begin // 独占模式：等 6 拍延迟线上唯一一笔数据
        int unsigned waited = 0;
        while (vif.drv_cb.rd_valid !== 1'b1 && waited < RD_LATENCY + 4) begin
          @(vif.drv_cb); waited++;
        end
        if (vif.drv_cb.rd_valid === 1'b1) begin
          tr.data      = vif.drv_cb.rd_data;
          tr.got_valid = 1'b1;
        end
        else
          `uvm_error(get_type_name(),
                     $sformatf("rd_valid timeout: %s", tr.convert2string()))
      end
      seq_item_port.item_done();
    end
  endtask

  task drive_idle();
    vif.drv_cb.rd_en   <= 1'b0;
    vif.drv_cb.rd_addr <= '0;
  endtask

endclass : cbuf_rd_driver


class cbuf_rd_monitor #(
  int ADDR_W = 12
) extends uvm_monitor;

  typedef cbuf_rd_monitor #(ADDR_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual cbuf_rd_if #(ADDR_W) vif_t;
  vif_t vif;

  uvm_analysis_port #(cbuf_rd_item) ap;

  protected bit [ADDR_W-1:0] pend_addr_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    cbuf_rd_item tr;
    if (vif == null) return;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) begin
        pend_addr_q.delete();
        continue;
      end
      if (vif.mon_cb.rd_en === 1'b1)
        pend_addr_q.push_back(vif.mon_cb.rd_addr);
      if (vif.mon_cb.rd_valid === 1'b1) begin
        if (pend_addr_q.size() == 0) begin
          `uvm_error(get_type_name(), "rd_valid with no pending read address")
          continue;
        end
        tr           = cbuf_rd_item::type_id::create("cbuf_rd");
        tr.addr      = 12'(pend_addr_q.pop_front());
        tr.data      = vif.mon_cb.rd_data;
        tr.got_valid = 1'b1;
        `uvm_info(get_type_name(), tr.convert2string(), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask

endclass : cbuf_rd_monitor


class cbuf_rd_agent #(
  int ADDR_W = 12
) extends uvm_agent;

  typedef cbuf_rd_agent #(ADDR_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual cbuf_rd_if #(ADDR_W) vif_t;
  typedef cbuf_rd_driver  #(ADDR_W) driver_t;
  typedef cbuf_rd_monitor #(ADDR_W) monitor_t;

  vif_t             vif;
  driver_t          drv;
  cbuf_rd_sequencer sqr;
  monitor_t         mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(vif_t)::get(this, "", "cbuf_rd_vif", vif))
      `uvm_info(get_type_name(), "cbuf_rd_vif not found, agent in skeleton mode", UVM_HIGH)
    mon = monitor_t::type_id::create("mon", this);
    mon.vif = vif;
    if (get_is_active() == UVM_ACTIVE && vif != null) begin
      drv = driver_t::type_id::create("drv", this);
      sqr = cbuf_rd_sequencer::type_id::create("sqr", this);
      drv.vif = vif;
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (drv != null)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : cbuf_rd_agent

`endif // CBUF_RD_AGENT_SVH
