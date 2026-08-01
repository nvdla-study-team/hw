// -----------------------------------------------------------------------------
// cdma_sc_stub : sc 侧状态-信用面 stub
//   - 监测 cdma2sc_dat_updt / cdma2sc_wt_updt 拍，发布 cdma_sc_item
//   - sc2cdma_* 默认驱 0；send_dat_release()/send_wt_release()/set_pending_req()
//     可显式驱动信用归还与 pending 握手
//   - auto_pending=1（默认）：模拟 CSC 的层间清账握手——首层（或 bank 配置变化的
//     层）DMA 通路进 PEND 态并拉 cdma2sc_*_pending_ack（NV_NVDLA_CDMA_status.v
//     注释块"四"；dc/wt 等 sc2cdma_*_pending_req 的**下降沿**才出 PEND：
//     NV_NVDLA_CDMA_dc.v `pending_req_end = pending_req_d1 & ~pending_req`），
//     stub 看到 ack 起即拉高对应 req 数拍再放下，完成 req&ack 同高清账 + 下降沿放行
//   virtual interface 经 config_db 键 "cdma_sc_vif"
// -----------------------------------------------------------------------------
`ifndef CDMA_SC_STUB_SVH
`define CDMA_SC_STUB_SVH

class cdma_sc_stub extends uvm_component;

  virtual cdma_sc_if vif;

  uvm_analysis_port #(cdma_sc_item) ap;
  int unsigned n_dat_updt;
  int unsigned n_wt_updt;
  bit          auto_pending = 1'b1; // 自动服务 pending 握手
  int unsigned n_dat_pending_served;
  int unsigned n_wt_pending_served;

  `uvm_component_utils(cdma_sc_stub)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      if (!uvm_config_db#(virtual cdma_sc_if)::get(this, "", "cdma_sc_vif", vif))
        `uvm_info(get_type_name(), "cdma_sc_vif not found, stub in skeleton mode", UVM_HIGH)
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (vif == null) return;
    drive_idle();
    fork
      mon_loop();
      dat_pending_loop();
      wt_pending_loop();
    join
  endtask

  // ack 起 -> 拉 req 4 拍 -> 放下（req&ack 同高清账；下降沿放行 PEND）
  task dat_pending_loop();
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1 || !auto_pending) continue;
      if (vif.mon_cb.cdma2sc_dat_pending_ack === 1'b1 &&
          vif.mon_cb.sc2cdma_dat_pending_req !== 1'b1) begin
        vif.drv_cb.sc2cdma_dat_pending_req <= 1'b1;
        repeat (4) @(vif.drv_cb);
        vif.drv_cb.sc2cdma_dat_pending_req <= 1'b0;
        n_dat_pending_served++;
        `uvm_info(get_type_name(), "dat pending handshake served", UVM_MEDIUM)
        do @(vif.mon_cb); while (vif.mon_cb.cdma2sc_dat_pending_ack === 1'b1);
      end
    end
  endtask

  task wt_pending_loop();
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1 || !auto_pending) continue;
      if (vif.mon_cb.cdma2sc_wt_pending_ack === 1'b1 &&
          vif.mon_cb.sc2cdma_wt_pending_req !== 1'b1) begin
        vif.drv_cb.sc2cdma_wt_pending_req <= 1'b1;
        repeat (4) @(vif.drv_cb);
        vif.drv_cb.sc2cdma_wt_pending_req <= 1'b0;
        n_wt_pending_served++;
        `uvm_info(get_type_name(), "wt pending handshake served", UVM_MEDIUM)
        do @(vif.mon_cb); while (vif.mon_cb.cdma2sc_wt_pending_ack === 1'b1);
      end
    end
  endtask

  task drive_idle();
    vif.drv_cb.sc2cdma_dat_updt        <= 1'b0;
    vif.drv_cb.sc2cdma_dat_entries     <= '0;
    vif.drv_cb.sc2cdma_dat_slices      <= '0;
    vif.drv_cb.sc2cdma_wt_updt         <= 1'b0;
    vif.drv_cb.sc2cdma_wt_kernels      <= '0;
    vif.drv_cb.sc2cdma_wt_entries      <= '0;
    vif.drv_cb.sc2cdma_wmb_entries     <= '0;
    vif.drv_cb.sc2cdma_dat_pending_req <= 1'b0;
    vif.drv_cb.sc2cdma_wt_pending_req  <= 1'b0;
  endtask

  task mon_loop();
    cdma_sc_item tr;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;
      if (vif.mon_cb.cdma2sc_dat_updt === 1'b1) begin
        tr         = cdma_sc_item::type_id::create("sc_dat_updt");
        tr.kind    = cdma_sc_item::SC_DAT_UPDT;
        tr.entries = vif.mon_cb.cdma2sc_dat_entries;
        tr.slices  = vif.mon_cb.cdma2sc_dat_slices;
        n_dat_updt++;
        `uvm_info(get_type_name(), tr.convert2string(), UVM_MEDIUM)
        ap.write(tr);
      end
      if (vif.mon_cb.cdma2sc_wt_updt === 1'b1) begin
        tr             = cdma_sc_item::type_id::create("sc_wt_updt");
        tr.kind        = cdma_sc_item::SC_WT_UPDT;
        tr.kernels     = vif.mon_cb.cdma2sc_wt_kernels;
        tr.entries     = vif.mon_cb.cdma2sc_wt_entries;
        tr.wmb_entries = vif.mon_cb.cdma2sc_wmb_entries;
        n_wt_updt++;
        `uvm_info(get_type_name(), tr.convert2string(), UVM_MEDIUM)
        ap.write(tr);
      end
    end
  endtask

  // ---- Wave2 驱动接口（本轮不使用）----

  // 归还数据 credit：单拍 updt 脉冲携带 entries/slices
  // 先对齐一拍：调用方可能在非时钟事件时刻（#delay 后）调用，否则起/落脉冲
  // 会落到同一 clocking 事件上被 last-wins 吞掉（同 cbuf_rd_driver 竞态）
  task send_dat_release(bit [11:0] entries, bit [11:0] slices);
    @(vif.drv_cb);
    vif.drv_cb.sc2cdma_dat_updt    <= 1'b1;
    vif.drv_cb.sc2cdma_dat_entries <= entries;
    vif.drv_cb.sc2cdma_dat_slices  <= slices;
    @(vif.drv_cb);
    vif.drv_cb.sc2cdma_dat_updt    <= 1'b0;
  endtask

  // 归还权重 credit：单拍 updt 脉冲携带 kernels/entries/wmb_entries（对齐同上）
  task send_wt_release(bit [13:0] kernels, bit [11:0] entries, bit [8:0] wmb_entries);
    @(vif.drv_cb);
    vif.drv_cb.sc2cdma_wt_updt     <= 1'b1;
    vif.drv_cb.sc2cdma_wt_kernels  <= kernels;
    vif.drv_cb.sc2cdma_wt_entries  <= entries;
    vif.drv_cb.sc2cdma_wmb_entries <= wmb_entries;
    @(vif.drv_cb);
    vif.drv_cb.sc2cdma_wt_updt     <= 1'b0;
  endtask

  // pending 请求电平（应答经 mon_cb.cdma2sc_dat/wt_pending_ack 观测；对齐同上）
  task set_pending_req(bit dat, bit wt);
    @(vif.drv_cb);
    vif.drv_cb.sc2cdma_dat_pending_req <= dat;
    vif.drv_cb.sc2cdma_wt_pending_req  <= wt;
    @(vif.drv_cb);
  endtask

endclass : cdma_sc_stub

`endif // CDMA_SC_STUB_SVH
