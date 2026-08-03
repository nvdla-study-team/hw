// -----------------------------------------------------------------------------
// cdp_scoreboard : 阶段4 环境版占位——数据通路比对待后续 wave
//   - dma_imp  : 收 mc_agt.mon 发布的 DMA 事务（rd req/rsp、wr cmd/data），仅计数
//   - intr_imp : 收 intr0/intr1 agent 的上升沿事件，仅计数
//   - check 留空；T0 的 CSB 面比对由 seq 内 csb_check 承担（照 ccc 的 seq 写法）
// -----------------------------------------------------------------------------
`ifndef CDP_SCOREBOARD_SVH
`define CDP_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_cdp_dma)
`uvm_analysis_imp_decl(_cdp_intr)

class cdp_scoreboard extends uvm_component;

  uvm_analysis_imp_cdp_dma  #(dma_seq_item, cdp_scoreboard) dma_imp;
  uvm_analysis_imp_cdp_intr #(bit,          cdp_scoreboard) intr_imp;

  int unsigned n_dma_rd_req, n_dma_rd_rsp, n_dma_wr_cmd, n_dma_wr_data;
  int unsigned n_intr;

  `uvm_component_utils(cdp_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dma_imp  = new("dma_imp", this);
    intr_imp = new("intr_imp", this);
  endfunction

  virtual function void write_cdp_dma(dma_seq_item tr);
    case (tr.kind)
      dma_seq_item::DMA_RD_REQ:  n_dma_rd_req++;
      dma_seq_item::DMA_RD_RSP:  n_dma_rd_rsp++;
      dma_seq_item::DMA_WR_CMD:  n_dma_wr_cmd++;
      dma_seq_item::DMA_WR_DATA: n_dma_wr_data++;
    endcase
    `uvm_info(get_type_name(),
              $sformatf("dma tr: %s", tr.convert2string()), UVM_HIGH)
  endfunction

  virtual function void write_cdp_intr(bit b);
    n_intr++;
  endfunction

  // 阶段4 环境版占位：数据通路比对待后续 wave（refmodel + wr 流判分）
  function void final_check();
  endfunction

endclass : cdp_scoreboard

`endif // CDP_SCOREBOARD_SVH
