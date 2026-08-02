// -----------------------------------------------------------------------------
// csc_cdma_stub : cdma 侧状态-信用面 stub（cdma_sc_stub 的方向对偶版，csc UT 用）
//   接口用 csc_cdma_if（cdma_sc_if 的方向对偶版，独立 interface 的原因见其头注）
//   - 驱动侧（drv_cb）：send_dat_updt(slices, entries) / send_wt_updt(kernels,
//     entries, wmb) 单拍 updt 脉冲通告"CBUF 新增了多少"（模拟 CDMA 写完入账）
//   - auto_ack=1（默认）：csc 层间清账握手的 cdma 侧应答——csc 拉
//     sc2cdma_*_pending_req 请求暂停，stub 拉对应 cdma2sc_*_pending_ack 并保持到
//     req 撤销（req&ack 同高完成清账；csc 见 ack 才撤 req，电平保持保证重叠，
//     协议见 docs/spec/units/cdma-cbuf.md 2.5 节）
//   - 监测侧（mon_cb）：sc2cdma_dat/wt_updt（csc 层末归还 credit）发布 cdma_sc_item
//     经 analysis port（item kind 复用 SC_DAT_UPDT/SC_WT_UPDT，此处语义为归还）
//   virtual interface 经 config_db 键 "csc_cdma_vif"
// -----------------------------------------------------------------------------
`ifndef CSC_CDMA_STUB_SVH
`define CSC_CDMA_STUB_SVH

class csc_cdma_stub extends uvm_component;

  virtual csc_cdma_if vif;

  uvm_analysis_port #(cdma_sc_item) ap; // sc2cdma 归还观测
  bit          auto_ack = 1'b1;         // 自动应答 pending 握手
  int unsigned n_dat_rls;               // 观测到的 dat 归还次数
  int unsigned n_wt_rls;
  int unsigned n_dat_ack_served;
  int unsigned n_wt_ack_served;

  `uvm_component_utils(csc_cdma_stub)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      if (!uvm_config_db#(virtual csc_cdma_if)::get(this, "", "csc_cdma_vif", vif))
        `uvm_info(get_type_name(), "csc_cdma_vif not found, stub in skeleton mode", UVM_HIGH)
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (vif == null) return;
    drive_idle();
    fork
      mon_loop();
      dat_ack_loop();
      wt_ack_loop();
    join
  endtask

  task drive_idle();
    vif.drv_cb.cdma2sc_dat_updt        <= 1'b0;
    vif.drv_cb.cdma2sc_dat_entries     <= '0;
    vif.drv_cb.cdma2sc_dat_slices      <= '0;
    vif.drv_cb.cdma2sc_wt_updt         <= 1'b0;
    vif.drv_cb.cdma2sc_wt_kernels      <= '0;
    vif.drv_cb.cdma2sc_wt_entries      <= '0;
    vif.drv_cb.cdma2sc_wmb_entries     <= '0;
    vif.drv_cb.cdma2sc_dat_pending_ack <= 1'b0;
    vif.drv_cb.cdma2sc_wt_pending_ack  <= 1'b0;
  endtask

  // req 起 -> ack 拉高保持 -> req 撤 -> ack 撤（电平应答保证 req&ack 重叠）
  task dat_ack_loop();
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1 || !auto_ack) continue;
      if (vif.mon_cb.sc2cdma_dat_pending_req === 1'b1) begin
        vif.drv_cb.cdma2sc_dat_pending_ack <= 1'b1;
        do @(vif.mon_cb); while (vif.mon_cb.sc2cdma_dat_pending_req === 1'b1);
        vif.drv_cb.cdma2sc_dat_pending_ack <= 1'b0;
        n_dat_ack_served++;
        `uvm_info(get_type_name(), "dat pending handshake served (cdma side)", UVM_MEDIUM)
      end
    end
  endtask

  task wt_ack_loop();
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1 || !auto_ack) continue;
      if (vif.mon_cb.sc2cdma_wt_pending_req === 1'b1) begin
        vif.drv_cb.cdma2sc_wt_pending_ack <= 1'b1;
        do @(vif.mon_cb); while (vif.mon_cb.sc2cdma_wt_pending_req === 1'b1);
        vif.drv_cb.cdma2sc_wt_pending_ack <= 1'b0;
        n_wt_ack_served++;
        `uvm_info(get_type_name(), "wt pending handshake served (cdma side)", UVM_MEDIUM)
      end
    end
  endtask

  // 观测 csc 的层末归还（sc2cdma updt）
  task mon_loop();
    cdma_sc_item tr;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;
      if (vif.mon_cb.sc2cdma_dat_updt === 1'b1) begin
        tr         = cdma_sc_item::type_id::create("sc2cdma_dat_updt");
        tr.kind    = cdma_sc_item::SC_DAT_UPDT;
        tr.entries = vif.mon_cb.sc2cdma_dat_entries;
        tr.slices  = vif.mon_cb.sc2cdma_dat_slices;
        n_dat_rls++;
        `uvm_info(get_type_name(), {"release ", tr.convert2string()}, UVM_MEDIUM)
        ap.write(tr);
      end
      if (vif.mon_cb.sc2cdma_wt_updt === 1'b1) begin
        tr             = cdma_sc_item::type_id::create("sc2cdma_wt_updt");
        tr.kind        = cdma_sc_item::SC_WT_UPDT;
        tr.kernels     = vif.mon_cb.sc2cdma_wt_kernels;
        tr.entries     = vif.mon_cb.sc2cdma_wt_entries;
        tr.wmb_entries = vif.mon_cb.sc2cdma_wmb_entries;
        n_wt_rls++;
        `uvm_info(get_type_name(), {"release ", tr.convert2string()}, UVM_MEDIUM)
        ap.write(tr);
      end
    end
  endtask

  // ---- 驱动接口（Wave2 层激励用）----

  // 通告数据入账：单拍 updt 脉冲携带 entries/slices
  // 先对齐一拍：调用方可能在非时钟事件时刻调用，否则起/落脉冲会落到同一
  // clocking 事件被 last-wins 吞掉（同 cdma_sc_stub 头注的竞态教训）
  task send_dat_updt(bit [11:0] slices, bit [11:0] entries);
    @(vif.drv_cb);
    vif.drv_cb.cdma2sc_dat_updt    <= 1'b1;
    vif.drv_cb.cdma2sc_dat_entries <= entries;
    vif.drv_cb.cdma2sc_dat_slices  <= slices;
    @(vif.drv_cb);
    vif.drv_cb.cdma2sc_dat_updt    <= 1'b0;
  endtask

  // 通告权重入账：单拍 updt 脉冲携带 kernels/entries/wmb_entries（对齐同上）
  task send_wt_updt(bit [13:0] kernels, bit [11:0] entries, bit [8:0] wmb_entries);
    @(vif.drv_cb);
    vif.drv_cb.cdma2sc_wt_updt     <= 1'b1;
    vif.drv_cb.cdma2sc_wt_kernels  <= kernels;
    vif.drv_cb.cdma2sc_wt_entries  <= entries;
    vif.drv_cb.cdma2sc_wmb_entries <= wmb_entries;
    @(vif.drv_cb);
    vif.drv_cb.cdma2sc_wt_updt     <= 1'b0;
  endtask

endclass : csc_cdma_stub

`endif // CSC_CDMA_STUB_SVH
