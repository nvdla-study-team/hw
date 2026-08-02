// -----------------------------------------------------------------------------
// cbuf_resp_if : sc2buf 读口响应侧 interface（TB 扮演 cbuf，参数化 ADDR_W）
//   与 cbuf_rd_if 方向对偶：那边 TB 是主动读侧（驱 en/addr 采 valid/data），
//   这边 TB 是响应侧（采 en/addr 驱 valid/data），两者不可混用
//   dat/wt 口 ADDR_W=12，wmb 口 ADDR_W=8（RTL 实测 sc2buf_wmb_rd_addr[7:0]，
//   outdir .../csc/NV_NVDLA_csc.v:606）；数据恒 1024b
//   协议 : en+addr 一拍 -> 恰 6 拍后 valid+data，无反压，可背靠背流水
//         （合同同 cbuf_rd_if 头注，事实源 NV_NVDLA_cbuf.v:5838-5909）
// -----------------------------------------------------------------------------
interface cbuf_resp_if #(
  parameter int ADDR_W = 12
) (input logic clk, input logic rstn);

  logic              rd_en;     // DUT(csc) -> TB
  logic [ADDR_W-1:0] rd_addr;   // DUT(csc) -> TB
  logic              rd_valid;  // TB -> DUT
  logic [1023:0]     rd_data;   // TB -> DUT

  // cbuf_model 响应用：采请求、驱返回
  clocking mdl_cb @(posedge clk);
    default input #1step output #1;
    input  rd_en, rd_addr;
    output rd_valid, rd_data;
  endclocking

  // 只读观测
  clocking mon_cb @(posedge clk);
    default input #1step;
    input rd_en, rd_addr, rd_valid, rd_data;
  endclocking

endinterface : cbuf_resp_if
