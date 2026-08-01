// -----------------------------------------------------------------------------
// cbuf_rd_item : cbuf 读口事务（addr 按最大 12 位收纳，wmb 口 driver 截取低 8 位）
//   wait_data=1 时 driver 阻塞等 6 拍延迟的数据回填 item.data 再 item_done
//   （仅限该口无其它在途读时使用）；默认非阻塞流水，配对数据由 monitor 发布
// -----------------------------------------------------------------------------
`ifndef CBUF_RD_ITEM_SVH
`define CBUF_RD_ITEM_SVH

class cbuf_rd_item extends uvm_sequence_item;

  rand bit [11:0]   addr;
  rand int unsigned idle_before;  // 发起前空闲拍数
  rand bit          wait_data;    // 1=driver 等数据回填后才 item_done

  constraint idle_c { soft idle_before inside {[0:3]}; }
  constraint wait_c { soft wait_data == 1'b0; }

  bit [1023:0] data;   // 回填域（driver wait_data 模式 / monitor 配对）
  bit          got_valid;

  `uvm_object_utils(cbuf_rd_item)

  function new(string name = "cbuf_rd_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("CBUF_RD addr=0x%03h bank=%0d data[63:0]=0x%016h",
                     addr, addr[11:8], data[63:0]);
  endfunction

endclass : cbuf_rd_item

`endif // CBUF_RD_ITEM_SVH
