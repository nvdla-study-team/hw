// -----------------------------------------------------------------------------
// cbuf_wr_if : cdma2buf 写口监测 interface（monitor-only，参数化覆盖 dat/wt 两口）
//   dat 口 : DATA_W=1024, HSEL_W=2（hsel[0]/[1] = 低/高 512b 半拍）
//   wt  口 : DATA_W=512,  HSEL_W=1（hsel 选 1024b entry 低/高半）
//   事实源 : outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_cdma.v:79-86 端口声明；
//            互连样板 vmod/nvdla/top/NV_NVDLA_partition_c.v（cdma2buf_* 直连 cbuf）
// -----------------------------------------------------------------------------
interface cbuf_wr_if #(
  parameter int DATA_W = 1024,
  parameter int HSEL_W = 2
) (input logic clk, input logic rstn);

  logic              wr_en;
  logic [11:0]       wr_addr;   // [11:8]=bank
  logic [HSEL_W-1:0] wr_hsel;
  logic [DATA_W-1:0] wr_data;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input wr_en, wr_addr, wr_hsel, wr_data;
  endclocking

endinterface : cbuf_wr_if
