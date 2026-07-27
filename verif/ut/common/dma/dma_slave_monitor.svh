// -----------------------------------------------------------------------------
// dma_slave_monitor : DMA 通道 monitor（参数化，阶段2 骨架：编译 + 可实例化）
//   观测读请求 / 读响应 / 写 cmd / 写 data 四类握手拍并发布 dma_seq_item
// -----------------------------------------------------------------------------
`ifndef DMA_SLAVE_MONITOR_SVH
`define DMA_SLAVE_MONITOR_SVH

class dma_slave_monitor #(
  int RD_REQ_W = 79,
  int RD_RSP_W = 514,
  int WR_REQ_W = 515
) extends uvm_monitor;

  typedef dma_slave_monitor #(RD_REQ_W, RD_RSP_W, WR_REQ_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual dma_if #(RD_REQ_W, RD_RSP_W, WR_REQ_W) vif_t;
  vif_t vif;

  localparam int DATA_W = RD_RSP_W - 2;

  uvm_analysis_port #(dma_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    dma_seq_item tr;
    if (vif == null) begin
      `uvm_info(get_type_name(), "no vif bound, monitor idle (skeleton mode)", UVM_HIGH)
      return;
    end
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) continue;

      if (vif.mon_cb.rd_req_pvld === 1'b1 && vif.mon_cb.rd_req_prdy === 1'b1) begin
        tr      = dma_seq_item::type_id::create("rd_req");
        tr.kind = dma_seq_item::DMA_RD_REQ;
        tr.addr = vif.mon_cb.rd_req_pd[63:0];
        tr.size = vif.mon_cb.rd_req_pd[RD_REQ_W-1:64];
        ap.write(tr);
      end

      if (vif.mon_cb.rd_rsp_pvld === 1'b1 && vif.mon_cb.rd_rsp_prdy === 1'b1) begin
        tr      = dma_seq_item::type_id::create("rd_rsp");
        tr.kind = dma_seq_item::DMA_RD_RSP;
        tr.data = vif.mon_cb.rd_rsp_pd[DATA_W-1:0];
        tr.mask = vif.mon_cb.rd_rsp_pd[RD_RSP_W-1:DATA_W];
        ap.write(tr);
      end

      if (vif.mon_cb.wr_req_pvld === 1'b1 && vif.mon_cb.wr_req_prdy === 1'b1) begin
        if (vif.mon_cb.wr_req_pd[WR_REQ_W-1] == 1'b0) begin
          tr             = dma_seq_item::type_id::create("wr_cmd");
          tr.kind        = dma_seq_item::DMA_WR_CMD;
          tr.addr        = vif.mon_cb.wr_req_pd[63:0];
          tr.require_ack = vif.mon_cb.wr_req_pd[77];
        end
        else begin
          tr      = dma_seq_item::type_id::create("wr_data");
          tr.kind = dma_seq_item::DMA_WR_DATA;
          tr.data = vif.mon_cb.wr_req_pd[DATA_W-1:0];
        end
        ap.write(tr);
      end
    end
  endtask

endclass : dma_slave_monitor

`endif // DMA_SLAVE_MONITOR_SVH
