// -----------------------------------------------------------------------------
// sdp_source_stub : cacc2sdp 驱动 stub（阶段4 前置；SDP UT 扮演 cacc 发送侧）
//   - send_beat(tr) task：valid 拉高保持至 ready 握手，握手后按 gap 旋钮插空拍
//     （连续调用且 gap=0 时背靠背）
//   - gap 旋钮：gap_min/gap_max（uvm_config_db int unsigned 可调，默认 0）
//   - 复位期间 valid 压 0
//   virtual interface 经 config_db 键 "sdp_vif"（多实例靠作用域区分）
// -----------------------------------------------------------------------------
`ifndef SDP_SOURCE_STUB_SVH
`define SDP_SOURCE_STUB_SVH

class sdp_source_stub extends uvm_component;

  virtual sdp_if vif;

  // 握手后空拍旋钮：插 [gap_min:gap_max] 拍 valid=0（0/0=背靠背）
  int unsigned gap_min = 0;
  int unsigned gap_max = 0;

  int unsigned n_beats;

  `uvm_component_utils(sdp_source_stub)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null)
      if (!uvm_config_db#(virtual sdp_if)::get(this, "", "sdp_vif", vif))
        `uvm_info(get_type_name(), "sdp_vif not found, stub in skeleton mode", UVM_HIGH)
    void'(uvm_config_db#(int unsigned)::get(this, "", "gap_min", gap_min));
    void'(uvm_config_db#(int unsigned)::get(this, "", "gap_max", gap_max));
  endfunction

  // 初值 + 复位看护：复位期间 valid 压 0（出复位后交由 send_beat 独占驱动）
  virtual task run_phase(uvm_phase phase);
    if (vif == null) return;
    vif.src_cb.valid <= 1'b0;
    vif.src_cb.pd    <= '0;
    forever begin
      @(vif.src_cb);
      if (vif.rstn !== 1'b1) begin
        vif.src_cb.valid <= 1'b0;
        vif.src_cb.pd    <= '0;
      end
    end
  endtask

  // 发一拍（测试/序列直接调用）：复位中先压 0 等出复位；valid 保持至 ready 握手
  task send_beat(sdp_item tr);
    if (vif == null)
      `uvm_fatal(get_type_name(), "send_beat called with no vif")
    while (vif.rstn !== 1'b1) begin
      vif.src_cb.valid <= 1'b0;
      @(vif.src_cb);
    end
    vif.src_cb.valid <= 1'b1;
    vif.src_cb.pd    <= tr.pd;
    do @(vif.src_cb); while (vif.src_cb.ready !== 1'b1);
    vif.src_cb.valid <= 1'b0;
    n_beats++;
    `uvm_info(get_type_name(), tr.convert2string(), UVM_HIGH)
    if (gap_min > 0 || gap_max > 0)
      repeat ($urandom_range(gap_max, gap_min)) @(vif.src_cb);
  endtask

endclass : sdp_source_stub

`endif // SDP_SOURCE_STUB_SVH
