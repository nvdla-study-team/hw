// -----------------------------------------------------------------------------
// sdp2pdp_if : sdp2pdp 出口 interface（阶段4 前置公共组件）
//   事实源 : outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_sdp.v:156-158
//   valid/ready 握手 + pd[255:0]（SDP -> PDP 数据流）
//   信号裸 logic，方向只由 clocking 定：SDP UT 用 sink_cb 收出口，
//   PDP UT 用 src_cb 扮演 sdp 驱动侧
// -----------------------------------------------------------------------------
interface sdp2pdp_if (input logic clk, input logic rstn);

  logic         valid;  // src -> sink
  logic [255:0] pd;     // src -> sink
  logic         ready;  // sink -> src

  // sdp2pdp_source_stub 用：驱 valid/pd、采 ready
  clocking src_cb @(posedge clk);
    default input #1step output #1;
    output valid, pd;
    input  ready;
  endclocking

  // sdp2pdp_sink_stub 用：驱 ready、采 valid/pd
  clocking sink_cb @(posedge clk);
    default input #1step output #1;
    output ready;
    input  valid, pd;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, ready, pd;
  endclocking

endinterface : sdp2pdp_if
