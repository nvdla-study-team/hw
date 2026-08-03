// -----------------------------------------------------------------------------
// cdp_t0_reg_seq : T0 双块寄存器冒烟（CDP_RDMA 0xe000 / CDP 0xf000）
//   对两个目标各做：
//     1. 复位值读（S_STATUS/S_POINTER + 代表 D 寄存器）
//     2. 代表性 D 寄存器 mask 化写读（期望 = 写值 & 字段 mask，掩掉位读 0）
//     3. S_POINTER 乒乓影子（producer 切换，d0/d1 独立保值）
//     4. 块内偏移扫描读不挂（CDP 块跳过 0x008/0x00c，见下）
//   末尾做 2 目标互不串验证
//   全程不写 D_OP_ENABLE（RDMA 0x008 / CDP 0x048）：reg 层有 "Write group
//   registers when OP_EN is set" 断言（NV_NVDLA_CDP_reg.v:683/:730），且 op_en
//   会启动数据通路，T0 保持纯寄存器面
//   全程不碰 S_LUT_ACCESS_CFG(0xf008)/DATA(0xf00c)：写 0x008/0x00c 出
//   lut_addr/data_trigger（CDP_REG_single.v:204-205，装载 LUT 指针/写 LUT 表项），
//   读 0x00c 在 lut_access_type==0（复位值即 READ）时触发 LUT 地址自增
//   （NV_NVDLA_CDP_reg.v:1040 reg2dp_lut_data_rd_trigger）——扫描跳过这两个 offset
//   寄存器事实源（outdir/nv_full/vmod/nvdla/cdp/）：
//     NV_NVDLA_CDP_RDMA_REG_single.v:54-57（0x000/0x004）、
//       RDMA_REG_dual.v:99-130（offset/拼接）、:207-217（复位块，全 0）
//     NV_NVDLA_CDP_REG_single.v:168-205（S 组 offset/触发）、:291-318（复位全 0）、
//       CDP_REG_dual.v:169-227（offset/拼接）、:358-378（复位：input_data_type=01、
//       datin_scale=1、datout_scale=1，其余 0）
// -----------------------------------------------------------------------------
`ifndef CDP_T0_REG_SEQ_SVH
`define CDP_T0_REG_SEQ_SVH

class cdp_t0_reg_seq extends cdp_csb_base_seq;

  // ---- 公共偏移（两块同构） ----
  localparam bit [11:0] S_STATUS  = 12'h000;
  localparam bit [11:0] S_POINTER = 12'h004;

  // ---- CDP_RDMA（块 0xe；D 组 0x008-0x040）----
  localparam bit [11:0] R_D_OP_ENABLE     = 12'h008; // 只读复位值，不写
  localparam bit [11:0] R_D_CUBE_WIDTH    = 12'h00c;
  localparam bit [11:0] R_D_CUBE_HEIGHT   = 12'h010;
  localparam bit [11:0] R_D_CUBE_CHANNEL  = 12'h014;
  localparam bit [11:0] R_D_SRC_ADDR_LOW  = 12'h018;
  localparam bit [11:0] R_D_SRC_ADDR_HIGH = 12'h01c;
  localparam bit [11:0] R_D_SRC_DMA_CFG   = 12'h028;
  localparam bit [11:0] R_D_DATA_FORMAT   = 12'h034;
  localparam bit [11:0] R_SCAN_HI         = 12'h040; // D_CYA 止
  localparam bit [31:0] R_CUBE_MASK      = 32'h0000_1FFF; // width/height/channel[12:0]
  localparam bit [31:0] R_ADDR_LOW_MASK  = 32'hFFFF_FFE0; // src_base_addr_low[26:0]<<5
  localparam bit [31:0] R_ADDR_HIGH_MASK = 32'hFFFF_FFFF;
  localparam bit [31:0] R_RAM_TYPE_MASK  = 32'h0000_0001; // src_ram_type
  localparam bit [31:0] R_DFMT_MASK      = 32'h0000_0003; // input_data[1:0]

  // ---- CDP（块 0xf；S 组 0x000-0x044、D 组 0x048-0x0b8）----
  localparam bit [11:0] C_S_LUT_ACCESS_CFG  = 12'h008; // 不碰（trigger 副作用）
  localparam bit [11:0] C_S_LUT_ACCESS_DATA = 12'h00c; // 不碰（读也自增 LUT 指针）
  localparam bit [11:0] C_S_LUT_CFG         = 12'h010;
  localparam bit [11:0] C_S_LUT_INFO        = 12'h014;
  localparam bit [11:0] C_D_OP_ENABLE       = 12'h048; // 只读复位值，不写
  localparam bit [11:0] C_D_FUNC_BYPASS     = 12'h04c;
  localparam bit [11:0] C_D_DST_ADDR_LOW    = 12'h050;
  localparam bit [11:0] C_D_DST_ADDR_HIGH   = 12'h054;
  localparam bit [11:0] C_D_DST_DMA_CFG     = 12'h060;
  localparam bit [11:0] C_D_DATA_FORMAT     = 12'h068;
  localparam bit [11:0] C_D_DATIN_SCALE     = 12'h078;
  localparam bit [11:0] C_D_DATOUT_SCALE    = 12'h084;
  localparam bit [11:0] C_D_CYA             = 12'h0b8;
  localparam bit [11:0] C_SCAN_HI           = 12'h0b8; // D_CYA 止
  localparam bit [31:0] C_LUT_CFG_MASK   = 32'h0000_0071; // hybrid/oflow/uflow_pri[6:4],le_function[0]
  localparam bit [31:0] C_LUT_INFO_MASK  = 32'h00FF_FFFF; // lo_idx/le_idx/le_off 各 8b
  localparam bit [31:0] C_BYPASS_MASK    = 32'h0000_0003; // mul_bypass,sqsum_bypass
  localparam bit [31:0] C_ADDR_LOW_MASK  = 32'hFFFF_FFE0; // dst_base_addr_low[26:0]<<5
  localparam bit [31:0] C_ADDR_HIGH_MASK = 32'hFFFF_FFFF;
  localparam bit [31:0] C_RAM_TYPE_MASK  = 32'h0000_0001; // dst_ram_type
  localparam bit [31:0] C_DFMT_MASK      = 32'h0000_0003; // input_data_type[1:0]
  localparam bit [31:0] C_DFMT_RST       = 32'h0000_0001; // 复位 2'b01（REG_dual.v:361）
  localparam bit [31:0] C_SCALE_MASK     = 32'h0000_FFFF;
  localparam bit [31:0] C_SCALE_RST      = 32'h0000_0001; // datin/datout_scale 复位 1
  localparam bit [31:0] C_CYA_MASK       = 32'hFFFF_FFFF;

  `uvm_object_utils(cdp_t0_reg_seq)

  function new(string name = "cdp_t0_reg_seq");
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

  // 块内偏移扫描读（不比对值，只验证不挂/不 X；skip0/skip1 跳过副作用 offset）
  task scan_check(input csb_tgt_e tgt, input bit [11:0] hi, input string tag,
                  input int skip0 = -1, input int skip1 = -1);
    bit [31:0] rd;
    for (int unsigned off = 0; off <= hi; off += 4) begin
      if (int'(off) == skip0 || int'(off) == skip1) begin
        `uvm_info(get_type_name(),
                  $sformatf("%s scan off=0x%03h SKIPPED (LUT access side effect)",
                            tag, off), UVM_MEDIUM)
        continue;
      end
      csb_read(tgt, 12'(off), rd);
      `uvm_info(get_type_name(),
                $sformatf("%s scan off=0x%03h rd=0x%08h", tag, off, rd), UVM_HIGH)
    end
  endtask

  virtual task body();
    // =============== 1. 复位值读 ===============
    // CDP_RDMA（复位块全 0：CDP_RDMA_REG_dual.v:207-217）
    csb_check(CSB_TGT_CDP_RDMA, S_STATUS,        32'h0, "rst RDMA S_STATUS");
    csb_check(CSB_TGT_CDP_RDMA, S_POINTER,       32'h0, "rst RDMA S_POINTER");
    csb_check(CSB_TGT_CDP_RDMA, R_D_OP_ENABLE,   32'h0, "rst RDMA D_OP_ENABLE");
    csb_check(CSB_TGT_CDP_RDMA, R_D_CUBE_WIDTH,  32'h0, "rst RDMA D_DATA_CUBE_WIDTH");
    csb_check(CSB_TGT_CDP_RDMA, R_D_SRC_DMA_CFG, 32'h0, "rst RDMA D_SRC_DMA_CFG");
    csb_check(CSB_TGT_CDP_RDMA, R_D_DATA_FORMAT, 32'h0, "rst RDMA D_DATA_FORMAT");
    // CDP（input_data_type=01、datin/datout_scale=1，其余 0）
    csb_check(CSB_TGT_CDP, S_STATUS,        32'h0,       "rst CDP S_STATUS");
    csb_check(CSB_TGT_CDP, S_POINTER,       32'h0,       "rst CDP S_POINTER");
    csb_check(CSB_TGT_CDP, C_S_LUT_CFG,     32'h0,       "rst CDP S_LUT_CFG");
    csb_check(CSB_TGT_CDP, C_D_OP_ENABLE,   32'h0,       "rst CDP D_OP_ENABLE");
    csb_check(CSB_TGT_CDP, C_D_DATA_FORMAT, C_DFMT_RST,  "rst CDP D_DATA_FORMAT");
    csb_check(CSB_TGT_CDP, C_D_DATIN_SCALE, C_SCALE_RST, "rst CDP D_DATIN_SCALE");
    csb_check(CSB_TGT_CDP, C_D_DATOUT_SCALE,C_SCALE_RST, "rst CDP D_DATOUT_SCALE");

    // =============== 2. 代表性寄存器 mask 化写读 ===============
    // CDP_RDMA
    rw_check(CSB_TGT_CDP_RDMA, R_D_CUBE_WIDTH, R_CUBE_MASK, 32'hFFFF_FFFF, "RDMA D_CUBE_WIDTH");
    rw_check(CSB_TGT_CDP_RDMA, R_D_CUBE_WIDTH, R_CUBE_MASK, 32'hA5A5_A5A5, "RDMA D_CUBE_WIDTH");
    csb_write(CSB_TGT_CDP_RDMA, R_D_CUBE_WIDTH, 32'h0); // 恢复
    rw_check(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_LOW, R_ADDR_LOW_MASK, 32'hFFFF_FFFF, "RDMA D_SRC_ADDR_LOW");
    rw_check(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_LOW, R_ADDR_LOW_MASK, 32'h5A5A_5A5A, "RDMA D_SRC_ADDR_LOW");
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_LOW, 32'h0);
    rw_check(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, R_ADDR_HIGH_MASK, 32'hA5A5_A5A5, "RDMA D_SRC_ADDR_HIGH");
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'h0);
    rw_check(CSB_TGT_CDP_RDMA, R_D_SRC_DMA_CFG, R_RAM_TYPE_MASK, 32'hFFFF_FFFF, "RDMA D_SRC_DMA_CFG");
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_DMA_CFG, 32'h0);
    rw_check(CSB_TGT_CDP_RDMA, R_D_DATA_FORMAT, R_DFMT_MASK, 32'hFFFF_FFFF, "RDMA D_DATA_FORMAT");
    csb_write(CSB_TGT_CDP_RDMA, R_D_DATA_FORMAT, 32'h0);
    // CDP：S 组代表（LUT 参数寄存器，无 trigger 副作用）+ D 组代表
    rw_check(CSB_TGT_CDP, C_S_LUT_INFO, C_LUT_INFO_MASK, 32'hFFFF_FFFF, "CDP S_LUT_INFO");
    rw_check(CSB_TGT_CDP, C_S_LUT_INFO, C_LUT_INFO_MASK, 32'hA5A5_A5A5, "CDP S_LUT_INFO");
    csb_write(CSB_TGT_CDP, C_S_LUT_INFO, 32'h0);
    rw_check(CSB_TGT_CDP, C_S_LUT_CFG, C_LUT_CFG_MASK, 32'hFFFF_FFFF, "CDP S_LUT_CFG");
    csb_write(CSB_TGT_CDP, C_S_LUT_CFG, 32'h0);
    rw_check(CSB_TGT_CDP, C_D_FUNC_BYPASS, C_BYPASS_MASK, 32'hFFFF_FFFF, "CDP D_FUNC_BYPASS");
    csb_write(CSB_TGT_CDP, C_D_FUNC_BYPASS, 32'h0);
    rw_check(CSB_TGT_CDP, C_D_DST_ADDR_LOW, C_ADDR_LOW_MASK, 32'hFFFF_FFFF, "CDP D_DST_ADDR_LOW");
    rw_check(CSB_TGT_CDP, C_D_DST_ADDR_LOW, C_ADDR_LOW_MASK, 32'hA5A5_A5A5, "CDP D_DST_ADDR_LOW");
    csb_write(CSB_TGT_CDP, C_D_DST_ADDR_LOW, 32'h0);
    rw_check(CSB_TGT_CDP, C_D_DST_DMA_CFG, C_RAM_TYPE_MASK, 32'hFFFF_FFFF, "CDP D_DST_DMA_CFG");
    csb_write(CSB_TGT_CDP, C_D_DST_DMA_CFG, 32'h0);
    rw_check(CSB_TGT_CDP, C_D_DATA_FORMAT, C_DFMT_MASK, 32'hFFFF_FFFF, "CDP D_DATA_FORMAT");
    csb_write(CSB_TGT_CDP, C_D_DATA_FORMAT, C_DFMT_RST); // 恢复复位值 01
    rw_check(CSB_TGT_CDP, C_D_CYA, C_CYA_MASK, 32'h5A5A_A5A5, "CDP D_CYA");
    csb_write(CSB_TGT_CDP, C_D_CYA, 32'h0);

    // =============== 3. S_POINTER 乒乓影子（每块一个代表 D 寄存器） =========
    shadow_check(CSB_TGT_CDP_RDMA, R_D_CUBE_WIDTH,   R_CUBE_MASK,
                 32'h0000_0123, 32'h0000_1ABC, 32'h0, "RDMA");
    shadow_check(CSB_TGT_CDP,      C_D_DST_ADDR_HIGH, C_ADDR_HIGH_MASK,
                 32'h1111_2222, 32'h3333_4444, 32'h0, "CDP");

    // =============== 4. 块内偏移扫描 ===============
    scan_check(CSB_TGT_CDP_RDMA, R_SCAN_HI, "RDMA"); // 0x000-0x040 全读
    // CDP 0x000-0x0b8，跳过 0x008/0x00c（S_LUT_ACCESS_*：读 0x00c 触发
    // LUT 地址自增，NV_NVDLA_CDP_reg.v:1040；决策记录方案书 §4.6）
    scan_check(CSB_TGT_CDP, C_SCAN_HI, "CDP",
               int'(C_S_LUT_ACCESS_CFG), int'(C_S_LUT_ACCESS_DATA));

    // =============== 5. 2 目标互不串 ===============
    // 两家各写一个特征值 -> 依次读回（任一家写窜到别家立即暴露）
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'hA5A5_0001);
    csb_write(CSB_TGT_CDP,      C_D_DST_ADDR_HIGH, 32'h5A5A_0002);
    csb_check(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'hA5A5_0001, "isolation RDMA");
    csb_check(CSB_TGT_CDP,      C_D_DST_ADDR_HIGH, 32'h5A5A_0002, "isolation CDP");
    // 反向：改写 RDMA 后复读 CDP 不受扰
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'h0000_BEEF);
    csb_check(CSB_TGT_CDP,      C_D_DST_ADDR_HIGH, 32'h5A5A_0002, "isolation CDP after RDMA wr");
    csb_check(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'h0000_BEEF, "isolation RDMA rewrite");
    // 恢复复位态
    csb_write(CSB_TGT_CDP_RDMA, R_D_SRC_ADDR_HIGH, 32'h0);
    csb_write(CSB_TGT_CDP,      C_D_DST_ADDR_HIGH, 32'h0);
  endtask

endclass : cdp_t0_reg_seq

`endif // CDP_T0_REG_SEQ_SVH
