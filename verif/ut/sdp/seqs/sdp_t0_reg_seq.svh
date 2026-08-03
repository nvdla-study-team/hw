// -----------------------------------------------------------------------------
// sdp_t0_reg_seq : T0 双 reg 块寄存器冒烟（SDP_RDMA=0xa / SDP=0xb），纯 CSB 面
//   ① 复位值读（S_STATUS/S_POINTER + 代表 D 寄存器）
//   ② 代表 D 寄存器 mask 化写读比对（期望 = 写值 & 字段 mask）
//   ③ S_POINTER 乒乓影子各一例（producer 切换，d0/d1 独立保值）
//   ④ 块内偏移扫描读不挂（SDP 主块跳过 0x00c，见下）
//   ⑤ 双块互不串（各写一特征值互读）
//   全程不写 D_OP_ENABLE（SDP 0x038 / RDMA 0x008）：两 wrapper 均有 "Write group
//   registers when OP_EN is set" 断言（NV_NVDLA_SDP_reg.v:1000/:1047），且 op_en
//   启动数据通路；全用 nposted 写保证串行完成
//   扫描回避决策（方案书 §4.6）：SDP 主块 S_LUT_ACCESS_DATA(0x00c) 读有副作用
//   ——LUT 内部指针在 lut_int_data_rd_trigger 上自增（NV_NVDLA_SDP_reg.v:1674、
//   :1691-1693），扫描跳过该 offset；S_LUT_ACCESS_CFG(0x008) 只有写触发器
//   （REG_single.v:166-167），读安全，不跳
//   寄存器事实源（outdir/nv_full/vmod/nvdla/sdp/）：
//     NV_NVDLA_SDP_REG_single.v:138-165（S 组译码/拼接）
//     NV_NVDLA_SDP_REG_dual.v:316-413（D 组译码/拼接）、:625-696（复位全 0）
//     NV_NVDLA_SDP_RDMA_REG_single.v:54-57、RDMA_REG_dual.v:232-301、
//       复位块（in/proc_precision=2'b01，其余 0）
// -----------------------------------------------------------------------------
`ifndef SDP_T0_REG_SEQ_SVH
`define SDP_T0_REG_SEQ_SVH

class sdp_t0_reg_seq extends sdp_csb_base_seq;

  // ---- 公共偏移 ----
  localparam bit [11:0] S_STATUS  = 12'h000;
  localparam bit [11:0] S_POINTER = 12'h004;

  // ---- SDP 主块（0xb000；D 组 0x038 起）----
  localparam bit [11:0] SDP_D_OP_ENABLE     = 12'h038; // 只读复位值，不写
  localparam bit [11:0] SDP_D_CUBE_WIDTH    = 12'h03c;
  localparam bit [11:0] SDP_D_CUBE_HEIGHT   = 12'h040;
  localparam bit [11:0] SDP_D_DST_ADDR_LOW  = 12'h048;
  localparam bit [11:0] SDP_D_DP_BS_CFG     = 12'h058;
  localparam bit [11:0] SDP_D_FEATURE_MODE  = 12'h0b0;
  localparam bit [11:0] SDP_D_DATA_FORMAT   = 12'h0bc;
  localparam bit [11:0] SDP_D_CVT_OFFSET    = 12'h0c0;
  localparam bit [11:0] SDP_D_PERF_ENABLE   = 12'h0dc;
  localparam bit [11:0] SDP_SCAN_HI         = 12'h0f8; // 末寄存器 D_PERF_LUT_LO_HIT
  localparam bit [11:0] SDP_SCAN_SKIP       = 12'h00c; // S_LUT_ACCESS_DATA 读自增

  localparam bit [31:0] SDP_CUBE_MASK  = 32'h0000_1FFF; // width/height/channel[12:0]
  localparam bit [31:0] SDP_ADDR_MASK  = 32'hFFFF_FFE0; // [26:0]<<5
  localparam bit [31:0] SDP_BSCFG_MASK = 32'h0000_007F; // relu_byp..bypass 7 位
  localparam bit [31:0] SDP_FMODE_MASK = 32'h0000_1F0F; // batch[12:8],n2z[3],wg[2],dst[1],fly[0]
  localparam bit [31:0] SDP_DFMT_MASK  = 32'h0000_000F; // out[3:2],proc[1:0]，复位 0
  localparam bit [31:0] SDP_CVTO_MASK  = 32'hFFFF_FFFF;
  localparam bit [31:0] SDP_PERF_MASK  = 32'h0000_000F;

  // ---- SDP_RDMA 块（0xa000；D 组 0x008 起）----
  localparam bit [11:0] RDMA_D_OP_ENABLE    = 12'h008; // 只读复位值，不写
  localparam bit [11:0] RDMA_D_CUBE_WIDTH   = 12'h00c;
  localparam bit [11:0] RDMA_D_SRC_ADDR_LOW = 12'h018;
  localparam bit [11:0] RDMA_D_BRDMA_CFG    = 12'h028;
  localparam bit [11:0] RDMA_D_FEATURE_MODE = 12'h070;
  localparam bit [11:0] RDMA_D_SRC_DMA_CFG  = 12'h074;
  localparam bit [11:0] RDMA_D_PERF_ENABLE  = 12'h080;
  localparam bit [11:0] RDMA_SCAN_HI        = 12'h090; // 末寄存器 D_PERF_ERDMA_READ_STALL

  localparam bit [31:0] RDMA_CUBE_MASK  = 32'h0000_1FFF;
  localparam bit [31:0] RDMA_ADDR_MASK  = 32'hFFFF_FFE0;
  localparam bit [31:0] RDMA_BRDMA_MASK = 32'h0000_003F; // ram_type[5],mode[4],size[3],use[2:1],disable[0]
  localparam bit [31:0] RDMA_FMODE_MASK = 32'h0000_1FFF; // batch[12:8],out[7:6],proc[5:4],in[3:2],wg[1],fly[0]
  localparam bit [31:0] RDMA_FMODE_RST  = 32'h0000_0014; // in_precision=01,proc_precision=01
  localparam bit [31:0] RDMA_SDMA_MASK  = 32'h0000_0001; // src_ram_type
  localparam bit [31:0] RDMA_PERF_MASK  = 32'h0000_0003;

  `uvm_object_utils(sdp_t0_reg_seq)

  function new(string name = "sdp_t0_reg_seq");
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

  // 块内偏移扫描读（不比对值，只验证不挂；skip 跳过带读副作用的 offset）
  task scan_check(input csb_tgt_e tgt, input bit [11:0] hi, input bit [11:0] skip,
                  input string tag);
    bit [31:0] rd;
    for (int unsigned off = 0; off <= hi; off += 4) begin
      if (12'(off) == skip) continue;
      csb_read(tgt, 12'(off), rd);
      `uvm_info(get_type_name(),
                $sformatf("%s scan off=0x%03h rd=0x%08h", tag, off, rd), UVM_HIGH)
    end
  endtask

  virtual task body();
    // =============== ① 复位值读 ===============
    // SDP_RDMA
    csb_check(CSB_TGT_SDP_RDMA, S_STATUS,           32'h0,          "rst RDMA S_STATUS");
    csb_check(CSB_TGT_SDP_RDMA, S_POINTER,          32'h0,          "rst RDMA S_POINTER");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_OP_ENABLE,   32'h0,          "rst RDMA D_OP_ENABLE");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH,  32'h0,          "rst RDMA D_DATA_CUBE_WIDTH");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_BRDMA_CFG,   32'h0,          "rst RDMA D_BRDMA_CFG");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_FEATURE_MODE, RDMA_FMODE_RST, "rst RDMA D_FEATURE_MODE_CFG");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_SRC_DMA_CFG, 32'h0,          "rst RDMA D_SRC_DMA_CFG");
    // SDP 主块
    csb_check(CSB_TGT_SDP, S_STATUS,          32'h0, "rst SDP S_STATUS");
    csb_check(CSB_TGT_SDP, S_POINTER,         32'h0, "rst SDP S_POINTER");
    csb_check(CSB_TGT_SDP, SDP_D_OP_ENABLE,   32'h0, "rst SDP D_OP_ENABLE");
    csb_check(CSB_TGT_SDP, SDP_D_CUBE_WIDTH,  32'h0, "rst SDP D_DATA_CUBE_WIDTH");
    csb_check(CSB_TGT_SDP, SDP_D_DATA_FORMAT, 32'h0, "rst SDP D_DATA_FORMAT");
    csb_check(CSB_TGT_SDP, SDP_D_FEATURE_MODE, 32'h0, "rst SDP D_FEATURE_MODE_CFG");

    // =============== ② 代表 D 寄存器 mask 化写读 ===============
    // SDP_RDMA
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH,   RDMA_CUBE_MASK,  32'hFFFF_FFFF, "RDMA D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH,   RDMA_CUBE_MASK,  32'hA5A5_A5A5, "RDMA D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH,   RDMA_CUBE_MASK,  32'h0000_0000, "RDMA D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_SRC_ADDR_LOW, RDMA_ADDR_MASK,  32'hFFFF_FFFF, "RDMA D_SRC_BASE_ADDR_LOW");
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_SRC_ADDR_LOW, RDMA_ADDR_MASK,  32'h0000_0000, "RDMA D_SRC_BASE_ADDR_LOW");
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_BRDMA_CFG,    RDMA_BRDMA_MASK, 32'hFFFF_FFFF, "RDMA D_BRDMA_CFG");
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_BRDMA_CFG, 32'h0);
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_FEATURE_MODE, RDMA_FMODE_MASK, 32'hFFFF_FFFF, "RDMA D_FEATURE_MODE_CFG");
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_FEATURE_MODE, RDMA_FMODE_RST); // 恢复
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_SRC_DMA_CFG,  RDMA_SDMA_MASK,  32'hFFFF_FFFF, "RDMA D_SRC_DMA_CFG");
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_SRC_DMA_CFG, 32'h0);
    rw_check(CSB_TGT_SDP_RDMA, RDMA_D_PERF_ENABLE,  RDMA_PERF_MASK,  32'hFFFF_FFFF, "RDMA D_PERF_ENABLE");
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_PERF_ENABLE, 32'h0);
    // SDP 主块
    rw_check(CSB_TGT_SDP, SDP_D_CUBE_WIDTH,   SDP_CUBE_MASK,  32'hFFFF_FFFF, "SDP D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP, SDP_D_CUBE_WIDTH,   SDP_CUBE_MASK,  32'h5A5A_5A5A, "SDP D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP, SDP_D_CUBE_WIDTH,   SDP_CUBE_MASK,  32'h0000_0000, "SDP D_DATA_CUBE_WIDTH");
    rw_check(CSB_TGT_SDP, SDP_D_DST_ADDR_LOW, SDP_ADDR_MASK,  32'hFFFF_FFFF, "SDP D_DST_BASE_ADDR_LOW");
    rw_check(CSB_TGT_SDP, SDP_D_DST_ADDR_LOW, SDP_ADDR_MASK,  32'h0000_0000, "SDP D_DST_BASE_ADDR_LOW");
    rw_check(CSB_TGT_SDP, SDP_D_DP_BS_CFG,    SDP_BSCFG_MASK, 32'hFFFF_FFFF, "SDP D_DP_BS_CFG");
    csb_write(CSB_TGT_SDP, SDP_D_DP_BS_CFG, 32'h0);
    rw_check(CSB_TGT_SDP, SDP_D_FEATURE_MODE, SDP_FMODE_MASK, 32'hFFFF_FFFF, "SDP D_FEATURE_MODE_CFG");
    csb_write(CSB_TGT_SDP, SDP_D_FEATURE_MODE, 32'h0);
    rw_check(CSB_TGT_SDP, SDP_D_DATA_FORMAT,  SDP_DFMT_MASK,  32'hFFFF_FFFF, "SDP D_DATA_FORMAT");
    csb_write(CSB_TGT_SDP, SDP_D_DATA_FORMAT, 32'h0);
    rw_check(CSB_TGT_SDP, SDP_D_CVT_OFFSET,   SDP_CVTO_MASK,  32'hDEAD_BEEF, "SDP D_CVT_OFFSET");
    csb_write(CSB_TGT_SDP, SDP_D_CVT_OFFSET, 32'h0);
    rw_check(CSB_TGT_SDP, SDP_D_PERF_ENABLE,  SDP_PERF_MASK,  32'hFFFF_FFFF, "SDP D_PERF_ENABLE");
    csb_write(CSB_TGT_SDP, SDP_D_PERF_ENABLE, 32'h0);

    // =============== ③ S_POINTER 乒乓影子（每块一个代表 D 寄存器） =========
    shadow_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, RDMA_CUBE_MASK,
                 32'h0000_0123, 32'h0000_1456, 32'h0, "RDMA");
    shadow_check(CSB_TGT_SDP,      SDP_D_CUBE_WIDTH,  SDP_CUBE_MASK,
                 32'h0000_0321, 32'h0000_1654, 32'h0, "SDP");

    // =============== ④ 块内偏移扫描（SDP 跳过 0x00c，见文件头决策） =========
    scan_check(CSB_TGT_SDP_RDMA, RDMA_SCAN_HI, 12'hfff,       "RDMA");
    scan_check(CSB_TGT_SDP,      SDP_SCAN_HI,  SDP_SCAN_SKIP, "SDP");

    // =============== ⑤ 双块互不串 ===============
    // 两块同名寄存器 D_DATA_CUBE_WIDTH 各写一特征值 -> 依次读回（写窜立即暴露）
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, 32'h0000_0AAA);
    csb_write(CSB_TGT_SDP,      SDP_D_CUBE_WIDTH,  32'h0000_1555);
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, 32'h0000_0AAA, "isolation RDMA");
    csb_check(CSB_TGT_SDP,      SDP_D_CUBE_WIDTH,  32'h0000_1555, "isolation SDP");
    // 反向：改写 RDMA 后复读 SDP 不受扰
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, 32'h0000_0777);
    csb_check(CSB_TGT_SDP,      SDP_D_CUBE_WIDTH,  32'h0000_1555, "isolation SDP after RDMA wr");
    csb_check(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, 32'h0000_0777, "isolation RDMA after RDMA wr");
    // 恢复复位态
    csb_write(CSB_TGT_SDP_RDMA, RDMA_D_CUBE_WIDTH, 32'h0);
    csb_write(CSB_TGT_SDP,      SDP_D_CUBE_WIDTH,  32'h0);
  endtask

endclass : sdp_t0_reg_seq

`endif // SDP_T0_REG_SEQ_SVH
