// -----------------------------------------------------------------------------
// pdp_csb_base_seq : pdp UT 的 CSB 序列基类（2 目标）
//   - 目标块基址：PDP_RDMA=0xc000（CSB_TGT_PDP_RDMA=12）/ PDP=0xd000
//     （CSB_TGT_PDP=13）（枚举值 == 块号，ut_types.svh），
//     字地址 = (块号<<10) + 块内字节偏移>>2
//   - 两 reg 终点只消费 offset[11:0]（NV_NVDLA_PDP_reg.v:650-651 select 用
//     reg_offset[11:0]；NV_NVDLA_PDP_RDMA_reg.v 同构）
//   - S/D 分界 0x008（PDP_reg.v:649-651：<0x008 走 single、>=0x008 按 producer
//     选 d0/d1）：S 组只有 S_STATUS(0x000)/S_POINTER(0x004)
//   - 两口 req_prdy 均恒 1（PDP_reg.v:839 / PDP_RDMA_reg.v:625）
// -----------------------------------------------------------------------------
`ifndef PDP_CSB_BASE_SEQ_SVH
`define PDP_CSB_BASE_SEQ_SVH

class pdp_csb_base_seq extends uvm_sequence #(csb_seq_item);

  `uvm_object_utils(pdp_csb_base_seq)

  function new(string name = "pdp_csb_base_seq");
    super.new(name);
  endfunction

  // 目标 + 块内字节偏移 -> 16 位字地址
  function bit [15:0] wa(input csb_tgt_e tgt, input bit [11:0] byte_off);
    return 16'((int'(tgt) << 10) | (byte_off >> 2));
  endfunction

  // 定向写（np=0 posted / np=1 nposted；T0 全用 nposted 保证串行完成）
  // 注意：字地址必须在 randomize 前算好存入本地变量——若在 with 约束里写
  // wa(tgt, off)，名字 tgt 会被解析成 csb_seq_item 自己的 tgt 域（未随机化，
  // 恒 CSB_TGT_GLB），块号丢失（ccc UT T0 首跑实测踩到，本 UT 沿用防坑写法）
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

endclass : pdp_csb_base_seq

`endif // PDP_CSB_BASE_SEQ_SVH
