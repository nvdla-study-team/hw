// -----------------------------------------------------------------------------
// csb_master_monitor : CSB 单口面 monitor（falcon 域，只读）
//   - ap_req : valid && ready 握手拍发布被接受的请求
//   - ap_rsp : rvalid（读数据）或 wr_complete（写完成）拍各发布一个响应 item
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_MONITOR_SVH
`define CSB_MASTER_MONITOR_SVH

class csb_master_monitor extends uvm_monitor;

  virtual csb_if vif;

  uvm_analysis_port #(csb_seq_item) ap_req;
  uvm_analysis_port #(csb_seq_item) ap_rsp;

  `uvm_component_utils(csb_master_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_req = new("ap_req", this);
    ap_rsp = new("ap_rsp", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    csb_seq_item tr;

    if (vif == null)
      `uvm_fatal(get_type_name(), "csb_master_monitor has no virtual interface")

    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;

      if (vif.mon_cb.valid === 1'b1 && vif.mon_cb.ready === 1'b1) begin
        tr = csb_seq_item::type_id::create("mst_req");
        tr.addr    = vif.mon_cb.addr;
        tr.wdat    = vif.mon_cb.wdat;
        tr.write   = vif.mon_cb.write;
        tr.nposted = vif.mon_cb.nposted;
        tr.tgt     = csb_target_of(tr.addr);
        ap_req.write(tr);
      end

      if (vif.mon_cb.rvalid === 1'b1) begin
        tr = csb_seq_item::type_id::create("mst_rsp_rd");
        tr.got_rvalid = 1'b1;
        tr.rdat       = vif.mon_cb.rdata;
        ap_rsp.write(tr);
      end

      if (vif.mon_cb.wr_complete === 1'b1) begin
        tr = csb_seq_item::type_id::create("mst_rsp_wr");
        tr.got_wr_complete = 1'b1;
        ap_rsp.write(tr);
      end
    end
  endtask

endclass : csb_master_monitor

`endif // CSB_MASTER_MONITOR_SVH
