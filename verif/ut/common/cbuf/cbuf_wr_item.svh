// -----------------------------------------------------------------------------
// cbuf_wr_item : cdma2buf 写口观测事务（dat/wt 共用；data/hsel 按最大位宽收纳）
// -----------------------------------------------------------------------------
`ifndef CBUF_WR_ITEM_SVH
`define CBUF_WR_ITEM_SVH

class cbuf_wr_item extends uvm_sequence_item;

  bit [11:0]   addr;
  bit [3:0]    bank;    // addr[11:8]
  bit [1:0]    hsel;    // wt 口只用 [0]
  bit [1023:0] data;    // wt 口只用 [511:0]

  `uvm_object_utils(cbuf_wr_item)

  function new(string name = "cbuf_wr_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("CBUF_WR addr=0x%03h bank=%0d hsel=%02b data[63:0]=0x%016h",
                     addr, bank, hsel, data[63:0]);
  endfunction

endclass : cbuf_wr_item

`endif // CBUF_WR_ITEM_SVH
