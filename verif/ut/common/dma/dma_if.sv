// -----------------------------------------------------------------------------
// dma_if : xx2mcif / xx2cvif DMA 客户端接口（参数化位宽，cdp 为默认样本）
//   读通道 : rd_req_pd {addr[63:0], size[RD_REQ_W-1:64]} / rd_rsp_pd {data, mask}
//            mask[1:0] = 512-bit beat 的两个 256-bit 半拍有效位
//   写通道 : wr_req_pd[WR_REQ_W-1] = id（0=cmd 1=data）；cmd 变体 [77]=require_ack，
//            仅 require_ack=1 的命令返回 wr_rsp_complete
//   credit : rd_cdt_lat_fifo_pop 消费脉冲归还
//   协议细节见 docs/spec/common/dma-if.md
// -----------------------------------------------------------------------------
interface dma_if #(
  parameter int RD_REQ_W = 79,
  parameter int RD_RSP_W = 514,
  parameter int WR_REQ_W = 515
) (input logic clk, input logic rstn);

  // 读请求（客户端 -> 内存模型）
  logic                rd_req_pvld;
  logic                rd_req_prdy;
  logic [RD_REQ_W-1:0] rd_req_pd;
  // 读响应（内存模型 -> 客户端）
  logic                rd_rsp_pvld;
  logic                rd_rsp_prdy;   // 客户端侧名 rd_rsp_rdy/ready
  logic [RD_RSP_W-1:0] rd_rsp_pd;
  // 写通道（客户端 -> 内存模型）
  logic                wr_req_pvld;
  logic                wr_req_prdy;
  logic [WR_REQ_W-1:0] wr_req_pd;
  logic                wr_rsp_complete;
  // credit 归还脉冲（客户端消费侧）
  logic                rd_cdt_lat_fifo_pop;

  clocking slv_cb @(posedge clk);
    default input #1step output #1;
    input  rd_req_pvld, rd_req_pd, rd_rsp_prdy,
           wr_req_pvld, wr_req_pd, rd_cdt_lat_fifo_pop;
    output rd_req_prdy, rd_rsp_pvld, rd_rsp_pd, wr_req_prdy, wr_rsp_complete;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rd_req_pvld, rd_req_prdy, rd_req_pd,
          rd_rsp_pvld, rd_rsp_prdy, rd_rsp_pd,
          wr_req_pvld, wr_req_prdy, wr_req_pd,
          wr_rsp_complete, rd_cdt_lat_fifo_pop;
  endclocking

endinterface : dma_if
