// -----------------------------------------------------------------------------
// dma_seq_item : DMA 通道观测/激励事务（阶段2 仅要求可编译、可实例化）
// -----------------------------------------------------------------------------
`ifndef DMA_SEQ_ITEM_SVH
`define DMA_SEQ_ITEM_SVH

class dma_seq_item extends uvm_sequence_item;

  typedef enum { DMA_RD_REQ, DMA_RD_RSP, DMA_WR_CMD, DMA_WR_DATA } dma_kind_e;

  dma_kind_e      kind;
  bit [63:0]      addr;
  bit [14:0]      size;         // 读请求 beat 数域
  bit             require_ack;  // 写命令 [77]：置 1 才回 wr_rsp_complete
  bit [511:0]     data;
  bit [1:0]       mask;         // 两个 256-bit 半拍有效位

  `uvm_object_utils(dma_seq_item)

  function new(string name = "dma_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s addr=0x%016h size=%0d ack=%0b mask=%02b",
                     kind.name(), addr, size, require_ack, mask);
  endfunction

endclass : dma_seq_item

`endif // DMA_SEQ_ITEM_SVH
