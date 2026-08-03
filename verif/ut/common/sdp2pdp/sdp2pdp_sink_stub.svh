// -----------------------------------------------------------------------------
// sdp2pdp_sink_stub : sdp2pdp 接收 stub（reactive sink；阶段4 前置公共组件）
//   - 收 valid/pd[255:0]，valid&ready 拍事务化（sdp2pdp_item）发 analysis port
//   - ready 背压旋钮：ready_gap_pct 概率拉低 [gap_min:gap_max] 拍；
//     hold_ready_low(n) 长停 task（反压场景用）
//   virtual interface 经 config_db 键 "sdp2pdp_vif"
// -----------------------------------------------------------------------------
`ifndef SDP2PDP_SINK_STUB_SVH
`define SDP2PDP_SINK_STUB_SVH

class sdp2pdp_sink_stub extends uvm_component;

  virtual sdp2pdp_if vif;

  uvm_analysis_port #(sdp2pdp_item) ap;

  // 背压旋钮
  int unsigned ready_gap_pct = 0; // 每拍拉低 ready 的百分比概率（0=恒 ready）
  int unsigned ready_gap_min = 1;
  int unsigned ready_gap_max = 4;

  protected bit forced_low = 1'b0; // hold_ready_low 生效期
  int unsigned  n_beats;

  `uvm_component_utils(sdp2pdp_sink_stub)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      if (!uvm_config_db#(virtual sdp2pdp_if)::get(this, "", "sdp2pdp_vif", vif))
        `uvm_info(get_type_name(), "sdp2pdp_vif not found, stub in skeleton mode", UVM_HIGH)
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (vif == null) return;
    vif.sink_cb.ready <= 1'b0;
    wait (vif.rstn === 1'b1);
    fork
      ready_loop();
      mon_loop();
    join
  endtask

  task ready_loop();
    forever begin
      @(vif.sink_cb);
      if (forced_low) begin
        vif.sink_cb.ready <= 1'b0;
        continue;
      end
      if (ready_gap_pct > 0 && $urandom_range(99) < ready_gap_pct) begin
        vif.sink_cb.ready <= 1'b0;
        repeat ($urandom_range(ready_gap_max, ready_gap_min)) @(vif.sink_cb);
      end
      vif.sink_cb.ready <= 1'b1;
    end
  endtask

  // 长停：拉低 ready 恰 ncycles 拍（期间 ready_loop 让位）
  task hold_ready_low(int unsigned ncycles);
    forced_low = 1'b1;
    vif.sink_cb.ready <= 1'b0;
    repeat (ncycles) @(vif.sink_cb);
    forced_low = 1'b0;
  endtask

  task mon_loop();
    sdp2pdp_item tr;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;
      if (vif.mon_cb.valid === 1'b1 && vif.mon_cb.ready === 1'b1) begin
        tr = sdp2pdp_item::type_id::create("sdp2pdp_beat");
        tr.pd = vif.mon_cb.pd;
        n_beats++;
        `uvm_info(get_type_name(), tr.convert2string(), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask

endclass : sdp2pdp_sink_stub

`endif // SDP2PDP_SINK_STUB_SVH
