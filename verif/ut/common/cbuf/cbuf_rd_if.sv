// -----------------------------------------------------------------------------
// cbuf_rd_if : sc2buf 读口 interface（csc 侧读 stub 用，参数化 ADDR_W）
//   dat/wt 口 ADDR_W=12，wmb 口 ADDR_W=8；数据恒 1024b
//   协议 : 拉 en+addr 一拍 -> 固定 6 拍后 valid+data 返回，无反压，可每拍流水
//   事实源 : outdir/nv_full/vmod/nvdla/cbuf/NV_NVDLA_cbuf.v:5838-5909（en 6 级延迟
//            出 valid）、:6550/:6597/:6644（nv_assert_at_time_interval #(0,6,...)）
// -----------------------------------------------------------------------------
interface cbuf_rd_if #(
  parameter int ADDR_W = 12
) (input logic clk, input logic rstn);

  logic              rd_en;
  logic [ADDR_W-1:0] rd_addr;
  logic              rd_valid;
  logic [1023:0]     rd_data;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output rd_en, rd_addr;
    input  rd_valid, rd_data;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rd_en, rd_addr, rd_valid, rd_data;
  endclocking

endinterface : cbuf_rd_if
