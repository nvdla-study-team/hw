// -----------------------------------------------------------------------------
// pdp_scoreboard : 阶段4 环境版占位——数据通路比对待后续 Wave
//   现阶段只声明观测入口并计数：
//     - dma_imp  : mc_agt.mon 的 DMA 事务流（读请求/读响应/写 cmd/写 data）
//     - intr_imp : intr0/intr1 agent 的置位事件
//   check 留空；T0 的 CSB 面比对由 seq 内 csb_check 承担（照 ccc 的 seq 写法）。
//   后续 Wave 在此接 pooling refmodel：以 sdp2pdp/RDMA 入流 + 寄存器配置建
//   期望 WDMA 写流（addr 序 + data），与 dma_imp 收到的 WR_CMD/WR_DATA 比对。
// -----------------------------------------------------------------------------
`ifndef PDP_SCOREBOARD_SVH
`define PDP_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_pdp_dma)
`uvm_analysis_imp_decl(_pdp_intr)

class pdp_scoreboard extends uvm_component;

  uvm_analysis_imp_pdp_dma  #(dma_seq_item, pdp_scoreboard) dma_imp;
  uvm_analysis_imp_pdp_intr #(bit, pdp_scoreboard)          intr_imp;

  int unsigned n_dma_rd_req;
  int unsigned n_dma_rd_rsp;
  int unsigned n_dma_wr_cmd;
  int unsigned n_dma_wr_data;
  int unsigned n_intr;

  `uvm_component_utils(pdp_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dma_imp  = new("dma_imp", this);
    intr_imp = new("intr_imp", this);
  endfunction

  virtual function void write_pdp_dma(dma_seq_item tr);
    case (tr.kind)
      dma_seq_item::DMA_RD_REQ:  n_dma_rd_req++;
      dma_seq_item::DMA_RD_RSP:  n_dma_rd_rsp++;
      dma_seq_item::DMA_WR_CMD:  n_dma_wr_cmd++;
      dma_seq_item::DMA_WR_DATA: n_dma_wr_data++;
    endcase
    `uvm_info(get_type_name(),
              $sformatf("dma observed: %s", tr.convert2string()), UVM_HIGH)
  endfunction

  virtual function void write_pdp_intr(bit b);
    n_intr++;
    `uvm_info(get_type_name(),
              $sformatf("intr rise #%0d", n_intr), UVM_MEDIUM)
  endfunction

  // 阶段4 环境版占位：数据通路比对待后续 Wave（pooling refmodel + WDMA 写流判分）
  function void final_check();
  endfunction

endclass : pdp_scoreboard

`endif // PDP_SCOREBOARD_SVH
