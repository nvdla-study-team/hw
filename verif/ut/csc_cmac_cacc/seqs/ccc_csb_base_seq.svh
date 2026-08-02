// -----------------------------------------------------------------------------
// ccc_csb_base_seq : csc_cmac_cacc UT 的 CSB 序列基类（4 目标）
//   - 目标块基址：CSC=0x6000 / CMAC_A=0x7000 / CMAC_B=0x8000 / CACC=0x9000
//     （枚举值 == 块号，ut_types.svh），字地址 = (块号<<10) + 块内字节偏移>>2
//   - 各 regfile 只消费 offset[11:0]（reg_offset={req_addr,2'b0} 低 12 位，
//     样板 NV_NVDLA_CSC_regfile.v:738/:555）
//   - S/D 分界 0x008（CSC_regfile.v:555-557，cmac/cacc 同构；与 CDMA 的 0x010
//     不同）：S 组只有 S_STATUS(0x000)/S_POINTER(0x004)
// -----------------------------------------------------------------------------
`ifndef CCC_CSB_BASE_SEQ_SVH
`define CCC_CSB_BASE_SEQ_SVH

class ccc_csb_base_seq extends uvm_sequence #(csb_seq_item);

  `uvm_object_utils(ccc_csb_base_seq)

  function new(string name = "ccc_csb_base_seq");
    super.new(name);
  endfunction

  // 目标 + 块内字节偏移 -> 16 位字地址
  function bit [15:0] wa(input csb_tgt_e tgt, input bit [11:0] byte_off);
    return 16'((int'(tgt) << 10) | (byte_off >> 2));
  endfunction

  // 定向写（np=0 posted / np=1 nposted；T0 全用 nposted 保证串行完成）
  // 注意：字地址必须在 randomize 前算好存入本地变量——若在 with 约束里写
  // wa(tgt, off)，名字 tgt 会被解析成 csb_seq_item 自己的 tgt 域（未随机化，
  // 恒 CSB_TGT_GLB），块号丢失（本 UT T0 首跑实测踩到）
  task csb_write(input csb_tgt_e tgt, input bit [11:0] off, input bit [31:0] d,
                 input bit np = 1'b1);
    bit [15:0] a;
    a   = wa(tgt, off);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with
        { addr == a; wdat == d; write == 1'b1; nposted == np; })
      `uvm_error(get_type_name(), "csb_write randomize failed")
    finish_item(req);
  endtask

  // 定向读（driver 回填 req.rdat 后返回；地址预算同上）
  task csb_read(input csb_tgt_e tgt, input bit [11:0] off, output bit [31:0] d);
    bit [15:0] a;
    a   = wa(tgt, off);
    req = csb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with
        { addr == a; write == 1'b0; nposted == 1'b0; })
      `uvm_error(get_type_name(), "csb_read randomize failed")
    finish_item(req);
    d = req.rdat;
  endtask

  // 读并与期望比对
  task csb_check(input csb_tgt_e tgt, input bit [11:0] off, input bit [31:0] exp,
                 input string tag);
    bit [31:0] rd;
    csb_read(tgt, off, rd);
    if (rd !== exp)
      `uvm_error(get_type_name(),
                 $sformatf("%s: tgt=%s off=0x%03h exp=0x%08h got=0x%08h",
                           tag, tgt.name(), off, exp, rd))
    else
      `uvm_info(get_type_name(),
                $sformatf("%s: tgt=%s off=0x%03h read 0x%08h OK",
                          tag, tgt.name(), off, rd), UVM_MEDIUM)
  endtask

endclass : ccc_csb_base_seq

`endif // CCC_CSB_BASE_SEQ_SVH
