// -----------------------------------------------------------------------------
// csb_base_seq : CSB 序列基类，提供定向读写辅助任务
// -----------------------------------------------------------------------------
`ifndef CSB_BASE_SEQ_SVH
`define CSB_BASE_SEQ_SVH

class csb_base_seq extends uvm_sequence #(csb_seq_item);

  `uvm_object_utils(csb_base_seq)

  function new(string name = "csb_base_seq");
    super.new(name);
  endfunction

  // 定向写（np=0 posted / np=1 nposted）
  task csb_write(input bit [15:0] a, input bit [31:0] d, input bit np);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == a; wdat == d; write == 1'b1; nposted == np; })
      `uvm_error(get_type_name(), "csb_write randomize failed")
    finish_item(req);
  endtask

  // 定向读（driver 回填 req.rdat 后返回）
  task csb_read(input bit [15:0] a, output bit [31:0] d);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == a; write == 1'b0; nposted == 1'b0; })
      `uvm_error(get_type_name(), "csb_read randomize failed")
    finish_item(req);
    d = req.rdat;
  endtask

endclass : csb_base_seq

`endif // CSB_BASE_SEQ_SVH
