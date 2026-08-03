// -----------------------------------------------------------------------------
// sdp_scoreboard : 阶段4 环境版占位骨架
//   - 三路 analysis imp：DMA 请求（4 读 1 写共用）、sdp2pdp 出口 beat、中断
//   - check 全留空，只做收数计数：数据通路比对（refmodel/判分）待后续 Wave
//   - CSB 面比对不经此处，由 seq 内 csb_check 承担（同 ccc T0 模式）
// -----------------------------------------------------------------------------
`ifndef SDP_SCOREBOARD_SVH
`define SDP_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_sdp_dma)
`uvm_analysis_imp_decl(_sdp_pdp)
`uvm_analysis_imp_decl(_sdp_intr)

class sdp_scoreboard extends uvm_component;

  uvm_analysis_imp_sdp_dma  #(dma_seq_item, sdp_scoreboard) dma_imp;
  uvm_analysis_imp_sdp_pdp  #(sdp2pdp_item, sdp_scoreboard) pdp_imp;
  uvm_analysis_imp_sdp_intr #(bit,          sdp_scoreboard) intr_imp;

  int unsigned n_dma_items;
  int unsigned n_pdp_beats;
  int unsigned n_intrs;

  `uvm_component_utils(sdp_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dma_imp  = new("dma_imp", this);
    pdp_imp  = new("pdp_imp", this);
    intr_imp = new("intr_imp", this);
  endfunction

  // 阶段4 环境版占位：数据通路比对待后续 Wave（refmodel + wdma 落盘/pdp 出口判分）
  virtual function void write_sdp_dma(dma_seq_item tr);
    n_dma_items++;
  endfunction

  virtual function void write_sdp_pdp(sdp2pdp_item tr);
    n_pdp_beats++;
  endfunction

  virtual function void write_sdp_intr(bit b);
    n_intrs++;
  endfunction

endclass : sdp_scoreboard

`endif // SDP_SCOREBOARD_SVH
