// -----------------------------------------------------------------------------
// cbuf_rd_list_seq : 按地址表逐 entry 发 cbuf 读（配对数据由 monitor 发布，
//   scoreboard 面③ 比对）。不同读口（dat/wt）的表由 test 分开下发，串行运行，
//   规避 cbuf 同拍读 hazard（dat/wt 同 bank、wt/wmb bank15）
// -----------------------------------------------------------------------------
`ifndef CBUF_RD_LIST_SEQ_SVH
`define CBUF_RD_LIST_SEQ_SVH

class cbuf_rd_list_seq extends uvm_sequence #(cbuf_rd_item);

  bit [11:0]   addr_q[$];
  int unsigned idle_max = 1;

  `uvm_object_utils(cbuf_rd_list_seq)

  function new(string name = "cbuf_rd_list_seq");
    super.new(name);
  endfunction

  virtual task body();
    foreach (addr_q[i]) begin
      req = cbuf_rd_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with { addr == addr_q[i];
                                  idle_before <= idle_max;
                                  wait_data == 1'b0; })
        `uvm_error(get_type_name(), "randomize failed")
      finish_item(req);
    end
  endtask

endclass : cbuf_rd_list_seq

`endif // CBUF_RD_LIST_SEQ_SVH
