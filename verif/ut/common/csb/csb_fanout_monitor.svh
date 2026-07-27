// -----------------------------------------------------------------------------
// csb_fanout_monitor : 扇出面 monitor（core 域，只读）
//   - ap_req : req_pvld && req_prdy 拍解码 req_pd 并发布（item 带 tgt 与 raw pd）
//   - ap_rsp : resp_valid 拍发布响应（rdat / error / type + raw pd）
//   17 路实例共用同一 scoreboard imp，靠 item.tgt 区分
// -----------------------------------------------------------------------------
`ifndef CSB_FANOUT_MONITOR_SVH
`define CSB_FANOUT_MONITOR_SVH

class csb_fanout_monitor extends uvm_monitor;

  virtual csb_fanout_if vif;
  int unsigned          tgt_id;

  uvm_analysis_port #(csb_seq_item) ap_req;
  uvm_analysis_port #(csb_seq_item) ap_rsp;

  `uvm_component_utils(csb_fanout_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_req = new("ap_req", this);
    ap_rsp = new("ap_rsp", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    csb_seq_item tr;

    if (vif == null)
      `uvm_fatal(get_type_name(), "csb_fanout_monitor has no virtual interface")

    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;

      if (vif.mon_cb.req_pvld === 1'b1 && vif.mon_cb.req_prdy === 1'b1) begin
        tr = csb_seq_item::type_id::create("fan_req");
        tr.raw_req_pd = vif.mon_cb.req_pd;
        tr.addr       = tr.raw_req_pd[15:0];
        tr.wdat       = tr.raw_req_pd[53:22];
        tr.write      = tr.raw_req_pd[54];
        tr.nposted    = tr.raw_req_pd[55];
        tr.tgt        = csb_tgt_e'(tgt_id);
        ap_req.write(tr);
      end

      if (vif.mon_cb.resp_valid === 1'b1) begin
        tr = csb_seq_item::type_id::create("fan_rsp");
        tr.raw_resp_pd = vif.mon_cb.resp_pd;
        tr.rdat        = tr.raw_resp_pd[31:0];
        tr.resp_error  = tr.raw_resp_pd[32];
        tr.resp_type   = tr.raw_resp_pd[33];
        tr.tgt         = csb_tgt_e'(tgt_id);
        ap_rsp.write(tr);
      end
    end
  endtask

endclass : csb_fanout_monitor

`endif // CSB_FANOUT_MONITOR_SVH
