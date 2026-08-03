// -----------------------------------------------------------------------------
// pdp_t0_reg_seq : T0 双 reg 块寄存器冒烟（PDP_RDMA=0xc / PDP=0xd），纯 CSB 面
//   ① 复位值读（两块 S_STATUS/S_POINTER + 代表 D 寄存器；两块 D 组复位全 0）
//   ② 代表 D 寄存器 mask 化写读比对（期望 = 写值 & 字段 mask）
//   ③ S_POINTER 乒乓影子各一例（D_CYA 载体）
//   ④ 块内偏移扫描读不挂（PDP 0x000-0x09c / PDP_RDMA 0x000-0x04c；REG_single/
//      dual 实读确认读路径纯组合 mux、无读副作用寄存器，未译码偏移读回 0）
//   ⑤ 双块互不串（同偏移 0x00c 两块各写特征值互读 + D_CYA 交叉复读）
//   全程不写 D_OP_ENABLE（0x008）：op_en 置位会启动数据通路且带 D 组写保护断言
//   （PDP_reg.v:693/:740 "Write group registers when OP_EN is set"）；全用 nposted 写
//   寄存器事实源（outdir/nv_full/vmod/nvdla/pdp/）：
//     NV_NVDLA_PDP_REG_single.v:54-57（S 组译码/拼装）
//     NV_NVDLA_PDP_REG_dual.v:228-265（D 组译码）、:266-303（读拼装=字段 mask）、
//       :470-516（复位块全 0）
//     NV_NVDLA_PDP_RDMA_REG_single.v 同构；RDMA_REG_dual.v:124-141/:142-159/:246-266
// -----------------------------------------------------------------------------
`ifndef PDP_T0_REG_SEQ_SVH
`define PDP_T0_REG_SEQ_SVH

class pdp_t0_reg_seq extends pdp_csb_base_seq;

  // ---- 公共偏移（两块同构） ----
  localparam bit [11:0] S_STATUS    = 12'h000;
  localparam bit [11:0] S_POINTER   = 12'h004;
  localparam bit [11:0] D_OP_ENABLE = 12'h008; // 只读复位值，不写

  // ---- PDP（0xd 块）代表 D 寄存器（REG_dual.v 实读推导）----
  localparam bit [11:0] PDP_D_CUBE_IN_WIDTH  = 12'h00c; // cube_in_width[12:0]
  localparam bit [11:0] PDP_D_OP_MODE_CFG    = 12'h024; // split[15:8],fly[4],method[1:0]
  localparam bit [11:0] PDP_D_KERNEL_CFG     = 12'h034; // ksh[23:20],ksw[19:16],kh[11:8],kw[3:0]
  localparam bit [11:0] PDP_D_DST_BASE_LOW   = 12'h070; // dst_base_addr_low[31:5]
  localparam bit [11:0] PDP_D_DST_RAM_CFG    = 12'h080; // dst_ram_type[0]
  localparam bit [11:0] PDP_D_CYA            = 12'h09c; // cya[31:0]
  localparam bit [31:0] PDP_CUBE_MASK     = 32'h0000_1FFF;
  localparam bit [31:0] PDP_OPMODE_MASK   = 32'h0000_FF13;
  localparam bit [31:0] PDP_KERNEL_MASK   = 32'h00FF_0F0F;
  localparam bit [31:0] PDP_ADDR_MASK     = 32'hFFFF_FFE0;
  localparam bit [31:0] PDP_RAMCFG_MASK   = 32'h0000_0001;

  // ---- PDP_RDMA（0xc 块）代表 D 寄存器（RDMA_REG_dual.v 实读推导）----
  localparam bit [11:0] RDMA_D_CUBE_IN_WIDTH = 12'h00c; // cube_in_width[12:0]
  localparam bit [11:0] RDMA_D_FLYING_MODE   = 12'h018; // flying_mode[0]
  localparam bit [11:0] RDMA_D_SRC_BASE_LOW  = 12'h01c; // src_base_addr_low[31:5]
  localparam bit [11:0] RDMA_D_SRC_RAM_CFG   = 12'h02c; // src_ram_type[0]
  localparam bit [11:0] RDMA_D_KERNEL_CFG    = 12'h038; // ksw[7:4],kw[3:0]
  localparam bit [11:0] RDMA_D_CYA           = 12'h04c; // cya[31:0]
  localparam bit [31:0] RDMA_CUBE_MASK    = 32'h0000_1FFF;
  localparam bit [31:0] RDMA_FLY_MASK     = 32'h0000_0001;
  localparam bit [31:0] RDMA_ADDR_MASK    = 32'hFFFF_FFE0;
  localparam bit [31:0] RDMA_RAMCFG_MASK  = 32'h0000_0001;
  localparam bit [31:0] RDMA_KERNEL_MASK  = 32'h0000_00FF;

  `uvm_object_utils(pdp_t0_reg_seq)

  function new(string name = "pdp_t0_reg_seq");
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
  // （PDP/PDP_RDMA D 组复位值全 0，rst_v 恒 0）
  task shadow_check(input csb_tgt_e tgt, input bit [11:0] off, input bit [31:0] mask,
                    input bit [31:0] v0, input bit [31:0] v1, input string tag);
    // producer=0 写 d0
    csb_write(tgt, S_POINTER, 32'h0);
    csb_write(tgt, off, v0);
    csb_check(tgt, off, v0 & mask, {tag, " shadow d0 wr"});
    // 切 producer=1：D 组落 d1（仍是复位值 0）
    csb_write(tgt, S_POINTER, 32'h1);
    csb_check(tgt, S_POINTER, 32'h0000_0001, {tag, " S_POINTER producer=1"});
    csb_check(tgt, off, 32'h0, {tag, " shadow d1 rst"});
    csb_write(tgt, off, v1);
    csb_check(tgt, off, v1 & mask, {tag, " shadow d1 wr"});
    // 切回 producer=0：d0 旧值仍在
    csb_write(tgt, S_POINTER, 32'h0);
    csb_check(tgt, off, v0 & mask, {tag, " shadow d0 keep"});
    // 再切 producer=1：d1 值也仍在
    csb_write(tgt, S_POINTER, 32'h1);
    csb_check(tgt, off, v1 & mask, {tag, " shadow d1 keep"});
    // 恢复：两组都写回复位值 0，producer 归 0
    csb_write(tgt, off, 32'h0);
    csb_write(tgt, S_POINTER, 32'h0);
    csb_write(tgt, off, 32'h0);
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
    // =============== ① 复位值读（两块 D 组复位全 0） ===============
    // PDP（0xd）
    csb_check(CSB_TGT_PDP, S_STATUS,    32'h0, "rst PDP S_STATUS");
    csb_check(CSB_TGT_PDP, S_POINTER,   32'h0, "rst PDP S_POINTER");
    csb_check(CSB_TGT_PDP, D_OP_ENABLE, 32'h0, "rst PDP D_OP_ENABLE");
    csb_check(CSB_TGT_PDP, PDP_D_OP_MODE_CFG,  32'h0, "rst PDP D_OPERATION_MODE_CFG");
    csb_check(CSB_TGT_PDP, PDP_D_KERNEL_CFG,   32'h0, "rst PDP D_POOLING_KERNEL_CFG");
    csb_check(CSB_TGT_PDP, PDP_D_DST_RAM_CFG,  32'h0, "rst PDP D_DST_RAM_CFG");
    // PDP_RDMA（0xc）
    csb_check(CSB_TGT_PDP_RDMA, S_STATUS,    32'h0, "rst PDP_RDMA S_STATUS");
    csb_check(CSB_TGT_PDP_RDMA, S_POINTER,   32'h0, "rst PDP_RDMA S_POINTER");
    csb_check(CSB_TGT_PDP_RDMA, D_OP_ENABLE, 32'h0, "rst PDP_RDMA D_OP_ENABLE");
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_FLYING_MODE, 32'h0, "rst PDP_RDMA D_FLYING_MODE");
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_SRC_RAM_CFG, 32'h0, "rst PDP_RDMA D_SRC_RAM_CFG");

    // =============== ② 代表 D 寄存器 mask 化写读 ===============
    // PDP
    rw_check(CSB_TGT_PDP, PDP_D_CUBE_IN_WIDTH, PDP_CUBE_MASK, 32'hFFFF_FFFF, "PDP D_CUBE_IN_WIDTH");
    rw_check(CSB_TGT_PDP, PDP_D_CUBE_IN_WIDTH, PDP_CUBE_MASK, 32'hA5A5_A5A5, "PDP D_CUBE_IN_WIDTH");
    rw_check(CSB_TGT_PDP, PDP_D_CUBE_IN_WIDTH, PDP_CUBE_MASK, 32'h0000_0000, "PDP D_CUBE_IN_WIDTH");
    rw_check(CSB_TGT_PDP, PDP_D_OP_MODE_CFG, PDP_OPMODE_MASK, 32'hFFFF_FFFF, "PDP D_OPERATION_MODE_CFG");
    rw_check(CSB_TGT_PDP, PDP_D_OP_MODE_CFG, PDP_OPMODE_MASK, 32'h5A5A_5A5A, "PDP D_OPERATION_MODE_CFG");
    csb_write(CSB_TGT_PDP, PDP_D_OP_MODE_CFG, 32'h0); // 恢复
    // D_POOLING_KERNEL_CFG 不可写全 1：kernel_width/stride 有纯组合 overlap
    // 借位断言（不看 op_en）"PDP-CORE: should not overflow"——RDMA 侧
    // NV_NVDLA_PDP_RDMA_ig.v:698 组合式 + :727 断言（T0 首跑实测踩中）；
    // PDP 侧同式 NV_NVDLA_PDP_CORE_cal1d.v:1359/:1388。合法条件：
    // kw<ksw 时 ksw-kw[2:0] 不借位；否则 kw[2:0]-ksw 不借位（kw[3] 单独看）。
    // 用两个合法组合覆盖字段全部位 + 掩掉位读 0：
    //   kw=7/kh=7/ksw=7/ksh=7（低 3 位全 1）与 kw=8/kh=8/ksw=F/ksh=F（bit3+stride 全 1）
    rw_check(CSB_TGT_PDP, PDP_D_KERNEL_CFG, PDP_KERNEL_MASK, 32'hFF77_F7F7, "PDP D_POOLING_KERNEL_CFG"); // kw=7 kh=7 ksw=7 ksh=7
    rw_check(CSB_TGT_PDP, PDP_D_KERNEL_CFG, PDP_KERNEL_MASK, 32'h00FF_0808, "PDP D_POOLING_KERNEL_CFG"); // kw=8 kh=8 ksw=F ksh=F
    csb_write(CSB_TGT_PDP, PDP_D_KERNEL_CFG, 32'h0);
    rw_check(CSB_TGT_PDP, PDP_D_DST_BASE_LOW, PDP_ADDR_MASK, 32'hFFFF_FFFF, "PDP D_DST_BASE_ADDR_LOW");
    rw_check(CSB_TGT_PDP, PDP_D_DST_BASE_LOW, PDP_ADDR_MASK, 32'h0000_0000, "PDP D_DST_BASE_ADDR_LOW");
    rw_check(CSB_TGT_PDP, PDP_D_DST_RAM_CFG, PDP_RAMCFG_MASK, 32'hFFFF_FFFF, "PDP D_DST_RAM_CFG");
    csb_write(CSB_TGT_PDP, PDP_D_DST_RAM_CFG, 32'h0);
    rw_check(CSB_TGT_PDP, PDP_D_CYA, 32'hFFFF_FFFF, 32'hDEAD_BEEF, "PDP D_CYA");
    csb_write(CSB_TGT_PDP, PDP_D_CYA, 32'h0);
    // PDP_RDMA
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, RDMA_CUBE_MASK, 32'hFFFF_FFFF, "PDP_RDMA D_CUBE_IN_WIDTH");
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, RDMA_CUBE_MASK, 32'h5A5A_5A5A, "PDP_RDMA D_CUBE_IN_WIDTH");
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, 32'h0);
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_FLYING_MODE, RDMA_FLY_MASK, 32'hFFFF_FFFF, "PDP_RDMA D_FLYING_MODE");
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_FLYING_MODE, 32'h0);
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_SRC_BASE_LOW, RDMA_ADDR_MASK, 32'hFFFF_FFFF, "PDP_RDMA D_SRC_BASE_ADDR_LOW");
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_SRC_BASE_LOW, RDMA_ADDR_MASK, 32'h0000_0000, "PDP_RDMA D_SRC_BASE_ADDR_LOW");
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_SRC_RAM_CFG, RDMA_RAMCFG_MASK, 32'hFFFF_FFFF, "PDP_RDMA D_SRC_RAM_CFG");
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_SRC_RAM_CFG, 32'h0);
    // 同 PDP 侧：kernel overlap 借位断言限制，全 1 非法，用两个合法组合
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_KERNEL_CFG, RDMA_KERNEL_MASK, 32'hFFFF_FF77, "PDP_RDMA D_POOLING_KERNEL_CFG"); // kw=7 ksw=7
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_KERNEL_CFG, RDMA_KERNEL_MASK, 32'h0000_00F8, "PDP_RDMA D_POOLING_KERNEL_CFG"); // kw=8 ksw=F
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_KERNEL_CFG, 32'h0);
    rw_check(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'hFFFF_FFFF, 32'hCAFE_F00D, "PDP_RDMA D_CYA");
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'h0);

    // =============== ③ S_POINTER 乒乓影子（每块一个代表 D 寄存器） =========
    shadow_check(CSB_TGT_PDP,      PDP_D_CYA,  32'hFFFF_FFFF,
                 32'h1111_2222, 32'h3333_4444, "PDP");
    shadow_check(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'hFFFF_FFFF,
                 32'h5555_6666, 32'h7777_8888, "PDP_RDMA");

    // =============== ④ 块内偏移扫描（各块实现范围） ===============
    scan_check(CSB_TGT_PDP,      12'h09c, "PDP");      // 0x000-0x09c（D_CYA 止）
    scan_check(CSB_TGT_PDP_RDMA, 12'h04c, "PDP_RDMA"); // 0x000-0x04c（D_CYA 止）

    // =============== ⑤ 双块互不串 ===============
    // 同偏移 0x00c（两块都是 cube_in_width）各写特征值 -> 互读（译码窜块立即暴露）
    csb_write(CSB_TGT_PDP,      PDP_D_CUBE_IN_WIDTH,  32'h0000_0AAA);
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, 32'h0000_0555);
    csb_check(CSB_TGT_PDP,      PDP_D_CUBE_IN_WIDTH,  32'h0000_0AAA, "isolation PDP 0x00c");
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, 32'h0000_0555, "isolation PDP_RDMA 0x00c");
    // 不同偏移的 D_CYA 交叉：改写一家后复读另一家不受扰
    csb_write(CSB_TGT_PDP,      PDP_D_CYA,  32'hA0A0_0001);
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'hB0B0_0002);
    csb_check(CSB_TGT_PDP,      PDP_D_CYA,  32'hA0A0_0001, "isolation PDP D_CYA");
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'hB0B0_0002, "isolation PDP_RDMA D_CYA");
    csb_write(CSB_TGT_PDP, PDP_D_CYA, 32'hC0C0_0003);
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_CYA, 32'hB0B0_0002, "isolation PDP_RDMA after PDP wr");
    csb_check(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, 32'h0000_0555, "isolation PDP_RDMA 0x00c after PDP wr");
    // 恢复复位态
    csb_write(CSB_TGT_PDP,      PDP_D_CUBE_IN_WIDTH,  32'h0);
    csb_write(CSB_TGT_PDP,      PDP_D_CYA,            32'h0);
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CUBE_IN_WIDTH, 32'h0);
    csb_write(CSB_TGT_PDP_RDMA, RDMA_D_CYA,           32'h0);
  endtask

endclass : pdp_t0_reg_seq

`endif // PDP_T0_REG_SEQ_SVH
