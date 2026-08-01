// -----------------------------------------------------------------------------
// cdma_csb_base_seq : cdma_cbuf UT 的 CSB 序列基类
//   - 提供定向读写 + 带比对读 + CDMA 块内字节偏移 -> 字地址换算
//   - CDMA 块基址 byte 0x5000（CSB_TGT_CDMA=5），字地址 = 0x1400 + off/4
//     （csb_master 译码 byte_addr[17:12]；regfile 只看 offset[11:0]，
//      NV_NVDLA_CDMA_regfile.v:1069 reg_offset={addr,2'b0}）
// -----------------------------------------------------------------------------
`ifndef CDMA_CSB_BASE_SEQ_SVH
`define CDMA_CSB_BASE_SEQ_SVH

class cdma_csb_base_seq extends uvm_sequence #(csb_seq_item);

  localparam bit [15:0] CDMA_BASE_WORD = 16'h1400; // byte 0x5000 >> 2

  `uvm_object_utils(cdma_csb_base_seq)

  function new(string name = "cdma_csb_base_seq");
    super.new(name);
  endfunction

  // 块内字节偏移 -> 16 位字地址
  function bit [15:0] wa(input bit [11:0] byte_off);
    return CDMA_BASE_WORD + (byte_off >> 2);
  endfunction

  // 定向写（np=0 posted / np=1 nposted；T0 全用 nposted 保证串行完成）
  task csb_write(input bit [11:0] off, input bit [31:0] d, input bit np = 1'b1);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == wa(off); wdat == d; write == 1'b1; nposted == np; })
      `uvm_error(get_type_name(), "csb_write randomize failed")
    finish_item(req);
  endtask

  // 定向读（driver 回填 req.rdat 后返回）
  task csb_read(input bit [11:0] off, output bit [31:0] d);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == wa(off); write == 1'b0; nposted == 1'b0; })
      `uvm_error(get_type_name(), "csb_read randomize failed")
    finish_item(req);
    d = req.rdat;
  endtask

  // 读并与期望比对
  task csb_check(input bit [11:0] off, input bit [31:0] exp, input string tag);
    bit [31:0] rd;
    csb_read(off, rd);
    if (rd !== exp)
      `uvm_error(get_type_name(),
                 $sformatf("%s: off=0x%03h exp=0x%08h got=0x%08h", tag, off, exp, rd))
    else
      `uvm_info(get_type_name(),
                $sformatf("%s: off=0x%03h read 0x%08h OK", tag, off, rd), UVM_MEDIUM)
  endtask

endclass : cdma_csb_base_seq

`endif // CDMA_CSB_BASE_SEQ_SVH
