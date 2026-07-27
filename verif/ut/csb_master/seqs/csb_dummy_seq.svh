// -----------------------------------------------------------------------------
// csb_dummy_seq : dummy 地址（字地址 >= 0x4400）行为验证
//   读回 0、nposted 写回 wr_complete、posted 写无响应（不回 error）
//   定向边界地址 + 少量随机 dummy 地址
// -----------------------------------------------------------------------------
`ifndef CSB_DUMMY_SEQ_SVH
`define CSB_DUMMY_SEQ_SVH

class csb_dummy_seq extends csb_base_seq;

  int unsigned num_random = 4;

  `uvm_object_utils(csb_dummy_seq)

  function new(string name = "csb_dummy_seq");
    super.new(name);
  endfunction

  task hit_dummy(input bit [15:0] a);
    bit [31:0] rd;
    csb_read(a, rd);
    if (rd !== 32'h0)
      `uvm_error(get_type_name(),
                 $sformatf("dummy read addr=0x%04h expected 0, got 0x%08h", a, rd))
    csb_write(a, $urandom(), 1'b1); // nposted 写：driver 等到 wr_complete 才返回
    csb_write(a, $urandom(), 1'b0); // posted 写：无响应
  endtask

  virtual task body();
    bit [15:0] directed[] = '{16'h4400, 16'h5000, 16'h8000, 16'hFFFF};
    foreach (directed[i]) hit_dummy(directed[i]);
    repeat (num_random) hit_dummy(16'($urandom_range(16'hFFFF, 16'h4400)));
  endtask

endclass : csb_dummy_seq

`endif // CSB_DUMMY_SEQ_SVH
