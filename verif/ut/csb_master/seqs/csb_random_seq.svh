// -----------------------------------------------------------------------------
// csb_random_seq : 全随机事务流
//   addr 全 16 位空间（约 73% 落 dummy）、write/nposted/wdat/idle_before 全随机
//   尾距约束：posted 写之后下一笔 idle_before >= 7 falcon 拍（70ns+握手 >
//   背压下扇出口保持寄存器最大滞留 gap_max+1=9 core 拍 = 63ns），规避 DUT
//   单级保持寄存器的同口覆盖（RTL 真实限制：持续背压下硬灌第二笔会丢前一笔）
// -----------------------------------------------------------------------------
`ifndef CSB_RANDOM_SEQ_SVH
`define CSB_RANDOM_SEQ_SVH

class csb_random_seq extends csb_base_seq;

  int unsigned num_txns = 300;

  `uvm_object_utils(csb_random_seq)

  function new(string name = "csb_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit prev_posted = 1'b0;
    repeat (num_txns) begin
      req = csb_seq_item::type_id::create("req");
      start_item(req);
      if (prev_posted) begin
        if (!req.randomize() with { idle_before inside {[7:12]}; })
          `uvm_error(get_type_name(), "randomize failed")
      end
      else begin
        if (!req.randomize())
          `uvm_error(get_type_name(), "randomize failed")
      end
      finish_item(req);
      prev_posted = req.write && !req.nposted;
    end
  endtask

endclass : csb_random_seq

`endif // CSB_RANDOM_SEQ_SVH
