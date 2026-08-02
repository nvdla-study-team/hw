// -----------------------------------------------------------------------------
// ccc_t0_reg_seq : T0 四单元寄存器冒烟（CSC / CMAC_A / CMAC_B / CACC）
//   对 4 个目标各做：
//     1. 复位值读（三单元 proc_precision 复位均 2'b01=int16，CSC 另有
//        in_precision=01；D_MISC_CFG 复位 CSC=0x1100、CMAC/CACC=0x1000）
//     2. 代表性 D 寄存器 mask 化写读（掩掉位读 0，*_out 拼接中非字段位 tie 0）
//     3. S_POINTER 乒乓影子（producer 切换，d0/d1 独立保值；S/D 分界 0x008）
//     4. 块内偏移扫描读不挂
//   末尾做 4 目标互不串验证（写 4 家各留一值，再逐家读回）
//   全程不写 D_OP_ENABLE（0x008）：regfile 有 "Write group registers when OP_EN
//   is set" 断言，且 op_en 会启动数据通路，T0 保持纯寄存器面
//   寄存器事实源（outdir/nv_full/vmod/nvdla/）：
//     csc/NV_NVDLA_CSC_single_reg.v:54-57、CSC_dual_reg.v:182-229（offset/拼接）、
//       复位块（atomics=1、rls_slices=1、in/proc_precision=01）
//     cmac/NV_NVDLA_CMAC_REG_single.v:54-57、REG_dual.v:55-58/:83-92
//     cacc/NV_NVDLA_CACC_single_reg.v:54-55、CACC_dual_reg.v:100-123、复位块
// -----------------------------------------------------------------------------
`ifndef CCC_T0_REG_SEQ_SVH
`define CCC_T0_REG_SEQ_SVH

class ccc_t0_reg_seq extends ccc_csb_base_seq;

  // ---- 公共偏移（三单元同构） ----
  localparam bit [11:0] S_STATUS    = 12'h000;
  localparam bit [11:0] S_POINTER   = 12'h004;
  localparam bit [11:0] D_OP_ENABLE = 12'h008; // 只读复位值，不写
  localparam bit [11:0] D_MISC_CFG  = 12'h00c;

  // ---- CSC 专有 ----
  localparam bit [11:0] CSC_D_DATAIN_FORMAT = 12'h010;
  localparam bit [11:0] CSC_D_ATOMICS       = 12'h044;
  localparam bit [11:0] CSC_D_RELEASE       = 12'h048;
  localparam bit [11:0] CSC_D_BANK          = 12'h05c;
  localparam bit [31:0] CSC_MISC_MASK  = 32'h1111_3301; // skip_w/d_rls,w/d_reuse,proc,in,conv_mode
  localparam bit [31:0] CSC_MISC_RST   = 32'h0000_1100; // in/proc_precision=01
  localparam bit [31:0] CSC_BANK_MASK  = 32'h000F_000F;
  localparam bit [31:0] CSC_ATOMICS_MASK = 32'h001F_FFFF;

  // ---- CMAC（A/B 同）----
  localparam bit [31:0] CMAC_MISC_MASK = 32'h0000_3001; // proc_precision[13:12],conv_mode[0]
  localparam bit [31:0] CMAC_MISC_RST  = 32'h0000_1000; // proc_precision=01

  // ---- CACC ----
  localparam bit [11:0] CACC_D_DATAOUT_ADDR = 12'h018;
  localparam bit [11:0] CACC_D_LINE_STRIDE  = 12'h020;
  localparam bit [11:0] CACC_D_DATAOUT_MAP  = 12'h028;
  localparam bit [11:0] CACC_D_CLIP_CFG     = 12'h02c;
  localparam bit [31:0] CACC_MISC_MASK   = 32'h0000_3001;
  localparam bit [31:0] CACC_MISC_RST    = 32'h0000_1000;
  localparam bit [31:0] CACC_DOUT_ADDR_MASK = 32'hFFFF_FFE0; // dataout_addr[26:0]<<5
  localparam bit [31:0] CACC_LSTRIDE_MASK   = 32'h00FF_FFE0; // line_stride[18:0]<<5
  localparam bit [31:0] CACC_DMAP_MASK      = 32'h0001_0001; // surf/line_packed
  localparam bit [31:0] CACC_CLIP_MASK      = 32'h0000_001F;

  `uvm_object_utils(ccc_t0_reg_seq)

  function new(string name = "ccc_t0_reg_seq");
    super.new(name);
  endfunction

  // 写读比对：读回值应 == 写值 & 可写位 mask
  task rw_check(input csb_tgt_e tgt, input bit [11:0] off, input bit [31:0] mask,
                input bit [31:0] wr, input string tag);
    bit [31:0] rd;
    csb_write(tgt, off, wr);
    csb_read(tgt, off, rd);
    if (rd !== (wr & mask))
      `uvm_error(get_type_name(),
                 $sformatf("%s RW: tgt=%s off=0x%03h wr=0x%08h exp=0x%08h got=0x%08h",
                           tag, tgt.name(), off, wr, wr & mask, rd))
    else
      `uvm_info(get_type_name(),
                $sformatf("%s RW: tgt=%s off=0x%03h wr=0x%08h rd=0x%08h OK",
                          tag, tgt.name(), off, wr, rd), UVM_MEDIUM)
  endtask

  // S_POINTER 乒乓影子样板：producer 切换后 D 组读写落到对应影子组，双向保值
  task shadow_check(input csb_tgt_e tgt, input bit [11:0] off, input bit [31:0] mask,
                    input bit [31:0] v0, input bit [31:0] v1, input bit [31:0] rst_v,
                    input string tag);
    // producer=0 写 d0
    csb_write(tgt, S_POINTER, 32'h0);
    csb_write(tgt, off, v0);
    csb_check(tgt, off, v0 & mask, {tag, " shadow d0 wr"});
    // 切 producer=1：D 组落 d1（仍是复位值）
    csb_write(tgt, S_POINTER, 32'h1);
    csb_check(tgt, S_POINTER, 32'h0000_0001, {tag, " S_POINTER producer=1"});
    csb_check(tgt, off, rst_v, {tag, " shadow d1 rst"});
    csb_write(tgt, off, v1);
    csb_check(tgt, off, v1 & mask, {tag, " shadow d1 wr"});
    // 切回 producer=0：d0 旧值仍在
    csb_write(tgt, S_POINTER, 32'h0);
    csb_check(tgt, off, v0 & mask, {tag, " shadow d0 keep"});
    // 再切 producer=1：d1 值也仍在
    csb_write(tgt, S_POINTER, 32'h1);
    csb_check(tgt, off, v1 & mask, {tag, " shadow d1 keep"});
    // 恢复：两组都写回复位值，producer 归 0
    csb_write(tgt, off, rst_v);
    csb_write(tgt, S_POINTER, 32'h0);
    csb_write(tgt, off, rst_v);
  endtask

  // 块内偏移扫描读（不比对值，只验证不挂/不 X）
  task scan_check(input csb_tgt_e tgt, input bit [11:0] hi, input string tag);
    bit [31:0] rd;
    for (int unsigned off = 0; off <= hi; off += 4) begin
      csb_read(tgt, 12'(off), rd);
      `uvm_info(get_type_name(),
                $sformatf("%s scan off=0x%03h rd=0x%08h", tag, off, rd), UVM_HIGH)
    end
  endtask

  virtual task body();
    // =============== 1. 复位值读 ===============
    // CSC
    csb_check(CSB_TGT_CSC, S_STATUS,    32'h0,        "rst CSC S_STATUS");
    csb_check(CSB_TGT_CSC, S_POINTER,   32'h0,        "rst CSC S_POINTER");
    csb_check(CSB_TGT_CSC, D_OP_ENABLE, 32'h0,        "rst CSC D_OP_ENABLE");
    csb_check(CSB_TGT_CSC, D_MISC_CFG,  CSC_MISC_RST, "rst CSC D_MISC_CFG");
    csb_check(CSB_TGT_CSC, CSC_D_ATOMICS, 32'h1,      "rst CSC D_ATOMICS");
    csb_check(CSB_TGT_CSC, CSC_D_RELEASE, 32'h1,      "rst CSC D_RELEASE");
    csb_check(CSB_TGT_CSC, CSC_D_BANK,    32'h0,      "rst CSC D_BANK");
    // CMAC A / B（极简寄存器组：S_STATUS/S_POINTER/D_OP_ENABLE/D_MISC_CFG 共 4 个）
    csb_check(CSB_TGT_CMAC_A, S_STATUS,    32'h0,         "rst CMAC_A S_STATUS");
    csb_check(CSB_TGT_CMAC_A, S_POINTER,   32'h0,         "rst CMAC_A S_POINTER");
    csb_check(CSB_TGT_CMAC_A, D_OP_ENABLE, 32'h0,         "rst CMAC_A D_OP_ENABLE");
    csb_check(CSB_TGT_CMAC_A, D_MISC_CFG,  CMAC_MISC_RST, "rst CMAC_A D_MISC_CFG");
    csb_check(CSB_TGT_CMAC_B, S_STATUS,    32'h0,         "rst CMAC_B S_STATUS");
    csb_check(CSB_TGT_CMAC_B, S_POINTER,   32'h0,         "rst CMAC_B S_POINTER");
    csb_check(CSB_TGT_CMAC_B, D_OP_ENABLE, 32'h0,         "rst CMAC_B D_OP_ENABLE");
    csb_check(CSB_TGT_CMAC_B, D_MISC_CFG,  CMAC_MISC_RST, "rst CMAC_B D_MISC_CFG");
    // CACC
    csb_check(CSB_TGT_CACC, S_STATUS,    32'h0,         "rst CACC S_STATUS");
    csb_check(CSB_TGT_CACC, S_POINTER,   32'h0,         "rst CACC S_POINTER");
    csb_check(CSB_TGT_CACC, D_OP_ENABLE, 32'h0,         "rst CACC D_OP_ENABLE");
    csb_check(CSB_TGT_CACC, D_MISC_CFG,  CACC_MISC_RST, "rst CACC D_MISC_CFG");
    csb_check(CSB_TGT_CACC, CACC_D_DATAOUT_ADDR, 32'h0, "rst CACC D_DATAOUT_ADDR");
    csb_check(CSB_TGT_CACC, CACC_D_CLIP_CFG,     32'h0, "rst CACC D_CLIP_CFG");

    // =============== 2. 代表性 D 寄存器 mask 化写读 ===============
    // CSC
    rw_check(CSB_TGT_CSC, D_MISC_CFG, CSC_MISC_MASK, 32'hFFFF_FFFF, "CSC D_MISC_CFG");
    rw_check(CSB_TGT_CSC, D_MISC_CFG, CSC_MISC_MASK, 32'hA5A5_A5A5, "CSC D_MISC_CFG");
    rw_check(CSB_TGT_CSC, D_MISC_CFG, CSC_MISC_MASK, 32'h0000_0000, "CSC D_MISC_CFG");
    csb_write(CSB_TGT_CSC, D_MISC_CFG, CSC_MISC_RST); // 恢复
    rw_check(CSB_TGT_CSC, CSC_D_DATAIN_FORMAT, 32'h1, 32'hFFFF_FFFF, "CSC D_DATAIN_FORMAT");
    csb_write(CSB_TGT_CSC, CSC_D_DATAIN_FORMAT, 32'h0);
    rw_check(CSB_TGT_CSC, CSC_D_ATOMICS, CSC_ATOMICS_MASK, 32'hFFFF_FFFF, "CSC D_ATOMICS");
    csb_write(CSB_TGT_CSC, CSC_D_ATOMICS, 32'h1);
    // D_BANK 不可写全 1：csc/u_wl 有纯组合的配置合法性断言（data/weight bank
    // overflow，zzz_assert_never_11x/12x，不看 op_en，寄存器值一非法立即炸）。
    // 用两个合法组合覆盖两字段全部 4 bit + 掩掉位读 0（(d+1)+(w+1) <= 16）
    rw_check(CSB_TGT_CSC, CSC_D_BANK, CSC_BANK_MASK, 32'hFFF8_FFF6, "CSC D_BANK"); // d=6,w=8
    rw_check(CSB_TGT_CSC, CSC_D_BANK, CSC_BANK_MASK, 32'hFFF6_FFF8, "CSC D_BANK"); // d=8,w=6
    rw_check(CSB_TGT_CSC, CSC_D_BANK, CSC_BANK_MASK, 32'h0000_0000, "CSC D_BANK");
    // CMAC A / B
    rw_check(CSB_TGT_CMAC_A, D_MISC_CFG, CMAC_MISC_MASK, 32'hFFFF_FFFF, "CMAC_A D_MISC_CFG");
    rw_check(CSB_TGT_CMAC_A, D_MISC_CFG, CMAC_MISC_MASK, 32'h5A5A_5A5A, "CMAC_A D_MISC_CFG");
    csb_write(CSB_TGT_CMAC_A, D_MISC_CFG, CMAC_MISC_RST);
    rw_check(CSB_TGT_CMAC_B, D_MISC_CFG, CMAC_MISC_MASK, 32'hFFFF_FFFF, "CMAC_B D_MISC_CFG");
    rw_check(CSB_TGT_CMAC_B, D_MISC_CFG, CMAC_MISC_MASK, 32'hA5A5_A5A5, "CMAC_B D_MISC_CFG");
    csb_write(CSB_TGT_CMAC_B, D_MISC_CFG, CMAC_MISC_RST);
    // CACC
    rw_check(CSB_TGT_CACC, D_MISC_CFG, CACC_MISC_MASK, 32'hFFFF_FFFF, "CACC D_MISC_CFG");
    csb_write(CSB_TGT_CACC, D_MISC_CFG, CACC_MISC_RST);
    rw_check(CSB_TGT_CACC, CACC_D_DATAOUT_ADDR, CACC_DOUT_ADDR_MASK, 32'hFFFF_FFFF, "CACC D_DATAOUT_ADDR");
    rw_check(CSB_TGT_CACC, CACC_D_DATAOUT_ADDR, CACC_DOUT_ADDR_MASK, 32'h0000_0000, "CACC D_DATAOUT_ADDR");
    rw_check(CSB_TGT_CACC, CACC_D_LINE_STRIDE, CACC_LSTRIDE_MASK, 32'hFFFF_FFFF, "CACC D_LINE_STRIDE");
    csb_write(CSB_TGT_CACC, CACC_D_LINE_STRIDE, 32'h0);
    rw_check(CSB_TGT_CACC, CACC_D_DATAOUT_MAP, CACC_DMAP_MASK, 32'hFFFF_FFFF, "CACC D_DATAOUT_MAP");
    csb_write(CSB_TGT_CACC, CACC_D_DATAOUT_MAP, 32'h0);
    rw_check(CSB_TGT_CACC, CACC_D_CLIP_CFG, CACC_CLIP_MASK, 32'hFFFF_FFFF, "CACC D_CLIP_CFG");
    csb_write(CSB_TGT_CACC, CACC_D_CLIP_CFG, 32'h0);

    // =============== 3. S_POINTER 乒乓影子（每单元一个代表 D 寄存器） =========
    shadow_check(CSB_TGT_CSC,    CSC_D_BANK,          CSC_BANK_MASK,
                 32'h0003_0002, 32'h0005_0004, 32'h0,          "CSC");
    shadow_check(CSB_TGT_CMAC_A, D_MISC_CFG,          CMAC_MISC_MASK,
                 32'h0000_0001, 32'h0000_3001, CMAC_MISC_RST,  "CMAC_A");
    shadow_check(CSB_TGT_CMAC_B, D_MISC_CFG,          CMAC_MISC_MASK,
                 32'h0000_2001, 32'h0000_0001, CMAC_MISC_RST,  "CMAC_B");
    shadow_check(CSB_TGT_CACC,   CACC_D_DATAOUT_ADDR, CACC_DOUT_ADDR_MASK,
                 32'h0000_0040, 32'h0000_1240, 32'h0,          "CACC");

    // =============== 4. 块内偏移扫描（各单元实现范围） ===============
    scan_check(CSB_TGT_CSC,    12'h064, "CSC");    // 0x000-0x064（D_CYA 止）
    scan_check(CSB_TGT_CMAC_A, 12'h00c, "CMAC_A"); // 0x000-0x00c
    scan_check(CSB_TGT_CMAC_B, 12'h00c, "CMAC_B");
    scan_check(CSB_TGT_CACC,   12'h034, "CACC");   // 0x000-0x034（D_CYA 止）

    // =============== 5. 4 目标互不串 ===============
    // 4 家各写一个特征值 -> 依次读回全部 4 家（任一家写窜到别家立即暴露）
    csb_write(CSB_TGT_CSC,    CSC_D_BANK,          32'h0003_0002);
    csb_write(CSB_TGT_CMAC_A, D_MISC_CFG,          32'h0000_2001);
    csb_write(CSB_TGT_CMAC_B, D_MISC_CFG,          32'h0000_1001);
    csb_write(CSB_TGT_CACC,   CACC_D_DATAOUT_ADDR, 32'h0000_0040);
    csb_check(CSB_TGT_CSC,    CSC_D_BANK,          32'h0003_0002, "isolation CSC");
    csb_check(CSB_TGT_CMAC_A, D_MISC_CFG,          32'h0000_2001, "isolation CMAC_A");
    csb_check(CSB_TGT_CMAC_B, D_MISC_CFG,          32'h0000_1001, "isolation CMAC_B");
    csb_check(CSB_TGT_CACC,   CACC_D_DATAOUT_ADDR, 32'h0000_0040, "isolation CACC");
    // 反向：改写 CSC 后复读其余 3 家不受扰（值须过 bank 合法性断言，d=5,w=7）
    csb_write(CSB_TGT_CSC,    CSC_D_BANK,          32'h0007_0005);
    csb_check(CSB_TGT_CMAC_A, D_MISC_CFG,          32'h0000_2001, "isolation CMAC_A after CSC wr");
    csb_check(CSB_TGT_CMAC_B, D_MISC_CFG,          32'h0000_1001, "isolation CMAC_B after CSC wr");
    csb_check(CSB_TGT_CACC,   CACC_D_DATAOUT_ADDR, 32'h0000_0040, "isolation CACC after CSC wr");
    // 恢复复位态
    csb_write(CSB_TGT_CSC,    CSC_D_BANK,          32'h0);
    csb_write(CSB_TGT_CMAC_A, D_MISC_CFG,          CMAC_MISC_RST);
    csb_write(CSB_TGT_CMAC_B, D_MISC_CFG,          CMAC_MISC_RST);
    csb_write(CSB_TGT_CACC,   CACC_D_DATAOUT_ADDR, 32'h0);
  endtask

endclass : ccc_t0_reg_seq

`endif // CCC_T0_REG_SEQ_SVH
