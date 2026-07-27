// -----------------------------------------------------------------------------
// csb_fanout_if : CSB 扇出面 interface（core 时钟域），每路目的地一个实例
//   对应 DUT 端口 csb2<xx>_req_pvld/prdy/pd[62:0] + <xx>2csb_resp_valid/pd[33:0]
//   - rsp_cb : reactive responder 用（采样请求、驱动 prdy 背压与响应）
//   - mon_cb : monitor 只读采样
//   阶段3 预留：当同一 agent 需要变成主动 master（直接对单元 reg 面发请求）时，
//   在此增加 drv_cb（output req_pvld/req_pd, input req_prdy, input resp_*），
//   agent 按 is_active 选择 responder 或 driver。
// -----------------------------------------------------------------------------
interface csb_fanout_if (input logic clk, input logic rstn);

  // 请求（DUT -> 目的地）
  logic        req_pvld;
  logic [62:0] req_pd;   // [15:0]addr [21:16]=0 [53:22]wdat [54]write [55]nposted [62:56]=0
  // 请求握手（目的地 -> DUT）
  logic        req_prdy;
  // 响应（目的地 -> DUT，无握手，单拍脉冲）
  logic        resp_valid;
  logic [33:0] resp_pd;  // [31:0]rdat [32]error [33]type(0=读 1=写完成)

  clocking rsp_cb @(posedge clk);
    default input #1step output #1;
    input  req_pvld, req_pd;
    output req_prdy, resp_valid, resp_pd;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input req_pvld, req_prdy, req_pd, resp_valid, resp_pd;
  endclocking

endinterface : csb_fanout_if
