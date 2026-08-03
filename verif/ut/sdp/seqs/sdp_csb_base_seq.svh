// -----------------------------------------------------------------------------
// sdp_csb_base_seq : sdp UT 的 CSB 序列基类（2 目标）
//   - 目标块基址：SDP_RDMA=0xa000（CSB_TGT_SDP_RDMA=10）/ SDP=0xb000
//     （CSB_TGT_SDP=11），枚举值 == 块号（ut_types.svh），
//     字地址 = (块号<<10) + 块内字节偏移>>2
//   - 各 reg 块只消费 offset[11:0]（reg_offset={req_addr,2'b0} 低 12 位，
//     NV_NVDLA_SDP_reg.v:1148 / NV_NVDLA_SDP_RDMA_reg.v 同构）
//   - S/D 分界两块不同：SDP 主块 0x038（NV_NVDLA_SDP_reg.v:956，S 组含 LUT 系）、
//     SDP_RDMA 0x008（NV_NVDLA_SDP_RDMA_reg.v:672，S 组只有 S_STATUS/S_POINTER）
// -----------------------------------------------------------------------------
`ifndef SDP_CSB_BASE_SEQ_SVH
`define SDP_CSB_BASE_SEQ_SVH

class sdp_csb_base_seq extends uvm_sequence #(csb_seq_item);

  `uvm_object_utils(sdp_csb_base_seq)

  function new(string name = "sdp_csb_base_seq");
    super.new(name);
  endfunction

  // 目标 + 块内字节偏移 -> 16 位字地址
  function bit [15:0] wa(input csb_tgt_e tgt, input bit [11:0] byte_off);
    return 16'((int'(tgt) << 10) | (byte_off >> 2));
  endfunction

  // 定向写（np=0 posted / np=1 nposted；T0 全用 nposted 保证串行完成）
  // 注意：字地址必须在 randomize 前算好存入本地变量——若在 with 约束里写
  // wa(tgt, off)，名字 tgt 会被解析成 csb_seq_item 自己的 tgt 域（未随机化，
  // 恒 CSB_TGT_GLB），块号丢失（ccc UT T0 首跑实测踩到的坑，原样保留防复发）
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

endclass : sdp_csb_base_seq

`endif // SDP_CSB_BASE_SEQ_SVH
