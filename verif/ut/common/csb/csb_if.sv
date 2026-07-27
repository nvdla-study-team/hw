// -----------------------------------------------------------------------------
// csb_if : CSB 单口面 interface（falcon 时钟域）
//   对应 DUT 端口 csb2nvdla_*（请求）与 nvdla2csb_*（响应）
//   - drv_cb : master driver 用（驱动请求、采样 ready 与响应）
//   - mon_cb : monitor 只读采样
//   TB 一律通过 clocking block 访问信号（output #1 / input #1step）
// -----------------------------------------------------------------------------
interface csb_if (input logic clk, input logic rstn);

  // 请求（TB -> DUT）
  logic        valid;
  logic [15:0] addr;     // 字地址
  logic [31:0] wdat;
  logic        write;
  logic        nposted;
  // 请求握手（DUT -> TB）
  logic        ready;
  // 响应（DUT -> TB）
  logic        rvalid;      // nvdla2csb_valid：读数据有效
  logic [31:0] rdata;       // nvdla2csb_data
  logic        wr_complete; // nvdla2csb_wr_complete：nposted 写完成

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output valid, addr, wdat, write, nposted;
    input  ready, rvalid, rdata, wr_complete;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, addr, wdat, write, nposted, ready, rvalid, rdata, wr_complete;
  endclocking

endinterface : csb_if
