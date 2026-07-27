// -----------------------------------------------------------------------------
// csb_smoke_seq : 17 路目的地各做 posted 写 -> nposted 写 -> 读回
//   读回值应等于 nposted 写入值（序列自检 + scoreboard 独立比对双保险）
// -----------------------------------------------------------------------------
`ifndef CSB_SMOKE_SEQ_SVH
`define CSB_SMOKE_SEQ_SVH

class csb_smoke_seq extends csb_base_seq;

  `uvm_object_utils(csb_smoke_seq)

  function new(string name = "csb_smoke_seq");
    super.new(name);
  endfunction

  virtual task body();
    for (int t = 0; t < NUM_CSB_TGT; t++) begin
      bit [15:0] a;
      bit [31:0] d1, d2, rd;
      a  = 16'(t * 'h400 + 'h10 + t); // 块内偏移错开，全部落在本 4KB 块
      d1 = 32'hA5A5_0000 | t;
      d2 = 32'h5A5A_0000 | t;
      csb_write(a, d1, 1'b0); // posted
      csb_write(a, d2, 1'b1); // nposted
      csb_read(a, rd);
      if (rd !== d2)
        `uvm_error(get_type_name(),
                   $sformatf("read-back mismatch tgt=%0d addr=0x%04h exp=0x%08h got=0x%08h",
                             t, a, d2, rd))
      else
        `uvm_info(get_type_name(),
                  $sformatf("tgt=%0d addr=0x%04h read-back OK (0x%08h)", t, a, rd),
                  UVM_MEDIUM)
    end
  endtask

endclass : csb_smoke_seq

`endif // CSB_SMOKE_SEQ_SVH
