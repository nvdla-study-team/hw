// -----------------------------------------------------------------------------
// cbuf_wr_monitor : cdma2buf 写口 monitor（参数化 dat/wt 两口）
//   wr_en 拍发布 cbuf_wr_item(addr/bank/hsel/data)
//   virtual interface 经 config_db 键 "cbuf_wr_vif"（tb 按实例作用域 set）；
//   未绑定 vif 时空转（skeleton 模式）
//   注意：cdma 复位释放后自动 flush cbuf（dat 走 bank0-7、wt 走 bank8-15，
//   数据全 0，各 4096 拍），monitor 会看到这批写——属正常行为
// -----------------------------------------------------------------------------
`ifndef CBUF_WR_MONITOR_SVH
`define CBUF_WR_MONITOR_SVH

class cbuf_wr_monitor #(
  int DATA_W = 1024,
  int HSEL_W = 2
) extends uvm_monitor;

  typedef cbuf_wr_monitor #(DATA_W, HSEL_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual cbuf_wr_if #(DATA_W, HSEL_W) vif_t;
  vif_t vif;

  uvm_analysis_port #(cbuf_wr_item) ap;
  int unsigned n_writes;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      if (!uvm_config_db#(vif_t)::get(this, "", "cbuf_wr_vif", vif))
        `uvm_info(get_type_name(), "cbuf_wr_vif not found, monitor in skeleton mode", UVM_HIGH)
  endfunction

  virtual task run_phase(uvm_phase phase);
    cbuf_wr_item tr;
    if (vif == null) return;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;
      if (vif.mon_cb.wr_en === 1'b1) begin
        tr      = cbuf_wr_item::type_id::create("cbuf_wr");
        tr.addr = vif.mon_cb.wr_addr;
        tr.bank = vif.mon_cb.wr_addr[11:8];
        tr.hsel = 2'(vif.mon_cb.wr_hsel);
        tr.data = 1024'(vif.mon_cb.wr_data);
        n_writes++;
        `uvm_info(get_type_name(), tr.convert2string(), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask

endclass : cbuf_wr_monitor

`endif // CBUF_WR_MONITOR_SVH
