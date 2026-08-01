// -----------------------------------------------------------------------------
// cdma_sc_item : cdma2sc 状态更新观测事务（Wave2 scoreboard 对账用）
// -----------------------------------------------------------------------------
`ifndef CDMA_SC_ITEM_SVH
`define CDMA_SC_ITEM_SVH

class cdma_sc_item extends uvm_sequence_item;

  typedef enum { SC_DAT_UPDT, SC_WT_UPDT } sc_kind_e;

  sc_kind_e  kind;
  bit [11:0] entries;      // dat: dat_entries / wt: wt_entries
  bit [11:0] slices;       // dat only
  bit [13:0] kernels;      // wt only
  bit [8:0]  wmb_entries;  // wt only

  `uvm_object_utils(cdma_sc_item)

  function new(string name = "cdma_sc_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    if (kind == SC_DAT_UPDT)
      return $sformatf("SC_DAT_UPDT entries=%0d slices=%0d", entries, slices);
    else
      return $sformatf("SC_WT_UPDT kernels=%0d entries=%0d wmb_entries=%0d",
                       kernels, entries, wmb_entries);
  endfunction

endclass : cdma_sc_item

`endif // CDMA_SC_ITEM_SVH
