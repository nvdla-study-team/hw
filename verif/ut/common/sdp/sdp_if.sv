// -----------------------------------------------------------------------------
// sdp_if : cacc2sdp 输出口 interface（TB 扮演 SDP 接收侧）
//   事实源 : outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_cacc.v:87-89
//   valid/ready 握手 + pd[513:0]；pd 打包（CACC_delivery_buffer.v:1397-1414）：
//   [511:0]=16x32b lane（lane i = pd[32i+31 : 32i]）、[512]=batch_end、
//   [513]=layer_end。ready 是 csc+cmac+cacc 子流水线唯一外部反压点
//   阶段4 增补：src_cb（TB 扮演 cacc 驱动侧，SDP UT 入口激励用）
// -----------------------------------------------------------------------------
interface sdp_if (input logic clk, input logic rstn);

  logic         valid;  // DUT(cacc) -> TB
  logic [513:0] pd;     // DUT(cacc) -> TB
  logic         ready;  // TB -> DUT

  // sdp_sink_stub 用：驱 ready、采 valid/pd
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output ready;
    input  valid, pd;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, ready, pd;
  endclocking

  // sdp_source_stub 用：驱 valid/pd、采 ready（阶段4，SDP UT 扮演 cacc 侧）
  clocking src_cb @(posedge clk);
    default input #1step output #1;
    output valid, pd;
    input  ready;
  endclocking

endinterface : sdp_if
