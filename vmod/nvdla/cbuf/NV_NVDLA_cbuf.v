// ================================================================
// NVDLA Open Source Project
// 
// Copyright(c) 2016 - 2017 NVIDIA Corporation.  Licensed under the
// NVDLA Open Hardware License; Check "LICENSE" which comes with 
// this distribution for more information.
// ================================================================

// File Name: NV_NVDLA_cbuf.v

// ----------------------------------------------------------------
// 【机制总览】cbuf：512KB 卷积缓冲，CDMA 写入 / CSC 读出的中转 RAM 阵列
//
// 一、物理组织：16 bank × 2 column × nv_ram_rws_256x512
//   每 RAM 256 深 × 512bit（16KB）；一个 bank = 2 column = 32KB。
//   entry = 1024bit(128B) = 同 bank 同地址的 c0(低 512b)+c1(高 512b)。
//   地址 [11:8]=bank、[7:0]=bank 内 entry 序号，全空间 4096 entry。
//   bank 划分按层配置：bank0 起是数据区，其后到 bank15 是权重区；
//   压缩模式的 WMB 固定占 bank15（所以有 dat 禁写 bank15、wt 禁写
//   bank0 的断言——数据区至少 1 个 bank，权重区至少 1 个 bank）。
//
// 二、写口 ×2（无 ready 反压，上游 CDMA 自己保证不超带宽）
//   p0=dat（1024b + hsel[1:0]）：hsel 是【半字使能】——bit0 写低 512b
//   进 c0、bit1 写高 512b 进 c1，可只写一半；hsel==0 属非法（断言）。
//   p1=wt（512b + 1bit hsel）：每拍只有 512b，hsel 选列（0→c0/1→c1），
//   两拍拼满一个 entry；权重数据与 WMB 都走这个口（按 bank 区分）。
//   写流水：入口打 1 拍（sel/addr/data d1）→ 再打 1 拍（d2）→ RAM 写，
//   即 banner 所记 "write latency 4 cycle（含 RAM 自身 1 拍）"。
//
// 三、读口 ×3（固定 6 拍延迟，无反压、无乱序，interval 断言钉死 6 拍）
//   p0=dat、p1=wt（12bit 地址，整 bank 解码）；p2=wmb（8bit 地址，
//   固定读 bank15，不做 bank 解码）。每次读同时使能该 bank 的 c0+c1
//   两个 RAM，拼出 1024b。流水：入口解码 → d1..d3（含 retiming 级，
//   物理上跨分区布线）→ RAM 读 1 拍 → d4 按 sel_d3 选 bank 数据 →
//   d5/d6 retiming/输出寄存。rd_en 打 6 拍成 rd_valid；data_d6 仅在
//   对应 valid 拍刷新，空闲时保持旧值（省翻转，下游只认 valid 拍）。
//
// 四、冲突规则：cbuf 内部【零仲裁】。每 bank 每 column 就是一读一写
//   口 RAM，同拍多客户端碰同一 bank 的约束全靠上游分工遵守，文末一排
//   断言兜底：dat/wt 写不同 bank、dat/wt 读不同 bank、wt 读与 wmb 读
//   不撞 bank15、读写不撞同 entry、dat 写与 wt 读（及对偶）不撞 bank。
//   本文件主体是 16 bank × 2 column 的机械重复展开，只需读一个 bank
//   的模式即可理解全部；下方各段落头注释标注了每段的语义。
// ----------------------------------------------------------------
`include "simulate_x_tick.vh"
module NV_NVDLA_cbuf (
   nvdla_core_clk       //|< i
  ,nvdla_core_rstn      //|< i
  ,cdma2buf_dat_wr_addr //|< i
  ,cdma2buf_dat_wr_data //|< i
  ,cdma2buf_dat_wr_en   //|< i
  ,cdma2buf_dat_wr_hsel //|< i
  ,cdma2buf_wt_wr_addr  //|< i
  ,cdma2buf_wt_wr_data  //|< i
  ,cdma2buf_wt_wr_en    //|< i
  ,cdma2buf_wt_wr_hsel  //|< i
  ,pwrbus_ram_pd        //|< i
  ,sc2buf_dat_rd_addr   //|< i
  ,sc2buf_dat_rd_en     //|< i
  ,sc2buf_wmb_rd_addr   //|< i
  ,sc2buf_wmb_rd_en     //|< i
  ,sc2buf_wt_rd_addr    //|< i
  ,sc2buf_wt_rd_en      //|< i
  ,sc2buf_dat_rd_data   //|> o
  ,sc2buf_dat_rd_valid  //|> o
  ,sc2buf_wmb_rd_data   //|> o
  ,sc2buf_wmb_rd_valid  //|> o
  ,sc2buf_wt_rd_data    //|> o
  ,sc2buf_wt_rd_valid   //|> o
  );

//
// NV_NVDLA_cbuf_ports.v
//
input  nvdla_core_clk;   /* cdma2buf_dat_wr, cdma2buf_wt_wr, sc2buf_dat_rd_nvdla_ram_addr_ADDR_WIDTH_12_BE_1, sc2buf_dat_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1, sc2buf_wt_rd_nvdla_ram_addr_ADDR_WIDTH_12_BE_1, sc2buf_wt_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1, sc2buf_wmb_rd_nvdla_ram_addr_ADDR_WIDTH_8_BE_1, sc2buf_wmb_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1 */
input  nvdla_core_rstn;  /* cdma2buf_dat_wr, cdma2buf_wt_wr, sc2buf_dat_rd_nvdla_ram_addr_ADDR_WIDTH_12_BE_1, sc2buf_dat_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1, sc2buf_wt_rd_nvdla_ram_addr_ADDR_WIDTH_12_BE_1, sc2buf_wt_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1, sc2buf_wmb_rd_nvdla_ram_addr_ADDR_WIDTH_8_BE_1, sc2buf_wmb_rd_nvdla_ram_data_valid_DATA_WIDTH_1024_ECC_SIZE_1 */

input [31:0] pwrbus_ram_pd;

input          cdma2buf_dat_wr_en;    /* data valid */
input   [11:0] cdma2buf_dat_wr_addr;
input    [1:0] cdma2buf_dat_wr_hsel;
input [1023:0] cdma2buf_dat_wr_data;

input         cdma2buf_wt_wr_en;    /* data valid */
input  [11:0] cdma2buf_wt_wr_addr;
input         cdma2buf_wt_wr_hsel;
input [511:0] cdma2buf_wt_wr_data;

input        sc2buf_dat_rd_en;    /* data valid */
input [11:0] sc2buf_dat_rd_addr;

output          sc2buf_dat_rd_valid;  /* data valid */
output [1023:0] sc2buf_dat_rd_data;

input        sc2buf_wt_rd_en;    /* data valid */
input [11:0] sc2buf_wt_rd_addr;

output          sc2buf_wt_rd_valid;  /* data valid */
output [1023:0] sc2buf_wt_rd_data;

input       sc2buf_wmb_rd_en;    /* data valid */
input [7:0] sc2buf_wmb_rd_addr;

output          sc2buf_wmb_rd_valid;  /* data valid */
output [1023:0] sc2buf_wmb_rd_data;

wire   [11:0] cbuf_p0_rd_addr;
wire    [3:0] cbuf_p0_rd_bank;
wire  [511:0] cbuf_p0_rd_c0_data_d4;
wire  [511:0] cbuf_p0_rd_c0_data_d6_w;
wire          cbuf_p0_rd_c0_valid_d6_w;
wire  [511:0] cbuf_p0_rd_c1_data_d4;
wire  [511:0] cbuf_p0_rd_c1_data_d6_w;
wire          cbuf_p0_rd_c1_valid_d6_w;
wire          cbuf_p0_rd_en;
wire          cbuf_p0_rd_en_d3;
wire          cbuf_p0_rd_en_d4;
wire          cbuf_p0_rd_sel_ram_b0c0_d3;
wire          cbuf_p0_rd_sel_ram_b0c1_d3;
wire          cbuf_p0_rd_sel_ram_b10c0_d3;
wire          cbuf_p0_rd_sel_ram_b10c1_d3;
wire          cbuf_p0_rd_sel_ram_b11c0_d3;
wire          cbuf_p0_rd_sel_ram_b11c1_d3;
wire          cbuf_p0_rd_sel_ram_b12c0_d3;
wire          cbuf_p0_rd_sel_ram_b12c1_d3;
wire          cbuf_p0_rd_sel_ram_b13c0_d3;
wire          cbuf_p0_rd_sel_ram_b13c1_d3;
wire          cbuf_p0_rd_sel_ram_b14c0_d3;
wire          cbuf_p0_rd_sel_ram_b14c1_d3;
wire          cbuf_p0_rd_sel_ram_b1c0_d3;
wire          cbuf_p0_rd_sel_ram_b1c1_d3;
wire          cbuf_p0_rd_sel_ram_b2c0_d3;
wire          cbuf_p0_rd_sel_ram_b2c1_d3;
wire          cbuf_p0_rd_sel_ram_b3c0_d3;
wire          cbuf_p0_rd_sel_ram_b3c1_d3;
wire          cbuf_p0_rd_sel_ram_b4c0_d3;
wire          cbuf_p0_rd_sel_ram_b4c1_d3;
wire          cbuf_p0_rd_sel_ram_b5c0_d3;
wire          cbuf_p0_rd_sel_ram_b5c1_d3;
wire          cbuf_p0_rd_sel_ram_b6c0_d3;
wire          cbuf_p0_rd_sel_ram_b6c1_d3;
wire          cbuf_p0_rd_sel_ram_b7c0_d3;
wire          cbuf_p0_rd_sel_ram_b7c1_d3;
wire          cbuf_p0_rd_sel_ram_b8c0_d3;
wire          cbuf_p0_rd_sel_ram_b8c1_d3;
wire          cbuf_p0_rd_sel_ram_b9c0_d3;
wire          cbuf_p0_rd_sel_ram_b9c1_d3;
wire   [11:0] cbuf_p0_wr_addr;
wire    [3:0] cbuf_p0_wr_bank;
wire          cbuf_p0_wr_en;
wire  [511:0] cbuf_p0_wr_hi_data;
wire  [511:0] cbuf_p0_wr_hi_data_d1_w;
wire          cbuf_p0_wr_hi_en;
wire          cbuf_p0_wr_hi_en_d1_w;
wire  [511:0] cbuf_p0_wr_lo_data;
wire  [511:0] cbuf_p0_wr_lo_data_d1_w;
wire          cbuf_p0_wr_lo_en;
wire          cbuf_p0_wr_lo_en_d1_w;
wire          cbuf_p0_wr_sel_ram_b0c0_d1;
wire          cbuf_p0_wr_sel_ram_b0c1_d1;
wire          cbuf_p0_wr_sel_ram_b10c0_d1;
wire          cbuf_p0_wr_sel_ram_b10c1_d1;
wire          cbuf_p0_wr_sel_ram_b11c0_d1;
wire          cbuf_p0_wr_sel_ram_b11c1_d1;
wire          cbuf_p0_wr_sel_ram_b12c0_d1;
wire          cbuf_p0_wr_sel_ram_b12c1_d1;
wire          cbuf_p0_wr_sel_ram_b13c0_d1;
wire          cbuf_p0_wr_sel_ram_b13c1_d1;
wire          cbuf_p0_wr_sel_ram_b14c0_d1;
wire          cbuf_p0_wr_sel_ram_b14c1_d1;
wire          cbuf_p0_wr_sel_ram_b1c0_d1;
wire          cbuf_p0_wr_sel_ram_b1c1_d1;
wire          cbuf_p0_wr_sel_ram_b2c0_d1;
wire          cbuf_p0_wr_sel_ram_b2c1_d1;
wire          cbuf_p0_wr_sel_ram_b3c0_d1;
wire          cbuf_p0_wr_sel_ram_b3c1_d1;
wire          cbuf_p0_wr_sel_ram_b4c0_d1;
wire          cbuf_p0_wr_sel_ram_b4c1_d1;
wire          cbuf_p0_wr_sel_ram_b5c0_d1;
wire          cbuf_p0_wr_sel_ram_b5c1_d1;
wire          cbuf_p0_wr_sel_ram_b6c0_d1;
wire          cbuf_p0_wr_sel_ram_b6c1_d1;
wire          cbuf_p0_wr_sel_ram_b7c0_d1;
wire          cbuf_p0_wr_sel_ram_b7c1_d1;
wire          cbuf_p0_wr_sel_ram_b8c0_d1;
wire          cbuf_p0_wr_sel_ram_b8c1_d1;
wire          cbuf_p0_wr_sel_ram_b9c0_d1;
wire          cbuf_p0_wr_sel_ram_b9c1_d1;
wire   [11:0] cbuf_p1_rd_addr;
wire    [3:0] cbuf_p1_rd_bank;
wire  [511:0] cbuf_p1_rd_c0_data_d4;
wire  [511:0] cbuf_p1_rd_c0_data_d6_w;
wire          cbuf_p1_rd_c0_valid_d6_w;
wire  [511:0] cbuf_p1_rd_c1_data_d4;
wire  [511:0] cbuf_p1_rd_c1_data_d6_w;
wire          cbuf_p1_rd_c1_valid_d6_w;
wire          cbuf_p1_rd_en;
wire          cbuf_p1_rd_en_d3;
wire          cbuf_p1_rd_en_d4;
wire          cbuf_p1_rd_sel_ram_b10c0_d3;
wire          cbuf_p1_rd_sel_ram_b10c1_d3;
wire          cbuf_p1_rd_sel_ram_b11c0_d3;
wire          cbuf_p1_rd_sel_ram_b11c1_d3;
wire          cbuf_p1_rd_sel_ram_b12c0_d3;
wire          cbuf_p1_rd_sel_ram_b12c1_d3;
wire          cbuf_p1_rd_sel_ram_b13c0_d3;
wire          cbuf_p1_rd_sel_ram_b13c1_d3;
wire          cbuf_p1_rd_sel_ram_b14c0_d3;
wire          cbuf_p1_rd_sel_ram_b14c1_d3;
wire          cbuf_p1_rd_sel_ram_b15c0_d3;
wire          cbuf_p1_rd_sel_ram_b15c1_d3;
wire          cbuf_p1_rd_sel_ram_b1c0_d3;
wire          cbuf_p1_rd_sel_ram_b1c1_d3;
wire          cbuf_p1_rd_sel_ram_b2c0_d3;
wire          cbuf_p1_rd_sel_ram_b2c1_d3;
wire          cbuf_p1_rd_sel_ram_b3c0_d3;
wire          cbuf_p1_rd_sel_ram_b3c1_d3;
wire          cbuf_p1_rd_sel_ram_b4c0_d3;
wire          cbuf_p1_rd_sel_ram_b4c1_d3;
wire          cbuf_p1_rd_sel_ram_b5c0_d3;
wire          cbuf_p1_rd_sel_ram_b5c1_d3;
wire          cbuf_p1_rd_sel_ram_b6c0_d3;
wire          cbuf_p1_rd_sel_ram_b6c1_d3;
wire          cbuf_p1_rd_sel_ram_b7c0_d3;
wire          cbuf_p1_rd_sel_ram_b7c1_d3;
wire          cbuf_p1_rd_sel_ram_b8c0_d3;
wire          cbuf_p1_rd_sel_ram_b8c1_d3;
wire          cbuf_p1_rd_sel_ram_b9c0_d3;
wire          cbuf_p1_rd_sel_ram_b9c1_d3;
wire   [11:0] cbuf_p1_wr_addr;
wire    [3:0] cbuf_p1_wr_bank;
wire  [511:0] cbuf_p1_wr_data;
wire          cbuf_p1_wr_en;
wire  [511:0] cbuf_p1_wr_hi_data_d1_w;
wire          cbuf_p1_wr_hi_en;
wire          cbuf_p1_wr_hi_en_d1_w;
wire  [511:0] cbuf_p1_wr_lo_data_d1_w;
wire          cbuf_p1_wr_lo_en;
wire          cbuf_p1_wr_lo_en_d1_w;
wire          cbuf_p1_wr_sel_ram_b10c0_d1;
wire          cbuf_p1_wr_sel_ram_b10c1_d1;
wire          cbuf_p1_wr_sel_ram_b11c0_d1;
wire          cbuf_p1_wr_sel_ram_b11c1_d1;
wire          cbuf_p1_wr_sel_ram_b12c0_d1;
wire          cbuf_p1_wr_sel_ram_b12c1_d1;
wire          cbuf_p1_wr_sel_ram_b13c0_d1;
wire          cbuf_p1_wr_sel_ram_b13c1_d1;
wire          cbuf_p1_wr_sel_ram_b14c0_d1;
wire          cbuf_p1_wr_sel_ram_b14c1_d1;
wire          cbuf_p1_wr_sel_ram_b15c0_d1;
wire          cbuf_p1_wr_sel_ram_b15c1_d1;
wire          cbuf_p1_wr_sel_ram_b1c0_d1;
wire          cbuf_p1_wr_sel_ram_b1c1_d1;
wire          cbuf_p1_wr_sel_ram_b2c0_d1;
wire          cbuf_p1_wr_sel_ram_b2c1_d1;
wire          cbuf_p1_wr_sel_ram_b3c0_d1;
wire          cbuf_p1_wr_sel_ram_b3c1_d1;
wire          cbuf_p1_wr_sel_ram_b4c0_d1;
wire          cbuf_p1_wr_sel_ram_b4c1_d1;
wire          cbuf_p1_wr_sel_ram_b5c0_d1;
wire          cbuf_p1_wr_sel_ram_b5c1_d1;
wire          cbuf_p1_wr_sel_ram_b6c0_d1;
wire          cbuf_p1_wr_sel_ram_b6c1_d1;
wire          cbuf_p1_wr_sel_ram_b7c0_d1;
wire          cbuf_p1_wr_sel_ram_b7c1_d1;
wire          cbuf_p1_wr_sel_ram_b8c0_d1;
wire          cbuf_p1_wr_sel_ram_b8c1_d1;
wire          cbuf_p1_wr_sel_ram_b9c0_d1;
wire          cbuf_p1_wr_sel_ram_b9c1_d1;
wire    [7:0] cbuf_p2_rd_addr;
wire  [511:0] cbuf_p2_rd_c0_data_d4;
wire  [511:0] cbuf_p2_rd_c0_data_d6_w;
wire          cbuf_p2_rd_c0_valid_d6_w;
wire  [511:0] cbuf_p2_rd_c1_data_d4;
wire  [511:0] cbuf_p2_rd_c1_data_d6_w;
wire          cbuf_p2_rd_c1_valid_d6_w;
wire          cbuf_p2_rd_en;
wire          cbuf_p2_rd_en_d3;
wire          cbuf_p2_rd_en_d4;
wire          cbuf_p2_rd_sel_ram_b15c0_d3;
wire          cbuf_p2_rd_sel_ram_b15c1_d3;
wire  [511:0] cbuf_rdat_b0c0;
wire  [511:0] cbuf_rdat_b0c1;
wire  [511:0] cbuf_rdat_b10c0;
wire  [511:0] cbuf_rdat_b10c1;
wire  [511:0] cbuf_rdat_b11c0;
wire  [511:0] cbuf_rdat_b11c1;
wire  [511:0] cbuf_rdat_b12c0;
wire  [511:0] cbuf_rdat_b12c1;
wire  [511:0] cbuf_rdat_b13c0;
wire  [511:0] cbuf_rdat_b13c1;
wire  [511:0] cbuf_rdat_b14c0;
wire  [511:0] cbuf_rdat_b14c1;
wire  [511:0] cbuf_rdat_b15c0;
wire  [511:0] cbuf_rdat_b15c1;
wire  [511:0] cbuf_rdat_b1c0;
wire  [511:0] cbuf_rdat_b1c1;
wire  [511:0] cbuf_rdat_b2c0;
wire  [511:0] cbuf_rdat_b2c1;
wire  [511:0] cbuf_rdat_b3c0;
wire  [511:0] cbuf_rdat_b3c1;
wire  [511:0] cbuf_rdat_b4c0;
wire  [511:0] cbuf_rdat_b4c1;
wire  [511:0] cbuf_rdat_b5c0;
wire  [511:0] cbuf_rdat_b5c1;
wire  [511:0] cbuf_rdat_b6c0;
wire  [511:0] cbuf_rdat_b6c1;
wire  [511:0] cbuf_rdat_b7c0;
wire  [511:0] cbuf_rdat_b7c1;
wire  [511:0] cbuf_rdat_b8c0;
wire  [511:0] cbuf_rdat_b8c1;
wire  [511:0] cbuf_rdat_b9c0;
wire  [511:0] cbuf_rdat_b9c1;
reg   [511:0] cbuf_p0_rd_c0_data_d5;
reg           cbuf_p0_rd_c0_valid_d5;
reg   [511:0] cbuf_p0_rd_c1_data_d5;
reg           cbuf_p0_rd_c1_valid_d5;
reg  [1023:0] cbuf_p0_rd_data_d4;
reg  [1023:0] cbuf_p0_rd_data_d4_w;
reg  [1023:0] cbuf_p0_rd_data_d6;
reg           cbuf_p0_rd_en_d5;
reg           cbuf_p0_rd_sel_ram_b0c0_w;
reg           cbuf_p0_rd_sel_ram_b0c1_w;
reg           cbuf_p0_rd_sel_ram_b10c0_w;
reg           cbuf_p0_rd_sel_ram_b10c1_w;
reg           cbuf_p0_rd_sel_ram_b11c0_w;
reg           cbuf_p0_rd_sel_ram_b11c1_w;
reg           cbuf_p0_rd_sel_ram_b12c0_w;
reg           cbuf_p0_rd_sel_ram_b12c1_w;
reg           cbuf_p0_rd_sel_ram_b13c0_w;
reg           cbuf_p0_rd_sel_ram_b13c1_w;
reg           cbuf_p0_rd_sel_ram_b14c0_w;
reg           cbuf_p0_rd_sel_ram_b14c1_w;
reg           cbuf_p0_rd_sel_ram_b1c0_w;
reg           cbuf_p0_rd_sel_ram_b1c1_w;
reg           cbuf_p0_rd_sel_ram_b2c0_w;
reg           cbuf_p0_rd_sel_ram_b2c1_w;
reg           cbuf_p0_rd_sel_ram_b3c0_w;
reg           cbuf_p0_rd_sel_ram_b3c1_w;
reg           cbuf_p0_rd_sel_ram_b4c0_w;
reg           cbuf_p0_rd_sel_ram_b4c1_w;
reg           cbuf_p0_rd_sel_ram_b5c0_w;
reg           cbuf_p0_rd_sel_ram_b5c1_w;
reg           cbuf_p0_rd_sel_ram_b6c0_w;
reg           cbuf_p0_rd_sel_ram_b6c1_w;
reg           cbuf_p0_rd_sel_ram_b7c0_w;
reg           cbuf_p0_rd_sel_ram_b7c1_w;
reg           cbuf_p0_rd_sel_ram_b8c0_w;
reg           cbuf_p0_rd_sel_ram_b8c1_w;
reg           cbuf_p0_rd_sel_ram_b9c0_w;
reg           cbuf_p0_rd_sel_ram_b9c1_w;
reg           cbuf_p0_rd_valid_d6;
reg     [7:0] cbuf_p0_wr_addr_d1;
reg   [511:0] cbuf_p0_wr_hi_data_d1;
reg   [511:0] cbuf_p0_wr_lo_data_d1;
reg           cbuf_p0_wr_sel_ram_b0c0_w;
reg           cbuf_p0_wr_sel_ram_b0c1_w;
reg           cbuf_p0_wr_sel_ram_b10c0_w;
reg           cbuf_p0_wr_sel_ram_b10c1_w;
reg           cbuf_p0_wr_sel_ram_b11c0_w;
reg           cbuf_p0_wr_sel_ram_b11c1_w;
reg           cbuf_p0_wr_sel_ram_b12c0_w;
reg           cbuf_p0_wr_sel_ram_b12c1_w;
reg           cbuf_p0_wr_sel_ram_b13c0_w;
reg           cbuf_p0_wr_sel_ram_b13c1_w;
reg           cbuf_p0_wr_sel_ram_b14c0_w;
reg           cbuf_p0_wr_sel_ram_b14c1_w;
reg           cbuf_p0_wr_sel_ram_b1c0_w;
reg           cbuf_p0_wr_sel_ram_b1c1_w;
reg           cbuf_p0_wr_sel_ram_b2c0_w;
reg           cbuf_p0_wr_sel_ram_b2c1_w;
reg           cbuf_p0_wr_sel_ram_b3c0_w;
reg           cbuf_p0_wr_sel_ram_b3c1_w;
reg           cbuf_p0_wr_sel_ram_b4c0_w;
reg           cbuf_p0_wr_sel_ram_b4c1_w;
reg           cbuf_p0_wr_sel_ram_b5c0_w;
reg           cbuf_p0_wr_sel_ram_b5c1_w;
reg           cbuf_p0_wr_sel_ram_b6c0_w;
reg           cbuf_p0_wr_sel_ram_b6c1_w;
reg           cbuf_p0_wr_sel_ram_b7c0_w;
reg           cbuf_p0_wr_sel_ram_b7c1_w;
reg           cbuf_p0_wr_sel_ram_b8c0_w;
reg           cbuf_p0_wr_sel_ram_b8c1_w;
reg           cbuf_p0_wr_sel_ram_b9c0_w;
reg           cbuf_p0_wr_sel_ram_b9c1_w;
reg   [511:0] cbuf_p1_rd_c0_data_d5;
reg           cbuf_p1_rd_c0_valid_d5;
reg   [511:0] cbuf_p1_rd_c1_data_d5;
reg           cbuf_p1_rd_c1_valid_d5;
reg  [1023:0] cbuf_p1_rd_data_d4;
reg  [1023:0] cbuf_p1_rd_data_d4_w;
reg  [1023:0] cbuf_p1_rd_data_d6;
reg           cbuf_p1_rd_en_d5;
reg           cbuf_p1_rd_sel_ram_b10c0_w;
reg           cbuf_p1_rd_sel_ram_b10c1_w;
reg           cbuf_p1_rd_sel_ram_b11c0_w;
reg           cbuf_p1_rd_sel_ram_b11c1_w;
reg           cbuf_p1_rd_sel_ram_b12c0_w;
reg           cbuf_p1_rd_sel_ram_b12c1_w;
reg           cbuf_p1_rd_sel_ram_b13c0_w;
reg           cbuf_p1_rd_sel_ram_b13c1_w;
reg           cbuf_p1_rd_sel_ram_b14c0_w;
reg           cbuf_p1_rd_sel_ram_b14c1_w;
reg           cbuf_p1_rd_sel_ram_b15c0_w;
reg           cbuf_p1_rd_sel_ram_b15c1_w;
reg           cbuf_p1_rd_sel_ram_b1c0_w;
reg           cbuf_p1_rd_sel_ram_b1c1_w;
reg           cbuf_p1_rd_sel_ram_b2c0_w;
reg           cbuf_p1_rd_sel_ram_b2c1_w;
reg           cbuf_p1_rd_sel_ram_b3c0_w;
reg           cbuf_p1_rd_sel_ram_b3c1_w;
reg           cbuf_p1_rd_sel_ram_b4c0_w;
reg           cbuf_p1_rd_sel_ram_b4c1_w;
reg           cbuf_p1_rd_sel_ram_b5c0_w;
reg           cbuf_p1_rd_sel_ram_b5c1_w;
reg           cbuf_p1_rd_sel_ram_b6c0_w;
reg           cbuf_p1_rd_sel_ram_b6c1_w;
reg           cbuf_p1_rd_sel_ram_b7c0_w;
reg           cbuf_p1_rd_sel_ram_b7c1_w;
reg           cbuf_p1_rd_sel_ram_b8c0_w;
reg           cbuf_p1_rd_sel_ram_b8c1_w;
reg           cbuf_p1_rd_sel_ram_b9c0_w;
reg           cbuf_p1_rd_sel_ram_b9c1_w;
reg           cbuf_p1_rd_valid_d6;
reg     [7:0] cbuf_p1_wr_addr_d1;
reg   [511:0] cbuf_p1_wr_hi_data_d1;
reg   [511:0] cbuf_p1_wr_lo_data_d1;
reg           cbuf_p1_wr_sel_ram_b10c0_w;
reg           cbuf_p1_wr_sel_ram_b10c1_w;
reg           cbuf_p1_wr_sel_ram_b11c0_w;
reg           cbuf_p1_wr_sel_ram_b11c1_w;
reg           cbuf_p1_wr_sel_ram_b12c0_w;
reg           cbuf_p1_wr_sel_ram_b12c1_w;
reg           cbuf_p1_wr_sel_ram_b13c0_w;
reg           cbuf_p1_wr_sel_ram_b13c1_w;
reg           cbuf_p1_wr_sel_ram_b14c0_w;
reg           cbuf_p1_wr_sel_ram_b14c1_w;
reg           cbuf_p1_wr_sel_ram_b15c0_w;
reg           cbuf_p1_wr_sel_ram_b15c1_w;
reg           cbuf_p1_wr_sel_ram_b1c0_w;
reg           cbuf_p1_wr_sel_ram_b1c1_w;
reg           cbuf_p1_wr_sel_ram_b2c0_w;
reg           cbuf_p1_wr_sel_ram_b2c1_w;
reg           cbuf_p1_wr_sel_ram_b3c0_w;
reg           cbuf_p1_wr_sel_ram_b3c1_w;
reg           cbuf_p1_wr_sel_ram_b4c0_w;
reg           cbuf_p1_wr_sel_ram_b4c1_w;
reg           cbuf_p1_wr_sel_ram_b5c0_w;
reg           cbuf_p1_wr_sel_ram_b5c1_w;
reg           cbuf_p1_wr_sel_ram_b6c0_w;
reg           cbuf_p1_wr_sel_ram_b6c1_w;
reg           cbuf_p1_wr_sel_ram_b7c0_w;
reg           cbuf_p1_wr_sel_ram_b7c1_w;
reg           cbuf_p1_wr_sel_ram_b8c0_w;
reg           cbuf_p1_wr_sel_ram_b8c1_w;
reg           cbuf_p1_wr_sel_ram_b9c0_w;
reg           cbuf_p1_wr_sel_ram_b9c1_w;
reg   [511:0] cbuf_p2_rd_c0_data_d5;
reg           cbuf_p2_rd_c0_valid_d5;
reg   [511:0] cbuf_p2_rd_c1_data_d5;
reg           cbuf_p2_rd_c1_valid_d5;
reg  [1023:0] cbuf_p2_rd_data_d4;
reg  [1023:0] cbuf_p2_rd_data_d4_w;
reg  [1023:0] cbuf_p2_rd_data_d6;
reg           cbuf_p2_rd_en_d5;
reg           cbuf_p2_rd_sel_ram_b15c0_w;
reg           cbuf_p2_rd_sel_ram_b15c1_w;
reg           cbuf_p2_rd_valid_d6;
reg     [7:0] cbuf_ra_b0c0;
reg     [7:0] cbuf_ra_b0c0_w;
reg     [7:0] cbuf_ra_b0c1;
reg     [7:0] cbuf_ra_b0c1_w;
reg     [7:0] cbuf_ra_b10c0;
reg     [7:0] cbuf_ra_b10c0_w;
reg     [7:0] cbuf_ra_b10c1;
reg     [7:0] cbuf_ra_b10c1_w;
reg     [7:0] cbuf_ra_b11c0;
reg     [7:0] cbuf_ra_b11c0_w;
reg     [7:0] cbuf_ra_b11c1;
reg     [7:0] cbuf_ra_b11c1_w;
reg     [7:0] cbuf_ra_b12c0;
reg     [7:0] cbuf_ra_b12c0_w;
reg     [7:0] cbuf_ra_b12c1;
reg     [7:0] cbuf_ra_b12c1_w;
reg     [7:0] cbuf_ra_b13c0;
reg     [7:0] cbuf_ra_b13c0_w;
reg     [7:0] cbuf_ra_b13c1;
reg     [7:0] cbuf_ra_b13c1_w;
reg     [7:0] cbuf_ra_b14c0;
reg     [7:0] cbuf_ra_b14c0_w;
reg     [7:0] cbuf_ra_b14c1;
reg     [7:0] cbuf_ra_b14c1_w;
reg     [7:0] cbuf_ra_b15c0;
reg     [7:0] cbuf_ra_b15c0_w;
reg     [7:0] cbuf_ra_b15c1;
reg     [7:0] cbuf_ra_b15c1_w;
reg     [7:0] cbuf_ra_b1c0;
reg     [7:0] cbuf_ra_b1c0_w;
reg     [7:0] cbuf_ra_b1c1;
reg     [7:0] cbuf_ra_b1c1_w;
reg     [7:0] cbuf_ra_b2c0;
reg     [7:0] cbuf_ra_b2c0_w;
reg     [7:0] cbuf_ra_b2c1;
reg     [7:0] cbuf_ra_b2c1_w;
reg     [7:0] cbuf_ra_b3c0;
reg     [7:0] cbuf_ra_b3c0_w;
reg     [7:0] cbuf_ra_b3c1;
reg     [7:0] cbuf_ra_b3c1_w;
reg     [7:0] cbuf_ra_b4c0;
reg     [7:0] cbuf_ra_b4c0_w;
reg     [7:0] cbuf_ra_b4c1;
reg     [7:0] cbuf_ra_b4c1_w;
reg     [7:0] cbuf_ra_b5c0;
reg     [7:0] cbuf_ra_b5c0_w;
reg     [7:0] cbuf_ra_b5c1;
reg     [7:0] cbuf_ra_b5c1_w;
reg     [7:0] cbuf_ra_b6c0;
reg     [7:0] cbuf_ra_b6c0_w;
reg     [7:0] cbuf_ra_b6c1;
reg     [7:0] cbuf_ra_b6c1_w;
reg     [7:0] cbuf_ra_b7c0;
reg     [7:0] cbuf_ra_b7c0_w;
reg     [7:0] cbuf_ra_b7c1;
reg     [7:0] cbuf_ra_b7c1_w;
reg     [7:0] cbuf_ra_b8c0;
reg     [7:0] cbuf_ra_b8c0_w;
reg     [7:0] cbuf_ra_b8c1;
reg     [7:0] cbuf_ra_b8c1_w;
reg     [7:0] cbuf_ra_b9c0;
reg     [7:0] cbuf_ra_b9c0_w;
reg     [7:0] cbuf_ra_b9c1;
reg     [7:0] cbuf_ra_b9c1_w;
reg     [2:0] cbuf_rd_en_d1;
reg     [2:0] cbuf_rd_en_d2;
reg     [2:0] cbuf_rd_en_d3;
reg     [2:0] cbuf_rd_en_d4;
reg    [61:0] cbuf_rd_sel_ram_d1;
reg    [61:0] cbuf_rd_sel_ram_d2;
reg    [61:0] cbuf_rd_sel_ram_d3;
reg   [511:0] cbuf_rdat_b0c0_d3;
reg   [511:0] cbuf_rdat_b0c1_d3;
reg   [511:0] cbuf_rdat_b10c0_d3;
reg   [511:0] cbuf_rdat_b10c1_d3;
reg   [511:0] cbuf_rdat_b11c0_d3;
reg   [511:0] cbuf_rdat_b11c1_d3;
reg   [511:0] cbuf_rdat_b12c0_d3;
reg   [511:0] cbuf_rdat_b12c1_d3;
reg   [511:0] cbuf_rdat_b13c0_d3;
reg   [511:0] cbuf_rdat_b13c1_d3;
reg   [511:0] cbuf_rdat_b14c0_d3;
reg   [511:0] cbuf_rdat_b14c1_d3;
reg   [511:0] cbuf_rdat_b15c0_d3;
reg   [511:0] cbuf_rdat_b15c1_d3;
reg   [511:0] cbuf_rdat_b1c0_d3;
reg   [511:0] cbuf_rdat_b1c1_d3;
reg   [511:0] cbuf_rdat_b2c0_d3;
reg   [511:0] cbuf_rdat_b2c1_d3;
reg   [511:0] cbuf_rdat_b3c0_d3;
reg   [511:0] cbuf_rdat_b3c1_d3;
reg   [511:0] cbuf_rdat_b4c0_d3;
reg   [511:0] cbuf_rdat_b4c1_d3;
reg   [511:0] cbuf_rdat_b5c0_d3;
reg   [511:0] cbuf_rdat_b5c1_d3;
reg   [511:0] cbuf_rdat_b6c0_d3;
reg   [511:0] cbuf_rdat_b6c1_d3;
reg   [511:0] cbuf_rdat_b7c0_d3;
reg   [511:0] cbuf_rdat_b7c1_d3;
reg   [511:0] cbuf_rdat_b8c0_d3;
reg   [511:0] cbuf_rdat_b8c1_d3;
reg   [511:0] cbuf_rdat_b9c0_d3;
reg   [511:0] cbuf_rdat_b9c1_d3;
reg           cbuf_re_b0c0;
reg           cbuf_re_b0c0_d2;
reg           cbuf_re_b0c0_w;
reg           cbuf_re_b0c1;
reg           cbuf_re_b0c1_d2;
reg           cbuf_re_b0c1_w;
reg           cbuf_re_b10c0;
reg           cbuf_re_b10c0_d2;
reg           cbuf_re_b10c0_w;
reg           cbuf_re_b10c1;
reg           cbuf_re_b10c1_d2;
reg           cbuf_re_b10c1_w;
reg           cbuf_re_b11c0;
reg           cbuf_re_b11c0_d2;
reg           cbuf_re_b11c0_w;
reg           cbuf_re_b11c1;
reg           cbuf_re_b11c1_d2;
reg           cbuf_re_b11c1_w;
reg           cbuf_re_b12c0;
reg           cbuf_re_b12c0_d2;
reg           cbuf_re_b12c0_w;
reg           cbuf_re_b12c1;
reg           cbuf_re_b12c1_d2;
reg           cbuf_re_b12c1_w;
reg           cbuf_re_b13c0;
reg           cbuf_re_b13c0_d2;
reg           cbuf_re_b13c0_w;
reg           cbuf_re_b13c1;
reg           cbuf_re_b13c1_d2;
reg           cbuf_re_b13c1_w;
reg           cbuf_re_b14c0;
reg           cbuf_re_b14c0_d2;
reg           cbuf_re_b14c0_w;
reg           cbuf_re_b14c1;
reg           cbuf_re_b14c1_d2;
reg           cbuf_re_b14c1_w;
reg           cbuf_re_b15c0;
reg           cbuf_re_b15c0_d2;
reg           cbuf_re_b15c0_w;
reg           cbuf_re_b15c1;
reg           cbuf_re_b15c1_d2;
reg           cbuf_re_b15c1_w;
reg           cbuf_re_b1c0;
reg           cbuf_re_b1c0_d2;
reg           cbuf_re_b1c0_w;
reg           cbuf_re_b1c1;
reg           cbuf_re_b1c1_d2;
reg           cbuf_re_b1c1_w;
reg           cbuf_re_b2c0;
reg           cbuf_re_b2c0_d2;
reg           cbuf_re_b2c0_w;
reg           cbuf_re_b2c1;
reg           cbuf_re_b2c1_d2;
reg           cbuf_re_b2c1_w;
reg           cbuf_re_b3c0;
reg           cbuf_re_b3c0_d2;
reg           cbuf_re_b3c0_w;
reg           cbuf_re_b3c1;
reg           cbuf_re_b3c1_d2;
reg           cbuf_re_b3c1_w;
reg           cbuf_re_b4c0;
reg           cbuf_re_b4c0_d2;
reg           cbuf_re_b4c0_w;
reg           cbuf_re_b4c1;
reg           cbuf_re_b4c1_d2;
reg           cbuf_re_b4c1_w;
reg           cbuf_re_b5c0;
reg           cbuf_re_b5c0_d2;
reg           cbuf_re_b5c0_w;
reg           cbuf_re_b5c1;
reg           cbuf_re_b5c1_d2;
reg           cbuf_re_b5c1_w;
reg           cbuf_re_b6c0;
reg           cbuf_re_b6c0_d2;
reg           cbuf_re_b6c0_w;
reg           cbuf_re_b6c1;
reg           cbuf_re_b6c1_d2;
reg           cbuf_re_b6c1_w;
reg           cbuf_re_b7c0;
reg           cbuf_re_b7c0_d2;
reg           cbuf_re_b7c0_w;
reg           cbuf_re_b7c1;
reg           cbuf_re_b7c1_d2;
reg           cbuf_re_b7c1_w;
reg           cbuf_re_b8c0;
reg           cbuf_re_b8c0_d2;
reg           cbuf_re_b8c0_w;
reg           cbuf_re_b8c1;
reg           cbuf_re_b8c1_d2;
reg           cbuf_re_b8c1_w;
reg           cbuf_re_b9c0;
reg           cbuf_re_b9c0_d2;
reg           cbuf_re_b9c0_w;
reg           cbuf_re_b9c1;
reg           cbuf_re_b9c1_d2;
reg           cbuf_re_b9c1_w;
reg     [7:0] cbuf_wa_b0c0;
reg     [7:0] cbuf_wa_b0c0_d2;
reg     [7:0] cbuf_wa_b0c1;
reg     [7:0] cbuf_wa_b0c1_d2;
reg     [7:0] cbuf_wa_b10c0;
reg     [7:0] cbuf_wa_b10c0_d2;
reg     [7:0] cbuf_wa_b10c1;
reg     [7:0] cbuf_wa_b10c1_d2;
reg     [7:0] cbuf_wa_b11c0;
reg     [7:0] cbuf_wa_b11c0_d2;
reg     [7:0] cbuf_wa_b11c1;
reg     [7:0] cbuf_wa_b11c1_d2;
reg     [7:0] cbuf_wa_b12c0;
reg     [7:0] cbuf_wa_b12c0_d2;
reg     [7:0] cbuf_wa_b12c1;
reg     [7:0] cbuf_wa_b12c1_d2;
reg     [7:0] cbuf_wa_b13c0;
reg     [7:0] cbuf_wa_b13c0_d2;
reg     [7:0] cbuf_wa_b13c1;
reg     [7:0] cbuf_wa_b13c1_d2;
reg     [7:0] cbuf_wa_b14c0;
reg     [7:0] cbuf_wa_b14c0_d2;
reg     [7:0] cbuf_wa_b14c1;
reg     [7:0] cbuf_wa_b14c1_d2;
reg     [7:0] cbuf_wa_b15c0;
reg     [7:0] cbuf_wa_b15c0_d2;
reg     [7:0] cbuf_wa_b15c1;
reg     [7:0] cbuf_wa_b15c1_d2;
reg     [7:0] cbuf_wa_b1c0;
reg     [7:0] cbuf_wa_b1c0_d2;
reg     [7:0] cbuf_wa_b1c1;
reg     [7:0] cbuf_wa_b1c1_d2;
reg     [7:0] cbuf_wa_b2c0;
reg     [7:0] cbuf_wa_b2c0_d2;
reg     [7:0] cbuf_wa_b2c1;
reg     [7:0] cbuf_wa_b2c1_d2;
reg     [7:0] cbuf_wa_b3c0;
reg     [7:0] cbuf_wa_b3c0_d2;
reg     [7:0] cbuf_wa_b3c1;
reg     [7:0] cbuf_wa_b3c1_d2;
reg     [7:0] cbuf_wa_b4c0;
reg     [7:0] cbuf_wa_b4c0_d2;
reg     [7:0] cbuf_wa_b4c1;
reg     [7:0] cbuf_wa_b4c1_d2;
reg     [7:0] cbuf_wa_b5c0;
reg     [7:0] cbuf_wa_b5c0_d2;
reg     [7:0] cbuf_wa_b5c1;
reg     [7:0] cbuf_wa_b5c1_d2;
reg     [7:0] cbuf_wa_b6c0;
reg     [7:0] cbuf_wa_b6c0_d2;
reg     [7:0] cbuf_wa_b6c1;
reg     [7:0] cbuf_wa_b6c1_d2;
reg     [7:0] cbuf_wa_b7c0;
reg     [7:0] cbuf_wa_b7c0_d2;
reg     [7:0] cbuf_wa_b7c1;
reg     [7:0] cbuf_wa_b7c1_d2;
reg     [7:0] cbuf_wa_b8c0;
reg     [7:0] cbuf_wa_b8c0_d2;
reg     [7:0] cbuf_wa_b8c1;
reg     [7:0] cbuf_wa_b8c1_d2;
reg     [7:0] cbuf_wa_b9c0;
reg     [7:0] cbuf_wa_b9c0_d2;
reg     [7:0] cbuf_wa_b9c1;
reg     [7:0] cbuf_wa_b9c1_d2;
reg   [511:0] cbuf_wdat_b0c0;
reg   [511:0] cbuf_wdat_b0c0_d2;
reg   [511:0] cbuf_wdat_b0c1;
reg   [511:0] cbuf_wdat_b0c1_d2;
reg   [511:0] cbuf_wdat_b10c0;
reg   [511:0] cbuf_wdat_b10c0_d2;
reg   [511:0] cbuf_wdat_b10c1;
reg   [511:0] cbuf_wdat_b10c1_d2;
reg   [511:0] cbuf_wdat_b11c0;
reg   [511:0] cbuf_wdat_b11c0_d2;
reg   [511:0] cbuf_wdat_b11c1;
reg   [511:0] cbuf_wdat_b11c1_d2;
reg   [511:0] cbuf_wdat_b12c0;
reg   [511:0] cbuf_wdat_b12c0_d2;
reg   [511:0] cbuf_wdat_b12c1;
reg   [511:0] cbuf_wdat_b12c1_d2;
reg   [511:0] cbuf_wdat_b13c0;
reg   [511:0] cbuf_wdat_b13c0_d2;
reg   [511:0] cbuf_wdat_b13c1;
reg   [511:0] cbuf_wdat_b13c1_d2;
reg   [511:0] cbuf_wdat_b14c0;
reg   [511:0] cbuf_wdat_b14c0_d2;
reg   [511:0] cbuf_wdat_b14c1;
reg   [511:0] cbuf_wdat_b14c1_d2;
reg   [511:0] cbuf_wdat_b15c0;
reg   [511:0] cbuf_wdat_b15c0_d2;
reg   [511:0] cbuf_wdat_b15c1;
reg   [511:0] cbuf_wdat_b15c1_d2;
reg   [511:0] cbuf_wdat_b1c0;
reg   [511:0] cbuf_wdat_b1c0_d2;
reg   [511:0] cbuf_wdat_b1c1;
reg   [511:0] cbuf_wdat_b1c1_d2;
reg   [511:0] cbuf_wdat_b2c0;
reg   [511:0] cbuf_wdat_b2c0_d2;
reg   [511:0] cbuf_wdat_b2c1;
reg   [511:0] cbuf_wdat_b2c1_d2;
reg   [511:0] cbuf_wdat_b3c0;
reg   [511:0] cbuf_wdat_b3c0_d2;
reg   [511:0] cbuf_wdat_b3c1;
reg   [511:0] cbuf_wdat_b3c1_d2;
reg   [511:0] cbuf_wdat_b4c0;
reg   [511:0] cbuf_wdat_b4c0_d2;
reg   [511:0] cbuf_wdat_b4c1;
reg   [511:0] cbuf_wdat_b4c1_d2;
reg   [511:0] cbuf_wdat_b5c0;
reg   [511:0] cbuf_wdat_b5c0_d2;
reg   [511:0] cbuf_wdat_b5c1;
reg   [511:0] cbuf_wdat_b5c1_d2;
reg   [511:0] cbuf_wdat_b6c0;
reg   [511:0] cbuf_wdat_b6c0_d2;
reg   [511:0] cbuf_wdat_b6c1;
reg   [511:0] cbuf_wdat_b6c1_d2;
reg   [511:0] cbuf_wdat_b7c0;
reg   [511:0] cbuf_wdat_b7c0_d2;
reg   [511:0] cbuf_wdat_b7c1;
reg   [511:0] cbuf_wdat_b7c1_d2;
reg   [511:0] cbuf_wdat_b8c0;
reg   [511:0] cbuf_wdat_b8c0_d2;
reg   [511:0] cbuf_wdat_b8c1;
reg   [511:0] cbuf_wdat_b8c1_d2;
reg   [511:0] cbuf_wdat_b9c0;
reg   [511:0] cbuf_wdat_b9c0_d2;
reg   [511:0] cbuf_wdat_b9c1;
reg   [511:0] cbuf_wdat_b9c1_d2;
reg           cbuf_we_b0c0;
reg           cbuf_we_b0c0_d2;
reg           cbuf_we_b0c1;
reg           cbuf_we_b0c1_d2;
reg           cbuf_we_b10c0;
reg           cbuf_we_b10c0_d2;
reg           cbuf_we_b10c1;
reg           cbuf_we_b10c1_d2;
reg           cbuf_we_b11c0;
reg           cbuf_we_b11c0_d2;
reg           cbuf_we_b11c1;
reg           cbuf_we_b11c1_d2;
reg           cbuf_we_b12c0;
reg           cbuf_we_b12c0_d2;
reg           cbuf_we_b12c1;
reg           cbuf_we_b12c1_d2;
reg           cbuf_we_b13c0;
reg           cbuf_we_b13c0_d2;
reg           cbuf_we_b13c1;
reg           cbuf_we_b13c1_d2;
reg           cbuf_we_b14c0;
reg           cbuf_we_b14c0_d2;
reg           cbuf_we_b14c1;
reg           cbuf_we_b14c1_d2;
reg           cbuf_we_b15c0;
reg           cbuf_we_b15c0_d2;
reg           cbuf_we_b15c1;
reg           cbuf_we_b15c1_d2;
reg           cbuf_we_b1c0;
reg           cbuf_we_b1c0_d2;
reg           cbuf_we_b1c1;
reg           cbuf_we_b1c1_d2;
reg           cbuf_we_b2c0;
reg           cbuf_we_b2c0_d2;
reg           cbuf_we_b2c1;
reg           cbuf_we_b2c1_d2;
reg           cbuf_we_b3c0;
reg           cbuf_we_b3c0_d2;
reg           cbuf_we_b3c1;
reg           cbuf_we_b3c1_d2;
reg           cbuf_we_b4c0;
reg           cbuf_we_b4c0_d2;
reg           cbuf_we_b4c1;
reg           cbuf_we_b4c1_d2;
reg           cbuf_we_b5c0;
reg           cbuf_we_b5c0_d2;
reg           cbuf_we_b5c1;
reg           cbuf_we_b5c1_d2;
reg           cbuf_we_b6c0;
reg           cbuf_we_b6c0_d2;
reg           cbuf_we_b6c1;
reg           cbuf_we_b6c1_d2;
reg           cbuf_we_b7c0;
reg           cbuf_we_b7c0_d2;
reg           cbuf_we_b7c1;
reg           cbuf_we_b7c1_d2;
reg           cbuf_we_b8c0;
reg           cbuf_we_b8c0_d2;
reg           cbuf_we_b8c1;
reg           cbuf_we_b8c1_d2;
reg           cbuf_we_b9c0;
reg           cbuf_we_b9c0_d2;
reg           cbuf_we_b9c1;
reg           cbuf_we_b9c1_d2;
reg    [59:0] cbuf_wr_sel_ram_d1;






////////////////////////////////////////////////////////////////////////
//                                                                    //
// Input write latency: 1 cycle                                       //
//                                                                    //
////////////////////////////////////////////////////////////////////////








////////////////////////////////////////////////////////////////////////
//                                                                    //
// Input write latency: 4 cycle (1 cycle for raw ram access)          //
//                                                                    //
////////////////////////////////////////////////////////////////////////




////////////////////////////////////////////////////////////////////////
// Input write stage1: connect to retiming registers                  //
////////////////////////////////////////////////////////////////////////

// hsel 半字使能语义：dat 口 1024b 拆成 lo/hi 两个 512b 独立写使能
// （lo→column0、hi→column1），cvt 只凑齐半个 entry 时可以只写一半；
// wt 口每拍本来就只有 512b，单 bit hsel 直接当列选择用
assign cbuf_p0_wr_en       = cdma2buf_dat_wr_en;
assign cbuf_p0_wr_lo_en    = cdma2buf_dat_wr_en & cdma2buf_dat_wr_hsel[0];
assign cbuf_p0_wr_hi_en    = cdma2buf_dat_wr_en & cdma2buf_dat_wr_hsel[1];
assign cbuf_p0_wr_lo_data  = cdma2buf_dat_wr_data[512-1:0];
assign cbuf_p0_wr_hi_data  = cdma2buf_dat_wr_data[512*2-1:512];
assign cbuf_p0_wr_addr     = cdma2buf_dat_wr_addr[12-1:0];

assign cbuf_p1_wr_en       = cdma2buf_wt_wr_en;
assign cbuf_p1_wr_lo_en    = cdma2buf_wt_wr_en & ~cdma2buf_wt_wr_hsel;
assign cbuf_p1_wr_hi_en    = cdma2buf_wt_wr_en & cdma2buf_wt_wr_hsel;
assign cbuf_p1_wr_data     = cdma2buf_wt_wr_data;
assign cbuf_p1_wr_addr     = cdma2buf_wt_wr_addr[12-1:0];


assign cbuf_p0_wr_lo_data_d1_w = cbuf_p0_wr_lo_data;
assign cbuf_p0_wr_hi_data_d1_w = cbuf_p0_wr_hi_data;
assign cbuf_p0_wr_lo_en_d1_w = cbuf_p0_wr_lo_en;
assign cbuf_p0_wr_hi_en_d1_w = cbuf_p0_wr_hi_en;
assign cbuf_p1_wr_lo_data_d1_w = cbuf_p1_wr_data;
assign cbuf_p1_wr_hi_data_d1_w = cbuf_p1_wr_data;
assign cbuf_p1_wr_lo_en_d1_w = cbuf_p1_wr_lo_en;
assign cbuf_p1_wr_hi_en_d1_w = cbuf_p1_wr_hi_en;


////////////////////////////////////////////////////////////////////////
// Input write stage1: misc logic                                     //
////////////////////////////////////////////////////////////////////////
// bank 解码 + 每 RAM 写选择：addr[11:8] 与各 bank 号比较、与半字使能
// 相与，得到 one-hot 写选通 *_sel_ram_bXcY_w。注意 sel 共 60 个而非 64：
// p0(dat) 只解码 b0..b14、p1(wt) 只解码 b1..b15——「dat 不进 bank15、
// wt 不进 bank0」的分区规则直接硬编码在解码范围里，越界写会被静默丢弃
// （另有断言抓）。以下为逐 bank 机械重复，看懂 b0c0/b0c1 一组即可
assign cbuf_p0_wr_bank = cbuf_p0_wr_addr[12-1:8];
assign cbuf_p1_wr_bank = cbuf_p1_wr_addr[12-1:8];

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b0c0_w = (cbuf_p0_wr_bank == 4'd0)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b0c1_w = (cbuf_p0_wr_bank == 4'd0)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b1c0_w = (cbuf_p0_wr_bank == 4'd1)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b1c1_w = (cbuf_p0_wr_bank == 4'd1)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b2c0_w = (cbuf_p0_wr_bank == 4'd2)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b2c1_w = (cbuf_p0_wr_bank == 4'd2)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b3c0_w = (cbuf_p0_wr_bank == 4'd3)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b3c1_w = (cbuf_p0_wr_bank == 4'd3)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b4c0_w = (cbuf_p0_wr_bank == 4'd4)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b4c1_w = (cbuf_p0_wr_bank == 4'd4)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b5c0_w = (cbuf_p0_wr_bank == 4'd5)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b5c1_w = (cbuf_p0_wr_bank == 4'd5)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b6c0_w = (cbuf_p0_wr_bank == 4'd6)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b6c1_w = (cbuf_p0_wr_bank == 4'd6)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b7c0_w = (cbuf_p0_wr_bank == 4'd7)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b7c1_w = (cbuf_p0_wr_bank == 4'd7)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b8c0_w = (cbuf_p0_wr_bank == 4'd8)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b8c1_w = (cbuf_p0_wr_bank == 4'd8)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b9c0_w = (cbuf_p0_wr_bank == 4'd9)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b9c1_w = (cbuf_p0_wr_bank == 4'd9)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b10c0_w = (cbuf_p0_wr_bank == 4'd10)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b10c1_w = (cbuf_p0_wr_bank == 4'd10)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b11c0_w = (cbuf_p0_wr_bank == 4'd11)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b11c1_w = (cbuf_p0_wr_bank == 4'd11)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b12c0_w = (cbuf_p0_wr_bank == 4'd12)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b12c1_w = (cbuf_p0_wr_bank == 4'd12)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b13c0_w = (cbuf_p0_wr_bank == 4'd13)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b13c1_w = (cbuf_p0_wr_bank == 4'd13)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_lo_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b14c0_w = (cbuf_p0_wr_bank == 4'd14)
                                && (cbuf_p0_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p0_wr_bank
  or cbuf_p0_wr_hi_en_d1_w
  ) begin
    cbuf_p0_wr_sel_ram_b14c1_w = (cbuf_p0_wr_bank == 4'd14)
                                && (cbuf_p0_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b1c0_w = (cbuf_p1_wr_bank == 4'd1)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b1c1_w = (cbuf_p1_wr_bank == 4'd1)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b2c0_w = (cbuf_p1_wr_bank == 4'd2)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b2c1_w = (cbuf_p1_wr_bank == 4'd2)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b3c0_w = (cbuf_p1_wr_bank == 4'd3)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b3c1_w = (cbuf_p1_wr_bank == 4'd3)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b4c0_w = (cbuf_p1_wr_bank == 4'd4)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b4c1_w = (cbuf_p1_wr_bank == 4'd4)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b5c0_w = (cbuf_p1_wr_bank == 4'd5)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b5c1_w = (cbuf_p1_wr_bank == 4'd5)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b6c0_w = (cbuf_p1_wr_bank == 4'd6)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b6c1_w = (cbuf_p1_wr_bank == 4'd6)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b7c0_w = (cbuf_p1_wr_bank == 4'd7)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b7c1_w = (cbuf_p1_wr_bank == 4'd7)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b8c0_w = (cbuf_p1_wr_bank == 4'd8)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b8c1_w = (cbuf_p1_wr_bank == 4'd8)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b9c0_w = (cbuf_p1_wr_bank == 4'd9)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b9c1_w = (cbuf_p1_wr_bank == 4'd9)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b10c0_w = (cbuf_p1_wr_bank == 4'd10)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b10c1_w = (cbuf_p1_wr_bank == 4'd10)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b11c0_w = (cbuf_p1_wr_bank == 4'd11)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b11c1_w = (cbuf_p1_wr_bank == 4'd11)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b12c0_w = (cbuf_p1_wr_bank == 4'd12)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b12c1_w = (cbuf_p1_wr_bank == 4'd12)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b13c0_w = (cbuf_p1_wr_bank == 4'd13)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b13c1_w = (cbuf_p1_wr_bank == 4'd13)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b14c0_w = (cbuf_p1_wr_bank == 4'd14)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b14c1_w = (cbuf_p1_wr_bank == 4'd14)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_lo_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b15c0_w = (cbuf_p1_wr_bank == 4'd15)
                                && (cbuf_p1_wr_lo_en_d1_w == 1'b1);
end

always @(
  cbuf_p1_wr_bank
  or cbuf_p1_wr_hi_en_d1_w
  ) begin
    cbuf_p1_wr_sel_ram_b15c1_w = (cbuf_p1_wr_bank == 4'd15)
                                && (cbuf_p1_wr_hi_en_d1_w == 1'b1);
end

////////////////////////////////////////////////////////////////////////
// Input write stage1 registers                                       //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_wr_sel_ram_d1 <= {60{1'b0}};
  end else begin
  cbuf_wr_sel_ram_d1 <= {cbuf_p0_wr_sel_ram_b0c0_w,
                         cbuf_p0_wr_sel_ram_b0c1_w,
                         cbuf_p0_wr_sel_ram_b1c0_w,
                         cbuf_p0_wr_sel_ram_b1c1_w,
                         cbuf_p0_wr_sel_ram_b2c0_w,
                         cbuf_p0_wr_sel_ram_b2c1_w,
                         cbuf_p0_wr_sel_ram_b3c0_w,
                         cbuf_p0_wr_sel_ram_b3c1_w,
                         cbuf_p0_wr_sel_ram_b4c0_w,
                         cbuf_p0_wr_sel_ram_b4c1_w,
                         cbuf_p0_wr_sel_ram_b5c0_w,
                         cbuf_p0_wr_sel_ram_b5c1_w,
                         cbuf_p0_wr_sel_ram_b6c0_w,
                         cbuf_p0_wr_sel_ram_b6c1_w,
                         cbuf_p0_wr_sel_ram_b7c0_w,
                         cbuf_p0_wr_sel_ram_b7c1_w,
                         cbuf_p0_wr_sel_ram_b8c0_w,
                         cbuf_p0_wr_sel_ram_b8c1_w,
                         cbuf_p0_wr_sel_ram_b9c0_w,
                         cbuf_p0_wr_sel_ram_b9c1_w,
                         cbuf_p0_wr_sel_ram_b10c0_w,
                         cbuf_p0_wr_sel_ram_b10c1_w,
                         cbuf_p0_wr_sel_ram_b11c0_w,
                         cbuf_p0_wr_sel_ram_b11c1_w,
                         cbuf_p0_wr_sel_ram_b12c0_w,
                         cbuf_p0_wr_sel_ram_b12c1_w,
                         cbuf_p0_wr_sel_ram_b13c0_w,
                         cbuf_p0_wr_sel_ram_b13c1_w,
                         cbuf_p0_wr_sel_ram_b14c0_w,
                         cbuf_p0_wr_sel_ram_b14c1_w,
                         cbuf_p1_wr_sel_ram_b1c0_w,
                         cbuf_p1_wr_sel_ram_b1c1_w,
                         cbuf_p1_wr_sel_ram_b2c0_w,
                         cbuf_p1_wr_sel_ram_b2c1_w,
                         cbuf_p1_wr_sel_ram_b3c0_w,
                         cbuf_p1_wr_sel_ram_b3c1_w,
                         cbuf_p1_wr_sel_ram_b4c0_w,
                         cbuf_p1_wr_sel_ram_b4c1_w,
                         cbuf_p1_wr_sel_ram_b5c0_w,
                         cbuf_p1_wr_sel_ram_b5c1_w,
                         cbuf_p1_wr_sel_ram_b6c0_w,
                         cbuf_p1_wr_sel_ram_b6c1_w,
                         cbuf_p1_wr_sel_ram_b7c0_w,
                         cbuf_p1_wr_sel_ram_b7c1_w,
                         cbuf_p1_wr_sel_ram_b8c0_w,
                         cbuf_p1_wr_sel_ram_b8c1_w,
                         cbuf_p1_wr_sel_ram_b9c0_w,
                         cbuf_p1_wr_sel_ram_b9c1_w,
                         cbuf_p1_wr_sel_ram_b10c0_w,
                         cbuf_p1_wr_sel_ram_b10c1_w,
                         cbuf_p1_wr_sel_ram_b11c0_w,
                         cbuf_p1_wr_sel_ram_b11c1_w,
                         cbuf_p1_wr_sel_ram_b12c0_w,
                         cbuf_p1_wr_sel_ram_b12c1_w,
                         cbuf_p1_wr_sel_ram_b13c0_w,
                         cbuf_p1_wr_sel_ram_b13c1_w,
                         cbuf_p1_wr_sel_ram_b14c0_w,
                         cbuf_p1_wr_sel_ram_b14c1_w,
                         cbuf_p1_wr_sel_ram_b15c0_w,
                         cbuf_p1_wr_sel_ram_b15c1_w};
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b0c0 <= 1'b0;
  end else begin
  cbuf_we_b0c0 <= cbuf_p0_wr_sel_ram_b0c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b0c1 <= 1'b0;
  end else begin
  cbuf_we_b0c1 <= cbuf_p0_wr_sel_ram_b0c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b1c0 <= 1'b0;
  end else begin
  cbuf_we_b1c0 <= cbuf_p0_wr_sel_ram_b1c0_w | cbuf_p1_wr_sel_ram_b1c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b1c1 <= 1'b0;
  end else begin
  cbuf_we_b1c1 <= cbuf_p0_wr_sel_ram_b1c1_w | cbuf_p1_wr_sel_ram_b1c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b2c0 <= 1'b0;
  end else begin
  cbuf_we_b2c0 <= cbuf_p0_wr_sel_ram_b2c0_w | cbuf_p1_wr_sel_ram_b2c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b2c1 <= 1'b0;
  end else begin
  cbuf_we_b2c1 <= cbuf_p0_wr_sel_ram_b2c1_w | cbuf_p1_wr_sel_ram_b2c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b3c0 <= 1'b0;
  end else begin
  cbuf_we_b3c0 <= cbuf_p0_wr_sel_ram_b3c0_w | cbuf_p1_wr_sel_ram_b3c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b3c1 <= 1'b0;
  end else begin
  cbuf_we_b3c1 <= cbuf_p0_wr_sel_ram_b3c1_w | cbuf_p1_wr_sel_ram_b3c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b4c0 <= 1'b0;
  end else begin
  cbuf_we_b4c0 <= cbuf_p0_wr_sel_ram_b4c0_w | cbuf_p1_wr_sel_ram_b4c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b4c1 <= 1'b0;
  end else begin
  cbuf_we_b4c1 <= cbuf_p0_wr_sel_ram_b4c1_w | cbuf_p1_wr_sel_ram_b4c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b5c0 <= 1'b0;
  end else begin
  cbuf_we_b5c0 <= cbuf_p0_wr_sel_ram_b5c0_w | cbuf_p1_wr_sel_ram_b5c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b5c1 <= 1'b0;
  end else begin
  cbuf_we_b5c1 <= cbuf_p0_wr_sel_ram_b5c1_w | cbuf_p1_wr_sel_ram_b5c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b6c0 <= 1'b0;
  end else begin
  cbuf_we_b6c0 <= cbuf_p0_wr_sel_ram_b6c0_w | cbuf_p1_wr_sel_ram_b6c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b6c1 <= 1'b0;
  end else begin
  cbuf_we_b6c1 <= cbuf_p0_wr_sel_ram_b6c1_w | cbuf_p1_wr_sel_ram_b6c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b7c0 <= 1'b0;
  end else begin
  cbuf_we_b7c0 <= cbuf_p0_wr_sel_ram_b7c0_w | cbuf_p1_wr_sel_ram_b7c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b7c1 <= 1'b0;
  end else begin
  cbuf_we_b7c1 <= cbuf_p0_wr_sel_ram_b7c1_w | cbuf_p1_wr_sel_ram_b7c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b8c0 <= 1'b0;
  end else begin
  cbuf_we_b8c0 <= cbuf_p0_wr_sel_ram_b8c0_w | cbuf_p1_wr_sel_ram_b8c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b8c1 <= 1'b0;
  end else begin
  cbuf_we_b8c1 <= cbuf_p0_wr_sel_ram_b8c1_w | cbuf_p1_wr_sel_ram_b8c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b9c0 <= 1'b0;
  end else begin
  cbuf_we_b9c0 <= cbuf_p0_wr_sel_ram_b9c0_w | cbuf_p1_wr_sel_ram_b9c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b9c1 <= 1'b0;
  end else begin
  cbuf_we_b9c1 <= cbuf_p0_wr_sel_ram_b9c1_w | cbuf_p1_wr_sel_ram_b9c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b10c0 <= 1'b0;
  end else begin
  cbuf_we_b10c0 <= cbuf_p0_wr_sel_ram_b10c0_w | cbuf_p1_wr_sel_ram_b10c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b10c1 <= 1'b0;
  end else begin
  cbuf_we_b10c1 <= cbuf_p0_wr_sel_ram_b10c1_w | cbuf_p1_wr_sel_ram_b10c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b11c0 <= 1'b0;
  end else begin
  cbuf_we_b11c0 <= cbuf_p0_wr_sel_ram_b11c0_w | cbuf_p1_wr_sel_ram_b11c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b11c1 <= 1'b0;
  end else begin
  cbuf_we_b11c1 <= cbuf_p0_wr_sel_ram_b11c1_w | cbuf_p1_wr_sel_ram_b11c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b12c0 <= 1'b0;
  end else begin
  cbuf_we_b12c0 <= cbuf_p0_wr_sel_ram_b12c0_w | cbuf_p1_wr_sel_ram_b12c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b12c1 <= 1'b0;
  end else begin
  cbuf_we_b12c1 <= cbuf_p0_wr_sel_ram_b12c1_w | cbuf_p1_wr_sel_ram_b12c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b13c0 <= 1'b0;
  end else begin
  cbuf_we_b13c0 <= cbuf_p0_wr_sel_ram_b13c0_w | cbuf_p1_wr_sel_ram_b13c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b13c1 <= 1'b0;
  end else begin
  cbuf_we_b13c1 <= cbuf_p0_wr_sel_ram_b13c1_w | cbuf_p1_wr_sel_ram_b13c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b14c0 <= 1'b0;
  end else begin
  cbuf_we_b14c0 <= cbuf_p0_wr_sel_ram_b14c0_w | cbuf_p1_wr_sel_ram_b14c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b14c1 <= 1'b0;
  end else begin
  cbuf_we_b14c1 <= cbuf_p0_wr_sel_ram_b14c1_w | cbuf_p1_wr_sel_ram_b14c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b15c0 <= 1'b0;
  end else begin
  cbuf_we_b15c0 <= cbuf_p1_wr_sel_ram_b15c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b15c1 <= 1'b0;
  end else begin
  cbuf_we_b15c1 <= cbuf_p1_wr_sel_ram_b15c1_w;
  end
end

always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_wr_en) == 1'b1) begin
    cbuf_p0_wr_addr_d1 <= cbuf_p0_wr_addr[8-1:0];
  // VCS coverage off
  end else if ((cbuf_p0_wr_en) == 1'b0) begin
  end else begin
    cbuf_p0_wr_addr_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_wr_en) == 1'b1) begin
    cbuf_p1_wr_addr_d1 <= cbuf_p1_wr_addr[8-1:0];
  // VCS coverage off
  end else if ((cbuf_p1_wr_en) == 1'b0) begin
  end else begin
    cbuf_p1_wr_addr_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end

always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_wr_lo_en_d1_w) == 1'b1) begin
    cbuf_p0_wr_lo_data_d1 <= cbuf_p0_wr_lo_data_d1_w;
  // VCS coverage off
  end else if ((cbuf_p0_wr_lo_en_d1_w) == 1'b0) begin
  end else begin
    cbuf_p0_wr_lo_data_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_wr_hi_en_d1_w) == 1'b1) begin
    cbuf_p0_wr_hi_data_d1 <= cbuf_p0_wr_hi_data_d1_w;
  // VCS coverage off
  end else if ((cbuf_p0_wr_hi_en_d1_w) == 1'b0) begin
  end else begin
    cbuf_p0_wr_hi_data_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_wr_lo_en_d1_w) == 1'b1) begin
    cbuf_p1_wr_lo_data_d1 <= cbuf_p1_wr_lo_data_d1_w;
  // VCS coverage off
  end else if ((cbuf_p1_wr_lo_en_d1_w) == 1'b0) begin
  end else begin
    cbuf_p1_wr_lo_data_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_wr_hi_en_d1_w) == 1'b1) begin
    cbuf_p1_wr_hi_data_d1 <= cbuf_p1_wr_hi_data_d1_w;
  // VCS coverage off
  end else if ((cbuf_p1_wr_hi_en_d1_w) == 1'b0) begin
  end else begin
    cbuf_p1_wr_hi_data_d1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end

////////////////////////////////////////////////////////////////////////
// Input write stage2: write connection to RAM                         //
////////////////////////////////////////////////////////////////////////
// d1 拍的 sel 解包后，把 p0/p1 两个写口的 addr/data 用 sel 掩码汇到每
// 个 RAM 私有的 wa/wdat 上（p0、p1 不同 bank，按位或不会混叠——正是
// "dat/wt 写不撞 bank"断言守护的前提），再打 d2 拍接 RAM 写口
assign {cbuf_p0_wr_sel_ram_b0c0_d1,
        cbuf_p0_wr_sel_ram_b0c1_d1,
        cbuf_p0_wr_sel_ram_b1c0_d1,
        cbuf_p0_wr_sel_ram_b1c1_d1,
        cbuf_p0_wr_sel_ram_b2c0_d1,
        cbuf_p0_wr_sel_ram_b2c1_d1,
        cbuf_p0_wr_sel_ram_b3c0_d1,
        cbuf_p0_wr_sel_ram_b3c1_d1,
        cbuf_p0_wr_sel_ram_b4c0_d1,
        cbuf_p0_wr_sel_ram_b4c1_d1,
        cbuf_p0_wr_sel_ram_b5c0_d1,
        cbuf_p0_wr_sel_ram_b5c1_d1,
        cbuf_p0_wr_sel_ram_b6c0_d1,
        cbuf_p0_wr_sel_ram_b6c1_d1,
        cbuf_p0_wr_sel_ram_b7c0_d1,
        cbuf_p0_wr_sel_ram_b7c1_d1,
        cbuf_p0_wr_sel_ram_b8c0_d1,
        cbuf_p0_wr_sel_ram_b8c1_d1,
        cbuf_p0_wr_sel_ram_b9c0_d1,
        cbuf_p0_wr_sel_ram_b9c1_d1,
        cbuf_p0_wr_sel_ram_b10c0_d1,
        cbuf_p0_wr_sel_ram_b10c1_d1,
        cbuf_p0_wr_sel_ram_b11c0_d1,
        cbuf_p0_wr_sel_ram_b11c1_d1,
        cbuf_p0_wr_sel_ram_b12c0_d1,
        cbuf_p0_wr_sel_ram_b12c1_d1,
        cbuf_p0_wr_sel_ram_b13c0_d1,
        cbuf_p0_wr_sel_ram_b13c1_d1,
        cbuf_p0_wr_sel_ram_b14c0_d1,
        cbuf_p0_wr_sel_ram_b14c1_d1,
        cbuf_p1_wr_sel_ram_b1c0_d1,
        cbuf_p1_wr_sel_ram_b1c1_d1,
        cbuf_p1_wr_sel_ram_b2c0_d1,
        cbuf_p1_wr_sel_ram_b2c1_d1,
        cbuf_p1_wr_sel_ram_b3c0_d1,
        cbuf_p1_wr_sel_ram_b3c1_d1,
        cbuf_p1_wr_sel_ram_b4c0_d1,
        cbuf_p1_wr_sel_ram_b4c1_d1,
        cbuf_p1_wr_sel_ram_b5c0_d1,
        cbuf_p1_wr_sel_ram_b5c1_d1,
        cbuf_p1_wr_sel_ram_b6c0_d1,
        cbuf_p1_wr_sel_ram_b6c1_d1,
        cbuf_p1_wr_sel_ram_b7c0_d1,
        cbuf_p1_wr_sel_ram_b7c1_d1,
        cbuf_p1_wr_sel_ram_b8c0_d1,
        cbuf_p1_wr_sel_ram_b8c1_d1,
        cbuf_p1_wr_sel_ram_b9c0_d1,
        cbuf_p1_wr_sel_ram_b9c1_d1,
        cbuf_p1_wr_sel_ram_b10c0_d1,
        cbuf_p1_wr_sel_ram_b10c1_d1,
        cbuf_p1_wr_sel_ram_b11c0_d1,
        cbuf_p1_wr_sel_ram_b11c1_d1,
        cbuf_p1_wr_sel_ram_b12c0_d1,
        cbuf_p1_wr_sel_ram_b12c1_d1,
        cbuf_p1_wr_sel_ram_b13c0_d1,
        cbuf_p1_wr_sel_ram_b13c1_d1,
        cbuf_p1_wr_sel_ram_b14c0_d1,
        cbuf_p1_wr_sel_ram_b14c1_d1,
        cbuf_p1_wr_sel_ram_b15c0_d1,
        cbuf_p1_wr_sel_ram_b15c1_d1} = cbuf_wr_sel_ram_d1;

always @(
  cbuf_p0_wr_sel_ram_b0c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  ) begin
    cbuf_wa_b0c0 =  ({8{cbuf_p0_wr_sel_ram_b0c0_d1}} & cbuf_p0_wr_addr_d1);
    cbuf_wdat_b0c0 =  ({512{cbuf_p0_wr_sel_ram_b0c0_d1}} & cbuf_p0_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b0c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  ) begin
    cbuf_wa_b0c1 =  ({8{cbuf_p0_wr_sel_ram_b0c1_d1}} & cbuf_p0_wr_addr_d1);
    cbuf_wdat_b0c1 =  ({512{cbuf_p0_wr_sel_ram_b0c1_d1}} & cbuf_p0_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b1c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b1c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b1c0 =  ({8{cbuf_p0_wr_sel_ram_b1c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b1c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b1c0 =  ({512{cbuf_p0_wr_sel_ram_b1c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b1c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b1c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b1c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b1c1 =  ({8{cbuf_p0_wr_sel_ram_b1c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b1c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b1c1 =  ({512{cbuf_p0_wr_sel_ram_b1c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b1c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b2c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b2c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b2c0 =  ({8{cbuf_p0_wr_sel_ram_b2c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b2c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b2c0 =  ({512{cbuf_p0_wr_sel_ram_b2c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b2c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b2c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b2c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b2c1 =  ({8{cbuf_p0_wr_sel_ram_b2c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b2c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b2c1 =  ({512{cbuf_p0_wr_sel_ram_b2c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b2c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b3c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b3c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b3c0 =  ({8{cbuf_p0_wr_sel_ram_b3c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b3c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b3c0 =  ({512{cbuf_p0_wr_sel_ram_b3c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b3c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b3c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b3c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b3c1 =  ({8{cbuf_p0_wr_sel_ram_b3c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b3c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b3c1 =  ({512{cbuf_p0_wr_sel_ram_b3c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b3c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b4c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b4c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b4c0 =  ({8{cbuf_p0_wr_sel_ram_b4c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b4c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b4c0 =  ({512{cbuf_p0_wr_sel_ram_b4c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b4c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b4c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b4c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b4c1 =  ({8{cbuf_p0_wr_sel_ram_b4c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b4c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b4c1 =  ({512{cbuf_p0_wr_sel_ram_b4c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b4c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b5c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b5c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b5c0 =  ({8{cbuf_p0_wr_sel_ram_b5c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b5c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b5c0 =  ({512{cbuf_p0_wr_sel_ram_b5c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b5c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b5c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b5c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b5c1 =  ({8{cbuf_p0_wr_sel_ram_b5c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b5c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b5c1 =  ({512{cbuf_p0_wr_sel_ram_b5c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b5c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b6c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b6c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b6c0 =  ({8{cbuf_p0_wr_sel_ram_b6c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b6c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b6c0 =  ({512{cbuf_p0_wr_sel_ram_b6c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b6c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b6c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b6c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b6c1 =  ({8{cbuf_p0_wr_sel_ram_b6c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b6c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b6c1 =  ({512{cbuf_p0_wr_sel_ram_b6c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b6c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b7c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b7c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b7c0 =  ({8{cbuf_p0_wr_sel_ram_b7c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b7c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b7c0 =  ({512{cbuf_p0_wr_sel_ram_b7c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b7c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b7c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b7c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b7c1 =  ({8{cbuf_p0_wr_sel_ram_b7c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b7c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b7c1 =  ({512{cbuf_p0_wr_sel_ram_b7c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b7c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b8c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b8c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b8c0 =  ({8{cbuf_p0_wr_sel_ram_b8c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b8c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b8c0 =  ({512{cbuf_p0_wr_sel_ram_b8c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b8c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b8c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b8c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b8c1 =  ({8{cbuf_p0_wr_sel_ram_b8c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b8c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b8c1 =  ({512{cbuf_p0_wr_sel_ram_b8c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b8c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b9c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b9c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b9c0 =  ({8{cbuf_p0_wr_sel_ram_b9c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b9c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b9c0 =  ({512{cbuf_p0_wr_sel_ram_b9c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b9c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b9c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b9c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b9c1 =  ({8{cbuf_p0_wr_sel_ram_b9c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b9c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b9c1 =  ({512{cbuf_p0_wr_sel_ram_b9c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b9c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b10c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b10c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b10c0 =  ({8{cbuf_p0_wr_sel_ram_b10c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b10c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b10c0 =  ({512{cbuf_p0_wr_sel_ram_b10c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b10c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b10c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b10c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b10c1 =  ({8{cbuf_p0_wr_sel_ram_b10c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b10c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b10c1 =  ({512{cbuf_p0_wr_sel_ram_b10c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b10c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b11c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b11c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b11c0 =  ({8{cbuf_p0_wr_sel_ram_b11c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b11c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b11c0 =  ({512{cbuf_p0_wr_sel_ram_b11c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b11c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b11c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b11c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b11c1 =  ({8{cbuf_p0_wr_sel_ram_b11c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b11c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b11c1 =  ({512{cbuf_p0_wr_sel_ram_b11c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b11c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b12c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b12c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b12c0 =  ({8{cbuf_p0_wr_sel_ram_b12c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b12c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b12c0 =  ({512{cbuf_p0_wr_sel_ram_b12c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b12c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b12c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b12c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b12c1 =  ({8{cbuf_p0_wr_sel_ram_b12c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b12c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b12c1 =  ({512{cbuf_p0_wr_sel_ram_b12c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b12c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b13c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b13c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b13c0 =  ({8{cbuf_p0_wr_sel_ram_b13c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b13c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b13c0 =  ({512{cbuf_p0_wr_sel_ram_b13c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b13c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b13c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b13c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b13c1 =  ({8{cbuf_p0_wr_sel_ram_b13c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b13c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b13c1 =  ({512{cbuf_p0_wr_sel_ram_b13c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b13c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b14c0_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b14c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_lo_data_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b14c0 =  ({8{cbuf_p0_wr_sel_ram_b14c0_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b14c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b14c0 =  ({512{cbuf_p0_wr_sel_ram_b14c0_d1}} & cbuf_p0_wr_lo_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b14c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p0_wr_sel_ram_b14c1_d1
  or cbuf_p0_wr_addr_d1
  or cbuf_p1_wr_sel_ram_b14c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p0_wr_hi_data_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b14c1 =  ({8{cbuf_p0_wr_sel_ram_b14c1_d1}} & cbuf_p0_wr_addr_d1) |
                    ({8{cbuf_p1_wr_sel_ram_b14c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b14c1 =  ({512{cbuf_p0_wr_sel_ram_b14c1_d1}} & cbuf_p0_wr_hi_data_d1) |
                      ({512{cbuf_p1_wr_sel_ram_b14c1_d1}} & cbuf_p1_wr_hi_data_d1);
end

always @(
  cbuf_p1_wr_sel_ram_b15c0_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p1_wr_lo_data_d1
  ) begin
    cbuf_wa_b15c0 =  ({8{cbuf_p1_wr_sel_ram_b15c0_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b15c0 =  ({512{cbuf_p1_wr_sel_ram_b15c0_d1}} & cbuf_p1_wr_lo_data_d1);
end

always @(
  cbuf_p1_wr_sel_ram_b15c1_d1
  or cbuf_p1_wr_addr_d1
  or cbuf_p1_wr_hi_data_d1
  ) begin
    cbuf_wa_b15c1 =  ({8{cbuf_p1_wr_sel_ram_b15c1_d1}} & cbuf_p1_wr_addr_d1);
    cbuf_wdat_b15c1 =  ({512{cbuf_p1_wr_sel_ram_b15c1_d1}} & cbuf_p1_wr_hi_data_d1);
end



////////////////////////////////////////////////////////////////////////
// Write retiming registers                                           //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b0c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b0c0_d2 <= cbuf_we_b0c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b0c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b0c1_d2 <= cbuf_we_b0c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b1c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b1c0_d2 <= cbuf_we_b1c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b1c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b1c1_d2 <= cbuf_we_b1c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b2c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b2c0_d2 <= cbuf_we_b2c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b2c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b2c1_d2 <= cbuf_we_b2c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b3c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b3c0_d2 <= cbuf_we_b3c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b3c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b3c1_d2 <= cbuf_we_b3c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b4c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b4c0_d2 <= cbuf_we_b4c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b4c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b4c1_d2 <= cbuf_we_b4c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b5c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b5c0_d2 <= cbuf_we_b5c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b5c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b5c1_d2 <= cbuf_we_b5c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b6c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b6c0_d2 <= cbuf_we_b6c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b6c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b6c1_d2 <= cbuf_we_b6c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b7c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b7c0_d2 <= cbuf_we_b7c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b7c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b7c1_d2 <= cbuf_we_b7c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b8c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b8c0_d2 <= cbuf_we_b8c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b8c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b8c1_d2 <= cbuf_we_b8c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b9c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b9c0_d2 <= cbuf_we_b9c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b9c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b9c1_d2 <= cbuf_we_b9c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b10c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b10c0_d2 <= cbuf_we_b10c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b10c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b10c1_d2 <= cbuf_we_b10c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b11c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b11c0_d2 <= cbuf_we_b11c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b11c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b11c1_d2 <= cbuf_we_b11c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b12c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b12c0_d2 <= cbuf_we_b12c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b12c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b12c1_d2 <= cbuf_we_b12c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b13c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b13c0_d2 <= cbuf_we_b13c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b13c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b13c1_d2 <= cbuf_we_b13c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b14c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b14c0_d2 <= cbuf_we_b14c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b14c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b14c1_d2 <= cbuf_we_b14c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b15c0_d2 <= 1'b0;
  end else begin
  cbuf_we_b15c0_d2 <= cbuf_we_b15c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_we_b15c1_d2 <= 1'b0;
  end else begin
  cbuf_we_b15c1_d2 <= cbuf_we_b15c1;
  end
end


always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b0c0) == 1'b1) begin
    cbuf_wa_b0c0_d2 <= cbuf_wa_b0c0;
  // VCS coverage off
  end else if ((cbuf_we_b0c0) == 1'b0) begin
  end else begin
    cbuf_wa_b0c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b0c1) == 1'b1) begin
    cbuf_wa_b0c1_d2 <= cbuf_wa_b0c1;
  // VCS coverage off
  end else if ((cbuf_we_b0c1) == 1'b0) begin
  end else begin
    cbuf_wa_b0c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b1c0) == 1'b1) begin
    cbuf_wa_b1c0_d2 <= cbuf_wa_b1c0;
  // VCS coverage off
  end else if ((cbuf_we_b1c0) == 1'b0) begin
  end else begin
    cbuf_wa_b1c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b1c1) == 1'b1) begin
    cbuf_wa_b1c1_d2 <= cbuf_wa_b1c1;
  // VCS coverage off
  end else if ((cbuf_we_b1c1) == 1'b0) begin
  end else begin
    cbuf_wa_b1c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b2c0) == 1'b1) begin
    cbuf_wa_b2c0_d2 <= cbuf_wa_b2c0;
  // VCS coverage off
  end else if ((cbuf_we_b2c0) == 1'b0) begin
  end else begin
    cbuf_wa_b2c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b2c1) == 1'b1) begin
    cbuf_wa_b2c1_d2 <= cbuf_wa_b2c1;
  // VCS coverage off
  end else if ((cbuf_we_b2c1) == 1'b0) begin
  end else begin
    cbuf_wa_b2c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b3c0) == 1'b1) begin
    cbuf_wa_b3c0_d2 <= cbuf_wa_b3c0;
  // VCS coverage off
  end else if ((cbuf_we_b3c0) == 1'b0) begin
  end else begin
    cbuf_wa_b3c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b3c1) == 1'b1) begin
    cbuf_wa_b3c1_d2 <= cbuf_wa_b3c1;
  // VCS coverage off
  end else if ((cbuf_we_b3c1) == 1'b0) begin
  end else begin
    cbuf_wa_b3c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b4c0) == 1'b1) begin
    cbuf_wa_b4c0_d2 <= cbuf_wa_b4c0;
  // VCS coverage off
  end else if ((cbuf_we_b4c0) == 1'b0) begin
  end else begin
    cbuf_wa_b4c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b4c1) == 1'b1) begin
    cbuf_wa_b4c1_d2 <= cbuf_wa_b4c1;
  // VCS coverage off
  end else if ((cbuf_we_b4c1) == 1'b0) begin
  end else begin
    cbuf_wa_b4c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b5c0) == 1'b1) begin
    cbuf_wa_b5c0_d2 <= cbuf_wa_b5c0;
  // VCS coverage off
  end else if ((cbuf_we_b5c0) == 1'b0) begin
  end else begin
    cbuf_wa_b5c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b5c1) == 1'b1) begin
    cbuf_wa_b5c1_d2 <= cbuf_wa_b5c1;
  // VCS coverage off
  end else if ((cbuf_we_b5c1) == 1'b0) begin
  end else begin
    cbuf_wa_b5c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b6c0) == 1'b1) begin
    cbuf_wa_b6c0_d2 <= cbuf_wa_b6c0;
  // VCS coverage off
  end else if ((cbuf_we_b6c0) == 1'b0) begin
  end else begin
    cbuf_wa_b6c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b6c1) == 1'b1) begin
    cbuf_wa_b6c1_d2 <= cbuf_wa_b6c1;
  // VCS coverage off
  end else if ((cbuf_we_b6c1) == 1'b0) begin
  end else begin
    cbuf_wa_b6c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b7c0) == 1'b1) begin
    cbuf_wa_b7c0_d2 <= cbuf_wa_b7c0;
  // VCS coverage off
  end else if ((cbuf_we_b7c0) == 1'b0) begin
  end else begin
    cbuf_wa_b7c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b7c1) == 1'b1) begin
    cbuf_wa_b7c1_d2 <= cbuf_wa_b7c1;
  // VCS coverage off
  end else if ((cbuf_we_b7c1) == 1'b0) begin
  end else begin
    cbuf_wa_b7c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b8c0) == 1'b1) begin
    cbuf_wa_b8c0_d2 <= cbuf_wa_b8c0;
  // VCS coverage off
  end else if ((cbuf_we_b8c0) == 1'b0) begin
  end else begin
    cbuf_wa_b8c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b8c1) == 1'b1) begin
    cbuf_wa_b8c1_d2 <= cbuf_wa_b8c1;
  // VCS coverage off
  end else if ((cbuf_we_b8c1) == 1'b0) begin
  end else begin
    cbuf_wa_b8c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b9c0) == 1'b1) begin
    cbuf_wa_b9c0_d2 <= cbuf_wa_b9c0;
  // VCS coverage off
  end else if ((cbuf_we_b9c0) == 1'b0) begin
  end else begin
    cbuf_wa_b9c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b9c1) == 1'b1) begin
    cbuf_wa_b9c1_d2 <= cbuf_wa_b9c1;
  // VCS coverage off
  end else if ((cbuf_we_b9c1) == 1'b0) begin
  end else begin
    cbuf_wa_b9c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b10c0) == 1'b1) begin
    cbuf_wa_b10c0_d2 <= cbuf_wa_b10c0;
  // VCS coverage off
  end else if ((cbuf_we_b10c0) == 1'b0) begin
  end else begin
    cbuf_wa_b10c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b10c1) == 1'b1) begin
    cbuf_wa_b10c1_d2 <= cbuf_wa_b10c1;
  // VCS coverage off
  end else if ((cbuf_we_b10c1) == 1'b0) begin
  end else begin
    cbuf_wa_b10c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b11c0) == 1'b1) begin
    cbuf_wa_b11c0_d2 <= cbuf_wa_b11c0;
  // VCS coverage off
  end else if ((cbuf_we_b11c0) == 1'b0) begin
  end else begin
    cbuf_wa_b11c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b11c1) == 1'b1) begin
    cbuf_wa_b11c1_d2 <= cbuf_wa_b11c1;
  // VCS coverage off
  end else if ((cbuf_we_b11c1) == 1'b0) begin
  end else begin
    cbuf_wa_b11c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b12c0) == 1'b1) begin
    cbuf_wa_b12c0_d2 <= cbuf_wa_b12c0;
  // VCS coverage off
  end else if ((cbuf_we_b12c0) == 1'b0) begin
  end else begin
    cbuf_wa_b12c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b12c1) == 1'b1) begin
    cbuf_wa_b12c1_d2 <= cbuf_wa_b12c1;
  // VCS coverage off
  end else if ((cbuf_we_b12c1) == 1'b0) begin
  end else begin
    cbuf_wa_b12c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b13c0) == 1'b1) begin
    cbuf_wa_b13c0_d2 <= cbuf_wa_b13c0;
  // VCS coverage off
  end else if ((cbuf_we_b13c0) == 1'b0) begin
  end else begin
    cbuf_wa_b13c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b13c1) == 1'b1) begin
    cbuf_wa_b13c1_d2 <= cbuf_wa_b13c1;
  // VCS coverage off
  end else if ((cbuf_we_b13c1) == 1'b0) begin
  end else begin
    cbuf_wa_b13c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b14c0) == 1'b1) begin
    cbuf_wa_b14c0_d2 <= cbuf_wa_b14c0;
  // VCS coverage off
  end else if ((cbuf_we_b14c0) == 1'b0) begin
  end else begin
    cbuf_wa_b14c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b14c1) == 1'b1) begin
    cbuf_wa_b14c1_d2 <= cbuf_wa_b14c1;
  // VCS coverage off
  end else if ((cbuf_we_b14c1) == 1'b0) begin
  end else begin
    cbuf_wa_b14c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b15c0) == 1'b1) begin
    cbuf_wa_b15c0_d2 <= cbuf_wa_b15c0;
  // VCS coverage off
  end else if ((cbuf_we_b15c0) == 1'b0) begin
  end else begin
    cbuf_wa_b15c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b15c1) == 1'b1) begin
    cbuf_wa_b15c1_d2 <= cbuf_wa_b15c1;
  // VCS coverage off
  end else if ((cbuf_we_b15c1) == 1'b0) begin
  end else begin
    cbuf_wa_b15c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end


always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b0c0) == 1'b1) begin
    cbuf_wdat_b0c0_d2 <= cbuf_wdat_b0c0;
  // VCS coverage off
  end else if ((cbuf_we_b0c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b0c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b0c1) == 1'b1) begin
    cbuf_wdat_b0c1_d2 <= cbuf_wdat_b0c1;
  // VCS coverage off
  end else if ((cbuf_we_b0c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b0c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b1c0) == 1'b1) begin
    cbuf_wdat_b1c0_d2 <= cbuf_wdat_b1c0;
  // VCS coverage off
  end else if ((cbuf_we_b1c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b1c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b1c1) == 1'b1) begin
    cbuf_wdat_b1c1_d2 <= cbuf_wdat_b1c1;
  // VCS coverage off
  end else if ((cbuf_we_b1c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b1c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b2c0) == 1'b1) begin
    cbuf_wdat_b2c0_d2 <= cbuf_wdat_b2c0;
  // VCS coverage off
  end else if ((cbuf_we_b2c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b2c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b2c1) == 1'b1) begin
    cbuf_wdat_b2c1_d2 <= cbuf_wdat_b2c1;
  // VCS coverage off
  end else if ((cbuf_we_b2c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b2c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b3c0) == 1'b1) begin
    cbuf_wdat_b3c0_d2 <= cbuf_wdat_b3c0;
  // VCS coverage off
  end else if ((cbuf_we_b3c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b3c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b3c1) == 1'b1) begin
    cbuf_wdat_b3c1_d2 <= cbuf_wdat_b3c1;
  // VCS coverage off
  end else if ((cbuf_we_b3c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b3c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b4c0) == 1'b1) begin
    cbuf_wdat_b4c0_d2 <= cbuf_wdat_b4c0;
  // VCS coverage off
  end else if ((cbuf_we_b4c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b4c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b4c1) == 1'b1) begin
    cbuf_wdat_b4c1_d2 <= cbuf_wdat_b4c1;
  // VCS coverage off
  end else if ((cbuf_we_b4c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b4c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b5c0) == 1'b1) begin
    cbuf_wdat_b5c0_d2 <= cbuf_wdat_b5c0;
  // VCS coverage off
  end else if ((cbuf_we_b5c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b5c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b5c1) == 1'b1) begin
    cbuf_wdat_b5c1_d2 <= cbuf_wdat_b5c1;
  // VCS coverage off
  end else if ((cbuf_we_b5c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b5c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b6c0) == 1'b1) begin
    cbuf_wdat_b6c0_d2 <= cbuf_wdat_b6c0;
  // VCS coverage off
  end else if ((cbuf_we_b6c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b6c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b6c1) == 1'b1) begin
    cbuf_wdat_b6c1_d2 <= cbuf_wdat_b6c1;
  // VCS coverage off
  end else if ((cbuf_we_b6c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b6c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b7c0) == 1'b1) begin
    cbuf_wdat_b7c0_d2 <= cbuf_wdat_b7c0;
  // VCS coverage off
  end else if ((cbuf_we_b7c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b7c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b7c1) == 1'b1) begin
    cbuf_wdat_b7c1_d2 <= cbuf_wdat_b7c1;
  // VCS coverage off
  end else if ((cbuf_we_b7c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b7c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b8c0) == 1'b1) begin
    cbuf_wdat_b8c0_d2 <= cbuf_wdat_b8c0;
  // VCS coverage off
  end else if ((cbuf_we_b8c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b8c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b8c1) == 1'b1) begin
    cbuf_wdat_b8c1_d2 <= cbuf_wdat_b8c1;
  // VCS coverage off
  end else if ((cbuf_we_b8c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b8c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b9c0) == 1'b1) begin
    cbuf_wdat_b9c0_d2 <= cbuf_wdat_b9c0;
  // VCS coverage off
  end else if ((cbuf_we_b9c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b9c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b9c1) == 1'b1) begin
    cbuf_wdat_b9c1_d2 <= cbuf_wdat_b9c1;
  // VCS coverage off
  end else if ((cbuf_we_b9c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b9c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b10c0) == 1'b1) begin
    cbuf_wdat_b10c0_d2 <= cbuf_wdat_b10c0;
  // VCS coverage off
  end else if ((cbuf_we_b10c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b10c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b10c1) == 1'b1) begin
    cbuf_wdat_b10c1_d2 <= cbuf_wdat_b10c1;
  // VCS coverage off
  end else if ((cbuf_we_b10c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b10c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b11c0) == 1'b1) begin
    cbuf_wdat_b11c0_d2 <= cbuf_wdat_b11c0;
  // VCS coverage off
  end else if ((cbuf_we_b11c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b11c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b11c1) == 1'b1) begin
    cbuf_wdat_b11c1_d2 <= cbuf_wdat_b11c1;
  // VCS coverage off
  end else if ((cbuf_we_b11c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b11c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b12c0) == 1'b1) begin
    cbuf_wdat_b12c0_d2 <= cbuf_wdat_b12c0;
  // VCS coverage off
  end else if ((cbuf_we_b12c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b12c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b12c1) == 1'b1) begin
    cbuf_wdat_b12c1_d2 <= cbuf_wdat_b12c1;
  // VCS coverage off
  end else if ((cbuf_we_b12c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b12c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b13c0) == 1'b1) begin
    cbuf_wdat_b13c0_d2 <= cbuf_wdat_b13c0;
  // VCS coverage off
  end else if ((cbuf_we_b13c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b13c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b13c1) == 1'b1) begin
    cbuf_wdat_b13c1_d2 <= cbuf_wdat_b13c1;
  // VCS coverage off
  end else if ((cbuf_we_b13c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b13c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b14c0) == 1'b1) begin
    cbuf_wdat_b14c0_d2 <= cbuf_wdat_b14c0;
  // VCS coverage off
  end else if ((cbuf_we_b14c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b14c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b14c1) == 1'b1) begin
    cbuf_wdat_b14c1_d2 <= cbuf_wdat_b14c1;
  // VCS coverage off
  end else if ((cbuf_we_b14c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b14c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b15c0) == 1'b1) begin
    cbuf_wdat_b15c0_d2 <= cbuf_wdat_b15c0;
  // VCS coverage off
  end else if ((cbuf_we_b15c0) == 1'b0) begin
  end else begin
    cbuf_wdat_b15c0_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_we_b15c1) == 1'b1) begin
    cbuf_wdat_b15c1_d2 <= cbuf_wdat_b15c1;
  // VCS coverage off
  end else if ((cbuf_we_b15c1) == 1'b0) begin
  end else begin
    cbuf_wdat_b15c1_d2 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end


////////////////////////////////////////////////////////////////////////
// Instance RAMs                                                      //
////////////////////////////////////////////////////////////////////////
// 32 个同构 RAM（16 bank × 2 column，rws = 一读一写口可同拍），写侧接
// d2 级寄存信号，读侧 ra/re 为寄存输出、dout 下一拍有效。bank 间完全
// 独立，这就是"不同客户端只要不撞同一 bank 就无冲突"的物理依据

nv_ram_rws_256x512 u_cbuf_ram_bank0_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b0c0[7:0])         //|< r
  ,.re            (cbuf_re_b0c0)              //|< r
  ,.dout          (cbuf_rdat_b0c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b0c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b0c0_d2)           //|< r
  ,.di            (cbuf_wdat_b0c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank0_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b0c1[7:0])         //|< r
  ,.re            (cbuf_re_b0c1)              //|< r
  ,.dout          (cbuf_rdat_b0c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b0c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b0c1_d2)           //|< r
  ,.di            (cbuf_wdat_b0c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank1_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b1c0[7:0])         //|< r
  ,.re            (cbuf_re_b1c0)              //|< r
  ,.dout          (cbuf_rdat_b1c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b1c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b1c0_d2)           //|< r
  ,.di            (cbuf_wdat_b1c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank1_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b1c1[7:0])         //|< r
  ,.re            (cbuf_re_b1c1)              //|< r
  ,.dout          (cbuf_rdat_b1c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b1c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b1c1_d2)           //|< r
  ,.di            (cbuf_wdat_b1c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank2_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b2c0[7:0])         //|< r
  ,.re            (cbuf_re_b2c0)              //|< r
  ,.dout          (cbuf_rdat_b2c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b2c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b2c0_d2)           //|< r
  ,.di            (cbuf_wdat_b2c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank2_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b2c1[7:0])         //|< r
  ,.re            (cbuf_re_b2c1)              //|< r
  ,.dout          (cbuf_rdat_b2c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b2c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b2c1_d2)           //|< r
  ,.di            (cbuf_wdat_b2c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank3_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b3c0[7:0])         //|< r
  ,.re            (cbuf_re_b3c0)              //|< r
  ,.dout          (cbuf_rdat_b3c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b3c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b3c0_d2)           //|< r
  ,.di            (cbuf_wdat_b3c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank3_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b3c1[7:0])         //|< r
  ,.re            (cbuf_re_b3c1)              //|< r
  ,.dout          (cbuf_rdat_b3c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b3c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b3c1_d2)           //|< r
  ,.di            (cbuf_wdat_b3c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank4_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b4c0[7:0])         //|< r
  ,.re            (cbuf_re_b4c0)              //|< r
  ,.dout          (cbuf_rdat_b4c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b4c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b4c0_d2)           //|< r
  ,.di            (cbuf_wdat_b4c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank4_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b4c1[7:0])         //|< r
  ,.re            (cbuf_re_b4c1)              //|< r
  ,.dout          (cbuf_rdat_b4c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b4c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b4c1_d2)           //|< r
  ,.di            (cbuf_wdat_b4c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank5_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b5c0[7:0])         //|< r
  ,.re            (cbuf_re_b5c0)              //|< r
  ,.dout          (cbuf_rdat_b5c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b5c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b5c0_d2)           //|< r
  ,.di            (cbuf_wdat_b5c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank5_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b5c1[7:0])         //|< r
  ,.re            (cbuf_re_b5c1)              //|< r
  ,.dout          (cbuf_rdat_b5c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b5c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b5c1_d2)           //|< r
  ,.di            (cbuf_wdat_b5c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank6_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b6c0[7:0])         //|< r
  ,.re            (cbuf_re_b6c0)              //|< r
  ,.dout          (cbuf_rdat_b6c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b6c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b6c0_d2)           //|< r
  ,.di            (cbuf_wdat_b6c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank6_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b6c1[7:0])         //|< r
  ,.re            (cbuf_re_b6c1)              //|< r
  ,.dout          (cbuf_rdat_b6c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b6c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b6c1_d2)           //|< r
  ,.di            (cbuf_wdat_b6c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank7_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b7c0[7:0])         //|< r
  ,.re            (cbuf_re_b7c0)              //|< r
  ,.dout          (cbuf_rdat_b7c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b7c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b7c0_d2)           //|< r
  ,.di            (cbuf_wdat_b7c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank7_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b7c1[7:0])         //|< r
  ,.re            (cbuf_re_b7c1)              //|< r
  ,.dout          (cbuf_rdat_b7c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b7c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b7c1_d2)           //|< r
  ,.di            (cbuf_wdat_b7c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank8_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b8c0[7:0])         //|< r
  ,.re            (cbuf_re_b8c0)              //|< r
  ,.dout          (cbuf_rdat_b8c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b8c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b8c0_d2)           //|< r
  ,.di            (cbuf_wdat_b8c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank8_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b8c1[7:0])         //|< r
  ,.re            (cbuf_re_b8c1)              //|< r
  ,.dout          (cbuf_rdat_b8c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b8c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b8c1_d2)           //|< r
  ,.di            (cbuf_wdat_b8c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank9_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b9c0[7:0])         //|< r
  ,.re            (cbuf_re_b9c0)              //|< r
  ,.dout          (cbuf_rdat_b9c0[511:0])     //|> w
  ,.wa            (cbuf_wa_b9c0_d2[7:0])      //|< r
  ,.we            (cbuf_we_b9c0_d2)           //|< r
  ,.di            (cbuf_wdat_b9c0_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank9_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b9c1[7:0])         //|< r
  ,.re            (cbuf_re_b9c1)              //|< r
  ,.dout          (cbuf_rdat_b9c1[511:0])     //|> w
  ,.wa            (cbuf_wa_b9c1_d2[7:0])      //|< r
  ,.we            (cbuf_we_b9c1_d2)           //|< r
  ,.di            (cbuf_wdat_b9c1_d2[511:0])  //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank10_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b10c0[7:0])        //|< r
  ,.re            (cbuf_re_b10c0)             //|< r
  ,.dout          (cbuf_rdat_b10c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b10c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b10c0_d2)          //|< r
  ,.di            (cbuf_wdat_b10c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank10_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b10c1[7:0])        //|< r
  ,.re            (cbuf_re_b10c1)             //|< r
  ,.dout          (cbuf_rdat_b10c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b10c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b10c1_d2)          //|< r
  ,.di            (cbuf_wdat_b10c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank11_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b11c0[7:0])        //|< r
  ,.re            (cbuf_re_b11c0)             //|< r
  ,.dout          (cbuf_rdat_b11c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b11c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b11c0_d2)          //|< r
  ,.di            (cbuf_wdat_b11c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank11_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b11c1[7:0])        //|< r
  ,.re            (cbuf_re_b11c1)             //|< r
  ,.dout          (cbuf_rdat_b11c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b11c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b11c1_d2)          //|< r
  ,.di            (cbuf_wdat_b11c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank12_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b12c0[7:0])        //|< r
  ,.re            (cbuf_re_b12c0)             //|< r
  ,.dout          (cbuf_rdat_b12c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b12c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b12c0_d2)          //|< r
  ,.di            (cbuf_wdat_b12c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank12_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b12c1[7:0])        //|< r
  ,.re            (cbuf_re_b12c1)             //|< r
  ,.dout          (cbuf_rdat_b12c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b12c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b12c1_d2)          //|< r
  ,.di            (cbuf_wdat_b12c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank13_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b13c0[7:0])        //|< r
  ,.re            (cbuf_re_b13c0)             //|< r
  ,.dout          (cbuf_rdat_b13c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b13c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b13c0_d2)          //|< r
  ,.di            (cbuf_wdat_b13c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank13_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b13c1[7:0])        //|< r
  ,.re            (cbuf_re_b13c1)             //|< r
  ,.dout          (cbuf_rdat_b13c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b13c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b13c1_d2)          //|< r
  ,.di            (cbuf_wdat_b13c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank14_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b14c0[7:0])        //|< r
  ,.re            (cbuf_re_b14c0)             //|< r
  ,.dout          (cbuf_rdat_b14c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b14c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b14c0_d2)          //|< r
  ,.di            (cbuf_wdat_b14c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank14_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b14c1[7:0])        //|< r
  ,.re            (cbuf_re_b14c1)             //|< r
  ,.dout          (cbuf_rdat_b14c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b14c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b14c1_d2)          //|< r
  ,.di            (cbuf_wdat_b14c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank15_column0 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b15c0[7:0])        //|< r
  ,.re            (cbuf_re_b15c0)             //|< r
  ,.dout          (cbuf_rdat_b15c0[511:0])    //|> w
  ,.wa            (cbuf_wa_b15c0_d2[7:0])     //|< r
  ,.we            (cbuf_we_b15c0_d2)          //|< r
  ,.di            (cbuf_wdat_b15c0_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );


nv_ram_rws_256x512 u_cbuf_ram_bank15_column1 (
   .clk           (nvdla_core_clk)            //|< i
  ,.ra            (cbuf_ra_b15c1[7:0])        //|< r
  ,.re            (cbuf_re_b15c1)             //|< r
  ,.dout          (cbuf_rdat_b15c1[511:0])    //|> w
  ,.wa            (cbuf_wa_b15c1_d2[7:0])     //|< r
  ,.we            (cbuf_we_b15c1_d2)          //|< r
  ,.di            (cbuf_wdat_b15c1_d2[511:0]) //|< r
  ,.pwrbus_ram_pd (pwrbus_ram_pd[31:0])       //|< i
  );

////////////////////////////////////////////////////////////////////////
// Input read stage1: rename signals                                  //
////////////////////////////////////////////////////////////////////////
// 三个读客户端（均来自 CSC）：p0=dat、p1=wt 带 12bit 全地址；p2=wmb
// 只有 8bit bank 内地址——它固定读 bank15（下方 p2 的 sel 不做 bank
// 比较，rd_en 即选中 b15 两列）。读是 fire-and-forget：无 ready，
// 发出后恰好 6 拍返回 valid+data

assign cbuf_p0_rd_en    = sc2buf_dat_rd_en;
assign cbuf_p0_rd_addr  = sc2buf_dat_rd_addr[12-1:0];

assign cbuf_p1_rd_en    = sc2buf_wt_rd_en;
assign cbuf_p1_rd_addr  = sc2buf_wt_rd_addr[12-1:0];

assign cbuf_p2_rd_en    = sc2buf_wmb_rd_en;
assign cbuf_p2_rd_addr  = sc2buf_wmb_rd_addr;


////////////////////////////////////////////////////////////////////////
// Input read stage1: misc logic                                      //
////////////////////////////////////////////////////////////////////////
// 读 bank 解码：与写侧同构，但每次读把同 bank 的 c0/c1 两列一起使能
// （同一 sel 条件复制两份），d4 拍再拼成 1024b entry。逐 bank 机械重复
assign cbuf_p0_rd_bank = cbuf_p0_rd_addr[12-1:8];
assign cbuf_p1_rd_bank = cbuf_p1_rd_addr[12-1:8];

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b0c0_w = (cbuf_p0_rd_bank == 4'd0)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b0c1_w = (cbuf_p0_rd_bank == 4'd0)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b1c0_w = (cbuf_p0_rd_bank == 4'd1)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b1c1_w = (cbuf_p0_rd_bank == 4'd1)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b2c0_w = (cbuf_p0_rd_bank == 4'd2)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b2c1_w = (cbuf_p0_rd_bank == 4'd2)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b3c0_w = (cbuf_p0_rd_bank == 4'd3)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b3c1_w = (cbuf_p0_rd_bank == 4'd3)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b4c0_w = (cbuf_p0_rd_bank == 4'd4)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b4c1_w = (cbuf_p0_rd_bank == 4'd4)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b5c0_w = (cbuf_p0_rd_bank == 4'd5)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b5c1_w = (cbuf_p0_rd_bank == 4'd5)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b6c0_w = (cbuf_p0_rd_bank == 4'd6)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b6c1_w = (cbuf_p0_rd_bank == 4'd6)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b7c0_w = (cbuf_p0_rd_bank == 4'd7)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b7c1_w = (cbuf_p0_rd_bank == 4'd7)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b8c0_w = (cbuf_p0_rd_bank == 4'd8)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b8c1_w = (cbuf_p0_rd_bank == 4'd8)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b9c0_w = (cbuf_p0_rd_bank == 4'd9)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b9c1_w = (cbuf_p0_rd_bank == 4'd9)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b10c0_w = (cbuf_p0_rd_bank == 4'd10)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b10c1_w = (cbuf_p0_rd_bank == 4'd10)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b11c0_w = (cbuf_p0_rd_bank == 4'd11)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b11c1_w = (cbuf_p0_rd_bank == 4'd11)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b12c0_w = (cbuf_p0_rd_bank == 4'd12)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b12c1_w = (cbuf_p0_rd_bank == 4'd12)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b13c0_w = (cbuf_p0_rd_bank == 4'd13)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b13c1_w = (cbuf_p0_rd_bank == 4'd13)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b14c0_w = (cbuf_p0_rd_bank == 4'd14)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_bank
  or cbuf_p0_rd_en
  ) begin
    cbuf_p0_rd_sel_ram_b14c1_w = (cbuf_p0_rd_bank == 4'd14)
                                && (cbuf_p0_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b1c0_w = (cbuf_p1_rd_bank == 4'd1)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b1c1_w = (cbuf_p1_rd_bank == 4'd1)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b2c0_w = (cbuf_p1_rd_bank == 4'd2)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b2c1_w = (cbuf_p1_rd_bank == 4'd2)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b3c0_w = (cbuf_p1_rd_bank == 4'd3)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b3c1_w = (cbuf_p1_rd_bank == 4'd3)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b4c0_w = (cbuf_p1_rd_bank == 4'd4)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b4c1_w = (cbuf_p1_rd_bank == 4'd4)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b5c0_w = (cbuf_p1_rd_bank == 4'd5)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b5c1_w = (cbuf_p1_rd_bank == 4'd5)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b6c0_w = (cbuf_p1_rd_bank == 4'd6)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b6c1_w = (cbuf_p1_rd_bank == 4'd6)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b7c0_w = (cbuf_p1_rd_bank == 4'd7)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b7c1_w = (cbuf_p1_rd_bank == 4'd7)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b8c0_w = (cbuf_p1_rd_bank == 4'd8)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b8c1_w = (cbuf_p1_rd_bank == 4'd8)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b9c0_w = (cbuf_p1_rd_bank == 4'd9)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b9c1_w = (cbuf_p1_rd_bank == 4'd9)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b10c0_w = (cbuf_p1_rd_bank == 4'd10)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b10c1_w = (cbuf_p1_rd_bank == 4'd10)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b11c0_w = (cbuf_p1_rd_bank == 4'd11)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b11c1_w = (cbuf_p1_rd_bank == 4'd11)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b12c0_w = (cbuf_p1_rd_bank == 4'd12)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b12c1_w = (cbuf_p1_rd_bank == 4'd12)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b13c0_w = (cbuf_p1_rd_bank == 4'd13)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b13c1_w = (cbuf_p1_rd_bank == 4'd13)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b14c0_w = (cbuf_p1_rd_bank == 4'd14)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b14c1_w = (cbuf_p1_rd_bank == 4'd14)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b15c0_w = (cbuf_p1_rd_bank == 4'd15)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p1_rd_bank
  or cbuf_p1_rd_en
  ) begin
    cbuf_p1_rd_sel_ram_b15c1_w = (cbuf_p1_rd_bank == 4'd15)
                                && (cbuf_p1_rd_en == 1'b1);
end

always @(
  cbuf_p2_rd_en
  ) begin
    cbuf_p2_rd_sel_ram_b15c0_w = (cbuf_p2_rd_en == 1'b1);
end

always @(
  cbuf_p2_rd_en
  ) begin
    cbuf_p2_rd_sel_ram_b15c1_w = (cbuf_p2_rd_en == 1'b1);
end

always @(
  cbuf_p0_rd_sel_ram_b0c0_w
  ) begin
    cbuf_re_b0c0_w = cbuf_p0_rd_sel_ram_b0c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b0c1_w
  ) begin
    cbuf_re_b0c1_w = cbuf_p0_rd_sel_ram_b0c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b1c0_w
  or cbuf_p1_rd_sel_ram_b1c0_w
  ) begin
    cbuf_re_b1c0_w = cbuf_p0_rd_sel_ram_b1c0_w | cbuf_p1_rd_sel_ram_b1c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b1c1_w
  or cbuf_p1_rd_sel_ram_b1c1_w
  ) begin
    cbuf_re_b1c1_w = cbuf_p0_rd_sel_ram_b1c1_w | cbuf_p1_rd_sel_ram_b1c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b2c0_w
  or cbuf_p1_rd_sel_ram_b2c0_w
  ) begin
    cbuf_re_b2c0_w = cbuf_p0_rd_sel_ram_b2c0_w | cbuf_p1_rd_sel_ram_b2c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b2c1_w
  or cbuf_p1_rd_sel_ram_b2c1_w
  ) begin
    cbuf_re_b2c1_w = cbuf_p0_rd_sel_ram_b2c1_w | cbuf_p1_rd_sel_ram_b2c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b3c0_w
  or cbuf_p1_rd_sel_ram_b3c0_w
  ) begin
    cbuf_re_b3c0_w = cbuf_p0_rd_sel_ram_b3c0_w | cbuf_p1_rd_sel_ram_b3c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b3c1_w
  or cbuf_p1_rd_sel_ram_b3c1_w
  ) begin
    cbuf_re_b3c1_w = cbuf_p0_rd_sel_ram_b3c1_w | cbuf_p1_rd_sel_ram_b3c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b4c0_w
  or cbuf_p1_rd_sel_ram_b4c0_w
  ) begin
    cbuf_re_b4c0_w = cbuf_p0_rd_sel_ram_b4c0_w | cbuf_p1_rd_sel_ram_b4c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b4c1_w
  or cbuf_p1_rd_sel_ram_b4c1_w
  ) begin
    cbuf_re_b4c1_w = cbuf_p0_rd_sel_ram_b4c1_w | cbuf_p1_rd_sel_ram_b4c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b5c0_w
  or cbuf_p1_rd_sel_ram_b5c0_w
  ) begin
    cbuf_re_b5c0_w = cbuf_p0_rd_sel_ram_b5c0_w | cbuf_p1_rd_sel_ram_b5c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b5c1_w
  or cbuf_p1_rd_sel_ram_b5c1_w
  ) begin
    cbuf_re_b5c1_w = cbuf_p0_rd_sel_ram_b5c1_w | cbuf_p1_rd_sel_ram_b5c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b6c0_w
  or cbuf_p1_rd_sel_ram_b6c0_w
  ) begin
    cbuf_re_b6c0_w = cbuf_p0_rd_sel_ram_b6c0_w | cbuf_p1_rd_sel_ram_b6c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b6c1_w
  or cbuf_p1_rd_sel_ram_b6c1_w
  ) begin
    cbuf_re_b6c1_w = cbuf_p0_rd_sel_ram_b6c1_w | cbuf_p1_rd_sel_ram_b6c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b7c0_w
  or cbuf_p1_rd_sel_ram_b7c0_w
  ) begin
    cbuf_re_b7c0_w = cbuf_p0_rd_sel_ram_b7c0_w | cbuf_p1_rd_sel_ram_b7c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b7c1_w
  or cbuf_p1_rd_sel_ram_b7c1_w
  ) begin
    cbuf_re_b7c1_w = cbuf_p0_rd_sel_ram_b7c1_w | cbuf_p1_rd_sel_ram_b7c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b8c0_w
  or cbuf_p1_rd_sel_ram_b8c0_w
  ) begin
    cbuf_re_b8c0_w = cbuf_p0_rd_sel_ram_b8c0_w | cbuf_p1_rd_sel_ram_b8c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b8c1_w
  or cbuf_p1_rd_sel_ram_b8c1_w
  ) begin
    cbuf_re_b8c1_w = cbuf_p0_rd_sel_ram_b8c1_w | cbuf_p1_rd_sel_ram_b8c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b9c0_w
  or cbuf_p1_rd_sel_ram_b9c0_w
  ) begin
    cbuf_re_b9c0_w = cbuf_p0_rd_sel_ram_b9c0_w | cbuf_p1_rd_sel_ram_b9c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b9c1_w
  or cbuf_p1_rd_sel_ram_b9c1_w
  ) begin
    cbuf_re_b9c1_w = cbuf_p0_rd_sel_ram_b9c1_w | cbuf_p1_rd_sel_ram_b9c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b10c0_w
  or cbuf_p1_rd_sel_ram_b10c0_w
  ) begin
    cbuf_re_b10c0_w = cbuf_p0_rd_sel_ram_b10c0_w | cbuf_p1_rd_sel_ram_b10c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b10c1_w
  or cbuf_p1_rd_sel_ram_b10c1_w
  ) begin
    cbuf_re_b10c1_w = cbuf_p0_rd_sel_ram_b10c1_w | cbuf_p1_rd_sel_ram_b10c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b11c0_w
  or cbuf_p1_rd_sel_ram_b11c0_w
  ) begin
    cbuf_re_b11c0_w = cbuf_p0_rd_sel_ram_b11c0_w | cbuf_p1_rd_sel_ram_b11c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b11c1_w
  or cbuf_p1_rd_sel_ram_b11c1_w
  ) begin
    cbuf_re_b11c1_w = cbuf_p0_rd_sel_ram_b11c1_w | cbuf_p1_rd_sel_ram_b11c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b12c0_w
  or cbuf_p1_rd_sel_ram_b12c0_w
  ) begin
    cbuf_re_b12c0_w = cbuf_p0_rd_sel_ram_b12c0_w | cbuf_p1_rd_sel_ram_b12c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b12c1_w
  or cbuf_p1_rd_sel_ram_b12c1_w
  ) begin
    cbuf_re_b12c1_w = cbuf_p0_rd_sel_ram_b12c1_w | cbuf_p1_rd_sel_ram_b12c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b13c0_w
  or cbuf_p1_rd_sel_ram_b13c0_w
  ) begin
    cbuf_re_b13c0_w = cbuf_p0_rd_sel_ram_b13c0_w | cbuf_p1_rd_sel_ram_b13c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b13c1_w
  or cbuf_p1_rd_sel_ram_b13c1_w
  ) begin
    cbuf_re_b13c1_w = cbuf_p0_rd_sel_ram_b13c1_w | cbuf_p1_rd_sel_ram_b13c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b14c0_w
  or cbuf_p1_rd_sel_ram_b14c0_w
  ) begin
    cbuf_re_b14c0_w = cbuf_p0_rd_sel_ram_b14c0_w | cbuf_p1_rd_sel_ram_b14c0_w;
end

always @(
  cbuf_p0_rd_sel_ram_b14c1_w
  or cbuf_p1_rd_sel_ram_b14c1_w
  ) begin
    cbuf_re_b14c1_w = cbuf_p0_rd_sel_ram_b14c1_w | cbuf_p1_rd_sel_ram_b14c1_w;
end

always @(
  cbuf_p1_rd_sel_ram_b15c0_w
  or cbuf_p2_rd_sel_ram_b15c0_w
  ) begin
    cbuf_re_b15c0_w = cbuf_p1_rd_sel_ram_b15c0_w | cbuf_p2_rd_sel_ram_b15c0_w;
end

always @(
  cbuf_p1_rd_sel_ram_b15c1_w
  or cbuf_p2_rd_sel_ram_b15c1_w
  ) begin
    cbuf_re_b15c1_w = cbuf_p1_rd_sel_ram_b15c1_w | cbuf_p2_rd_sel_ram_b15c1_w;
end

always @(
  cbuf_p0_rd_sel_ram_b0c0_w
  or cbuf_p0_rd_addr
  ) begin
    cbuf_ra_b0c0_w =  ({8{cbuf_p0_rd_sel_ram_b0c0_w}} & cbuf_p0_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b0c1_w
  or cbuf_p0_rd_addr
  ) begin
    cbuf_ra_b0c1_w =  ({8{cbuf_p0_rd_sel_ram_b0c1_w}} & cbuf_p0_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b1c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b1c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b1c0_w =  ({8{cbuf_p0_rd_sel_ram_b1c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b1c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b1c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b1c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b1c1_w =  ({8{cbuf_p0_rd_sel_ram_b1c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b1c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b2c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b2c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b2c0_w =  ({8{cbuf_p0_rd_sel_ram_b2c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b2c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b2c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b2c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b2c1_w =  ({8{cbuf_p0_rd_sel_ram_b2c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b2c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b3c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b3c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b3c0_w =  ({8{cbuf_p0_rd_sel_ram_b3c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b3c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b3c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b3c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b3c1_w =  ({8{cbuf_p0_rd_sel_ram_b3c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b3c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b4c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b4c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b4c0_w =  ({8{cbuf_p0_rd_sel_ram_b4c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b4c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b4c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b4c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b4c1_w =  ({8{cbuf_p0_rd_sel_ram_b4c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b4c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b5c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b5c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b5c0_w =  ({8{cbuf_p0_rd_sel_ram_b5c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b5c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b5c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b5c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b5c1_w =  ({8{cbuf_p0_rd_sel_ram_b5c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b5c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b6c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b6c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b6c0_w =  ({8{cbuf_p0_rd_sel_ram_b6c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b6c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b6c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b6c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b6c1_w =  ({8{cbuf_p0_rd_sel_ram_b6c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b6c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b7c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b7c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b7c0_w =  ({8{cbuf_p0_rd_sel_ram_b7c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b7c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b7c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b7c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b7c1_w =  ({8{cbuf_p0_rd_sel_ram_b7c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b7c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b8c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b8c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b8c0_w =  ({8{cbuf_p0_rd_sel_ram_b8c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b8c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b8c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b8c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b8c1_w =  ({8{cbuf_p0_rd_sel_ram_b8c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b8c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b9c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b9c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b9c0_w =  ({8{cbuf_p0_rd_sel_ram_b9c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b9c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b9c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b9c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b9c1_w =  ({8{cbuf_p0_rd_sel_ram_b9c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b9c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b10c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b10c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b10c0_w =  ({8{cbuf_p0_rd_sel_ram_b10c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b10c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b10c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b10c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b10c1_w =  ({8{cbuf_p0_rd_sel_ram_b10c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b10c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b11c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b11c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b11c0_w =  ({8{cbuf_p0_rd_sel_ram_b11c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b11c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b11c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b11c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b11c1_w =  ({8{cbuf_p0_rd_sel_ram_b11c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b11c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b12c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b12c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b12c0_w =  ({8{cbuf_p0_rd_sel_ram_b12c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b12c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b12c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b12c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b12c1_w =  ({8{cbuf_p0_rd_sel_ram_b12c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b12c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b13c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b13c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b13c0_w =  ({8{cbuf_p0_rd_sel_ram_b13c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b13c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b13c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b13c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b13c1_w =  ({8{cbuf_p0_rd_sel_ram_b13c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b13c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b14c0_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b14c0_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b14c0_w =  ({8{cbuf_p0_rd_sel_ram_b14c0_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b14c0_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p0_rd_sel_ram_b14c1_w
  or cbuf_p0_rd_addr
  or cbuf_p1_rd_sel_ram_b14c1_w
  or cbuf_p1_rd_addr
  ) begin
    cbuf_ra_b14c1_w =  ({8{cbuf_p0_rd_sel_ram_b14c1_w}} & cbuf_p0_rd_addr[8-1:0]) |
                      ({8{cbuf_p1_rd_sel_ram_b14c1_w}} & cbuf_p1_rd_addr[8-1:0]);
end

always @(
  cbuf_p1_rd_sel_ram_b15c0_w
  or cbuf_p1_rd_addr
  or cbuf_p2_rd_sel_ram_b15c0_w
  or cbuf_p2_rd_addr
  ) begin
    cbuf_ra_b15c0_w =  ({8{cbuf_p1_rd_sel_ram_b15c0_w}} & cbuf_p1_rd_addr[8-1:0]) |
                      ({8{cbuf_p2_rd_sel_ram_b15c0_w}} & cbuf_p2_rd_addr[8-1:0]);
end

always @(
  cbuf_p1_rd_sel_ram_b15c1_w
  or cbuf_p1_rd_addr
  or cbuf_p2_rd_sel_ram_b15c1_w
  or cbuf_p2_rd_addr
  ) begin
    cbuf_ra_b15c1_w =  ({8{cbuf_p1_rd_sel_ram_b15c1_w}} & cbuf_p1_rd_addr[8-1:0]) |
                      ({8{cbuf_p2_rd_sel_ram_b15c1_w}} & cbuf_p2_rd_addr[8-1:0]);
end

////////////////////////////////////////////////////////////////////////
// Input read stage1 registers                                        //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_sel_ram_d1 <= {62{1'b0}};
  end else begin
  cbuf_rd_sel_ram_d1 <= {cbuf_p0_rd_sel_ram_b0c0_w,
                         cbuf_p0_rd_sel_ram_b0c1_w,
                         cbuf_p0_rd_sel_ram_b1c0_w,
                         cbuf_p0_rd_sel_ram_b1c1_w,
                         cbuf_p0_rd_sel_ram_b2c0_w,
                         cbuf_p0_rd_sel_ram_b2c1_w,
                         cbuf_p0_rd_sel_ram_b3c0_w,
                         cbuf_p0_rd_sel_ram_b3c1_w,
                         cbuf_p0_rd_sel_ram_b4c0_w,
                         cbuf_p0_rd_sel_ram_b4c1_w,
                         cbuf_p0_rd_sel_ram_b5c0_w,
                         cbuf_p0_rd_sel_ram_b5c1_w,
                         cbuf_p0_rd_sel_ram_b6c0_w,
                         cbuf_p0_rd_sel_ram_b6c1_w,
                         cbuf_p0_rd_sel_ram_b7c0_w,
                         cbuf_p0_rd_sel_ram_b7c1_w,
                         cbuf_p0_rd_sel_ram_b8c0_w,
                         cbuf_p0_rd_sel_ram_b8c1_w,
                         cbuf_p0_rd_sel_ram_b9c0_w,
                         cbuf_p0_rd_sel_ram_b9c1_w,
                         cbuf_p0_rd_sel_ram_b10c0_w,
                         cbuf_p0_rd_sel_ram_b10c1_w,
                         cbuf_p0_rd_sel_ram_b11c0_w,
                         cbuf_p0_rd_sel_ram_b11c1_w,
                         cbuf_p0_rd_sel_ram_b12c0_w,
                         cbuf_p0_rd_sel_ram_b12c1_w,
                         cbuf_p0_rd_sel_ram_b13c0_w,
                         cbuf_p0_rd_sel_ram_b13c1_w,
                         cbuf_p0_rd_sel_ram_b14c0_w,
                         cbuf_p0_rd_sel_ram_b14c1_w,
                         cbuf_p1_rd_sel_ram_b1c0_w,
                         cbuf_p1_rd_sel_ram_b1c1_w,
                         cbuf_p1_rd_sel_ram_b2c0_w,
                         cbuf_p1_rd_sel_ram_b2c1_w,
                         cbuf_p1_rd_sel_ram_b3c0_w,
                         cbuf_p1_rd_sel_ram_b3c1_w,
                         cbuf_p1_rd_sel_ram_b4c0_w,
                         cbuf_p1_rd_sel_ram_b4c1_w,
                         cbuf_p1_rd_sel_ram_b5c0_w,
                         cbuf_p1_rd_sel_ram_b5c1_w,
                         cbuf_p1_rd_sel_ram_b6c0_w,
                         cbuf_p1_rd_sel_ram_b6c1_w,
                         cbuf_p1_rd_sel_ram_b7c0_w,
                         cbuf_p1_rd_sel_ram_b7c1_w,
                         cbuf_p1_rd_sel_ram_b8c0_w,
                         cbuf_p1_rd_sel_ram_b8c1_w,
                         cbuf_p1_rd_sel_ram_b9c0_w,
                         cbuf_p1_rd_sel_ram_b9c1_w,
                         cbuf_p1_rd_sel_ram_b10c0_w,
                         cbuf_p1_rd_sel_ram_b10c1_w,
                         cbuf_p1_rd_sel_ram_b11c0_w,
                         cbuf_p1_rd_sel_ram_b11c1_w,
                         cbuf_p1_rd_sel_ram_b12c0_w,
                         cbuf_p1_rd_sel_ram_b12c1_w,
                         cbuf_p1_rd_sel_ram_b13c0_w,
                         cbuf_p1_rd_sel_ram_b13c1_w,
                         cbuf_p1_rd_sel_ram_b14c0_w,
                         cbuf_p1_rd_sel_ram_b14c1_w,
                         cbuf_p1_rd_sel_ram_b15c0_w,
                         cbuf_p1_rd_sel_ram_b15c1_w,
                         cbuf_p2_rd_sel_ram_b15c0_w,
                         cbuf_p2_rd_sel_ram_b15c1_w};
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_en_d1 <= {3{1'b0}};
  end else begin
  cbuf_rd_en_d1 <= {cbuf_p0_rd_en,
                    cbuf_p1_rd_en,
                    cbuf_p2_rd_en};
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b0c0 <= 1'b0;
  end else begin
  cbuf_re_b0c0 <= cbuf_re_b0c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b0c1 <= 1'b0;
  end else begin
  cbuf_re_b0c1 <= cbuf_re_b0c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b1c0 <= 1'b0;
  end else begin
  cbuf_re_b1c0 <= cbuf_re_b1c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b1c1 <= 1'b0;
  end else begin
  cbuf_re_b1c1 <= cbuf_re_b1c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b2c0 <= 1'b0;
  end else begin
  cbuf_re_b2c0 <= cbuf_re_b2c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b2c1 <= 1'b0;
  end else begin
  cbuf_re_b2c1 <= cbuf_re_b2c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b3c0 <= 1'b0;
  end else begin
  cbuf_re_b3c0 <= cbuf_re_b3c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b3c1 <= 1'b0;
  end else begin
  cbuf_re_b3c1 <= cbuf_re_b3c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b4c0 <= 1'b0;
  end else begin
  cbuf_re_b4c0 <= cbuf_re_b4c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b4c1 <= 1'b0;
  end else begin
  cbuf_re_b4c1 <= cbuf_re_b4c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b5c0 <= 1'b0;
  end else begin
  cbuf_re_b5c0 <= cbuf_re_b5c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b5c1 <= 1'b0;
  end else begin
  cbuf_re_b5c1 <= cbuf_re_b5c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b6c0 <= 1'b0;
  end else begin
  cbuf_re_b6c0 <= cbuf_re_b6c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b6c1 <= 1'b0;
  end else begin
  cbuf_re_b6c1 <= cbuf_re_b6c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b7c0 <= 1'b0;
  end else begin
  cbuf_re_b7c0 <= cbuf_re_b7c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b7c1 <= 1'b0;
  end else begin
  cbuf_re_b7c1 <= cbuf_re_b7c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b8c0 <= 1'b0;
  end else begin
  cbuf_re_b8c0 <= cbuf_re_b8c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b8c1 <= 1'b0;
  end else begin
  cbuf_re_b8c1 <= cbuf_re_b8c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b9c0 <= 1'b0;
  end else begin
  cbuf_re_b9c0 <= cbuf_re_b9c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b9c1 <= 1'b0;
  end else begin
  cbuf_re_b9c1 <= cbuf_re_b9c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b10c0 <= 1'b0;
  end else begin
  cbuf_re_b10c0 <= cbuf_re_b10c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b10c1 <= 1'b0;
  end else begin
  cbuf_re_b10c1 <= cbuf_re_b10c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b11c0 <= 1'b0;
  end else begin
  cbuf_re_b11c0 <= cbuf_re_b11c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b11c1 <= 1'b0;
  end else begin
  cbuf_re_b11c1 <= cbuf_re_b11c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b12c0 <= 1'b0;
  end else begin
  cbuf_re_b12c0 <= cbuf_re_b12c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b12c1 <= 1'b0;
  end else begin
  cbuf_re_b12c1 <= cbuf_re_b12c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b13c0 <= 1'b0;
  end else begin
  cbuf_re_b13c0 <= cbuf_re_b13c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b13c1 <= 1'b0;
  end else begin
  cbuf_re_b13c1 <= cbuf_re_b13c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b14c0 <= 1'b0;
  end else begin
  cbuf_re_b14c0 <= cbuf_re_b14c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b14c1 <= 1'b0;
  end else begin
  cbuf_re_b14c1 <= cbuf_re_b14c1_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b15c0 <= 1'b0;
  end else begin
  cbuf_re_b15c0 <= cbuf_re_b15c0_w;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b15c1 <= 1'b0;
  end else begin
  cbuf_re_b15c1 <= cbuf_re_b15c1_w;
  end
end

always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b0c0_w) == 1'b1) begin
    cbuf_ra_b0c0 <= cbuf_ra_b0c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b0c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b0c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b0c1_w) == 1'b1) begin
    cbuf_ra_b0c1 <= cbuf_ra_b0c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b0c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b0c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b1c0_w) == 1'b1) begin
    cbuf_ra_b1c0 <= cbuf_ra_b1c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b1c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b1c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b1c1_w) == 1'b1) begin
    cbuf_ra_b1c1 <= cbuf_ra_b1c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b1c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b1c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b2c0_w) == 1'b1) begin
    cbuf_ra_b2c0 <= cbuf_ra_b2c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b2c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b2c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b2c1_w) == 1'b1) begin
    cbuf_ra_b2c1 <= cbuf_ra_b2c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b2c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b2c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b3c0_w) == 1'b1) begin
    cbuf_ra_b3c0 <= cbuf_ra_b3c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b3c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b3c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b3c1_w) == 1'b1) begin
    cbuf_ra_b3c1 <= cbuf_ra_b3c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b3c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b3c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b4c0_w) == 1'b1) begin
    cbuf_ra_b4c0 <= cbuf_ra_b4c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b4c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b4c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b4c1_w) == 1'b1) begin
    cbuf_ra_b4c1 <= cbuf_ra_b4c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b4c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b4c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b5c0_w) == 1'b1) begin
    cbuf_ra_b5c0 <= cbuf_ra_b5c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b5c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b5c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b5c1_w) == 1'b1) begin
    cbuf_ra_b5c1 <= cbuf_ra_b5c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b5c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b5c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b6c0_w) == 1'b1) begin
    cbuf_ra_b6c0 <= cbuf_ra_b6c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b6c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b6c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b6c1_w) == 1'b1) begin
    cbuf_ra_b6c1 <= cbuf_ra_b6c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b6c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b6c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b7c0_w) == 1'b1) begin
    cbuf_ra_b7c0 <= cbuf_ra_b7c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b7c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b7c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b7c1_w) == 1'b1) begin
    cbuf_ra_b7c1 <= cbuf_ra_b7c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b7c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b7c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b8c0_w) == 1'b1) begin
    cbuf_ra_b8c0 <= cbuf_ra_b8c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b8c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b8c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b8c1_w) == 1'b1) begin
    cbuf_ra_b8c1 <= cbuf_ra_b8c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b8c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b8c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b9c0_w) == 1'b1) begin
    cbuf_ra_b9c0 <= cbuf_ra_b9c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b9c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b9c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b9c1_w) == 1'b1) begin
    cbuf_ra_b9c1 <= cbuf_ra_b9c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b9c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b9c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b10c0_w) == 1'b1) begin
    cbuf_ra_b10c0 <= cbuf_ra_b10c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b10c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b10c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b10c1_w) == 1'b1) begin
    cbuf_ra_b10c1 <= cbuf_ra_b10c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b10c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b10c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b11c0_w) == 1'b1) begin
    cbuf_ra_b11c0 <= cbuf_ra_b11c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b11c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b11c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b11c1_w) == 1'b1) begin
    cbuf_ra_b11c1 <= cbuf_ra_b11c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b11c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b11c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b12c0_w) == 1'b1) begin
    cbuf_ra_b12c0 <= cbuf_ra_b12c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b12c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b12c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b12c1_w) == 1'b1) begin
    cbuf_ra_b12c1 <= cbuf_ra_b12c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b12c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b12c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b13c0_w) == 1'b1) begin
    cbuf_ra_b13c0 <= cbuf_ra_b13c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b13c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b13c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b13c1_w) == 1'b1) begin
    cbuf_ra_b13c1 <= cbuf_ra_b13c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b13c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b13c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b14c0_w) == 1'b1) begin
    cbuf_ra_b14c0 <= cbuf_ra_b14c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b14c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b14c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b14c1_w) == 1'b1) begin
    cbuf_ra_b14c1 <= cbuf_ra_b14c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b14c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b14c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b15c0_w) == 1'b1) begin
    cbuf_ra_b15c0 <= cbuf_ra_b15c0_w;
  // VCS coverage off
  end else if ((cbuf_re_b15c0_w) == 1'b0) begin
  end else begin
    cbuf_ra_b15c0 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b15c1_w) == 1'b1) begin
    cbuf_ra_b15c1 <= cbuf_ra_b15c1_w;
  // VCS coverage off
  end else if ((cbuf_re_b15c1_w) == 1'b0) begin
  end else begin
    cbuf_ra_b15c1 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end

////////////////////////////////////////////////////////////////////////
// Input read stage2: read connection to RAM                          //
////////////////////////////////////////////////////////////////////////





////////////////////////////////////////////////////////////////////////
// Input read stage2 registers                                        //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_sel_ram_d2 <= {62{1'b0}};
  end else begin
  cbuf_rd_sel_ram_d2 <= cbuf_rd_sel_ram_d1;
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_en_d2 <= {3{1'b0}};
  end else begin
  cbuf_rd_en_d2 <= cbuf_rd_en_d1;
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b0c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b0c0_d2 <= cbuf_re_b0c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b0c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b0c1_d2 <= cbuf_re_b0c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b1c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b1c0_d2 <= cbuf_re_b1c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b1c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b1c1_d2 <= cbuf_re_b1c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b2c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b2c0_d2 <= cbuf_re_b2c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b2c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b2c1_d2 <= cbuf_re_b2c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b3c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b3c0_d2 <= cbuf_re_b3c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b3c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b3c1_d2 <= cbuf_re_b3c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b4c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b4c0_d2 <= cbuf_re_b4c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b4c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b4c1_d2 <= cbuf_re_b4c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b5c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b5c0_d2 <= cbuf_re_b5c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b5c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b5c1_d2 <= cbuf_re_b5c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b6c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b6c0_d2 <= cbuf_re_b6c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b6c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b6c1_d2 <= cbuf_re_b6c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b7c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b7c0_d2 <= cbuf_re_b7c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b7c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b7c1_d2 <= cbuf_re_b7c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b8c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b8c0_d2 <= cbuf_re_b8c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b8c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b8c1_d2 <= cbuf_re_b8c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b9c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b9c0_d2 <= cbuf_re_b9c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b9c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b9c1_d2 <= cbuf_re_b9c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b10c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b10c0_d2 <= cbuf_re_b10c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b10c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b10c1_d2 <= cbuf_re_b10c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b11c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b11c0_d2 <= cbuf_re_b11c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b11c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b11c1_d2 <= cbuf_re_b11c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b12c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b12c0_d2 <= cbuf_re_b12c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b12c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b12c1_d2 <= cbuf_re_b12c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b13c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b13c0_d2 <= cbuf_re_b13c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b13c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b13c1_d2 <= cbuf_re_b13c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b14c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b14c0_d2 <= cbuf_re_b14c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b14c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b14c1_d2 <= cbuf_re_b14c1;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b15c0_d2 <= 1'b0;
  end else begin
  cbuf_re_b15c0_d2 <= cbuf_re_b15c0;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_re_b15c1_d2 <= 1'b0;
  end else begin
  cbuf_re_b15c1_d2 <= cbuf_re_b15c1;
  end
end



////////////////////////////////////////////////////////////////////////
// Input read stage3 retiming registers                               //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_sel_ram_d3 <= {62{1'b0}};
  end else begin
  cbuf_rd_sel_ram_d3 <= cbuf_rd_sel_ram_d2;
  end
end

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_en_d3 <= {3{1'b0}};
  end else begin
  cbuf_rd_en_d3 <= cbuf_rd_en_d2;
  end
end

always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b0c0_d2) == 1'b1) begin
    cbuf_rdat_b0c0_d3 <= cbuf_rdat_b0c0;
  // VCS coverage off
  end else if ((cbuf_re_b0c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b0c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b0c1_d2) == 1'b1) begin
    cbuf_rdat_b0c1_d3 <= cbuf_rdat_b0c1;
  // VCS coverage off
  end else if ((cbuf_re_b0c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b0c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b1c0_d2) == 1'b1) begin
    cbuf_rdat_b1c0_d3 <= cbuf_rdat_b1c0;
  // VCS coverage off
  end else if ((cbuf_re_b1c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b1c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b1c1_d2) == 1'b1) begin
    cbuf_rdat_b1c1_d3 <= cbuf_rdat_b1c1;
  // VCS coverage off
  end else if ((cbuf_re_b1c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b1c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b2c0_d2) == 1'b1) begin
    cbuf_rdat_b2c0_d3 <= cbuf_rdat_b2c0;
  // VCS coverage off
  end else if ((cbuf_re_b2c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b2c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b2c1_d2) == 1'b1) begin
    cbuf_rdat_b2c1_d3 <= cbuf_rdat_b2c1;
  // VCS coverage off
  end else if ((cbuf_re_b2c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b2c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b3c0_d2) == 1'b1) begin
    cbuf_rdat_b3c0_d3 <= cbuf_rdat_b3c0;
  // VCS coverage off
  end else if ((cbuf_re_b3c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b3c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b3c1_d2) == 1'b1) begin
    cbuf_rdat_b3c1_d3 <= cbuf_rdat_b3c1;
  // VCS coverage off
  end else if ((cbuf_re_b3c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b3c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b4c0_d2) == 1'b1) begin
    cbuf_rdat_b4c0_d3 <= cbuf_rdat_b4c0;
  // VCS coverage off
  end else if ((cbuf_re_b4c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b4c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b4c1_d2) == 1'b1) begin
    cbuf_rdat_b4c1_d3 <= cbuf_rdat_b4c1;
  // VCS coverage off
  end else if ((cbuf_re_b4c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b4c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b5c0_d2) == 1'b1) begin
    cbuf_rdat_b5c0_d3 <= cbuf_rdat_b5c0;
  // VCS coverage off
  end else if ((cbuf_re_b5c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b5c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b5c1_d2) == 1'b1) begin
    cbuf_rdat_b5c1_d3 <= cbuf_rdat_b5c1;
  // VCS coverage off
  end else if ((cbuf_re_b5c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b5c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b6c0_d2) == 1'b1) begin
    cbuf_rdat_b6c0_d3 <= cbuf_rdat_b6c0;
  // VCS coverage off
  end else if ((cbuf_re_b6c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b6c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b6c1_d2) == 1'b1) begin
    cbuf_rdat_b6c1_d3 <= cbuf_rdat_b6c1;
  // VCS coverage off
  end else if ((cbuf_re_b6c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b6c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b7c0_d2) == 1'b1) begin
    cbuf_rdat_b7c0_d3 <= cbuf_rdat_b7c0;
  // VCS coverage off
  end else if ((cbuf_re_b7c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b7c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b7c1_d2) == 1'b1) begin
    cbuf_rdat_b7c1_d3 <= cbuf_rdat_b7c1;
  // VCS coverage off
  end else if ((cbuf_re_b7c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b7c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b8c0_d2) == 1'b1) begin
    cbuf_rdat_b8c0_d3 <= cbuf_rdat_b8c0;
  // VCS coverage off
  end else if ((cbuf_re_b8c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b8c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b8c1_d2) == 1'b1) begin
    cbuf_rdat_b8c1_d3 <= cbuf_rdat_b8c1;
  // VCS coverage off
  end else if ((cbuf_re_b8c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b8c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b9c0_d2) == 1'b1) begin
    cbuf_rdat_b9c0_d3 <= cbuf_rdat_b9c0;
  // VCS coverage off
  end else if ((cbuf_re_b9c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b9c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b9c1_d2) == 1'b1) begin
    cbuf_rdat_b9c1_d3 <= cbuf_rdat_b9c1;
  // VCS coverage off
  end else if ((cbuf_re_b9c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b9c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b10c0_d2) == 1'b1) begin
    cbuf_rdat_b10c0_d3 <= cbuf_rdat_b10c0;
  // VCS coverage off
  end else if ((cbuf_re_b10c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b10c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b10c1_d2) == 1'b1) begin
    cbuf_rdat_b10c1_d3 <= cbuf_rdat_b10c1;
  // VCS coverage off
  end else if ((cbuf_re_b10c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b10c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b11c0_d2) == 1'b1) begin
    cbuf_rdat_b11c0_d3 <= cbuf_rdat_b11c0;
  // VCS coverage off
  end else if ((cbuf_re_b11c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b11c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b11c1_d2) == 1'b1) begin
    cbuf_rdat_b11c1_d3 <= cbuf_rdat_b11c1;
  // VCS coverage off
  end else if ((cbuf_re_b11c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b11c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b12c0_d2) == 1'b1) begin
    cbuf_rdat_b12c0_d3 <= cbuf_rdat_b12c0;
  // VCS coverage off
  end else if ((cbuf_re_b12c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b12c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b12c1_d2) == 1'b1) begin
    cbuf_rdat_b12c1_d3 <= cbuf_rdat_b12c1;
  // VCS coverage off
  end else if ((cbuf_re_b12c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b12c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b13c0_d2) == 1'b1) begin
    cbuf_rdat_b13c0_d3 <= cbuf_rdat_b13c0;
  // VCS coverage off
  end else if ((cbuf_re_b13c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b13c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b13c1_d2) == 1'b1) begin
    cbuf_rdat_b13c1_d3 <= cbuf_rdat_b13c1;
  // VCS coverage off
  end else if ((cbuf_re_b13c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b13c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b14c0_d2) == 1'b1) begin
    cbuf_rdat_b14c0_d3 <= cbuf_rdat_b14c0;
  // VCS coverage off
  end else if ((cbuf_re_b14c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b14c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b14c1_d2) == 1'b1) begin
    cbuf_rdat_b14c1_d3 <= cbuf_rdat_b14c1;
  // VCS coverage off
  end else if ((cbuf_re_b14c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b14c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b15c0_d2) == 1'b1) begin
    cbuf_rdat_b15c0_d3 <= cbuf_rdat_b15c0;
  // VCS coverage off
  end else if ((cbuf_re_b15c0_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b15c0_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_re_b15c1_d2) == 1'b1) begin
    cbuf_rdat_b15c1_d3 <= cbuf_rdat_b15c1;
  // VCS coverage off
  end else if ((cbuf_re_b15c1_d2) == 1'b0) begin
  end else begin
    cbuf_rdat_b15c1_d3 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end



////////////////////////////////////////////////////////////////////////
// Input read stage4: select output data                              //
////////////////////////////////////////////////////////////////////////
// RAM dout 已在 d3 拍寄存；此处按 sel_d3（读发起时的 bank one-hot，随
// 流水同步延迟到 d3）从 32 路 dout 中掩码选出本口数据，c0/c1 各 512b
assign {cbuf_p0_rd_sel_ram_b0c0_d3,
        cbuf_p0_rd_sel_ram_b0c1_d3,
        cbuf_p0_rd_sel_ram_b1c0_d3,
        cbuf_p0_rd_sel_ram_b1c1_d3,
        cbuf_p0_rd_sel_ram_b2c0_d3,
        cbuf_p0_rd_sel_ram_b2c1_d3,
        cbuf_p0_rd_sel_ram_b3c0_d3,
        cbuf_p0_rd_sel_ram_b3c1_d3,
        cbuf_p0_rd_sel_ram_b4c0_d3,
        cbuf_p0_rd_sel_ram_b4c1_d3,
        cbuf_p0_rd_sel_ram_b5c0_d3,
        cbuf_p0_rd_sel_ram_b5c1_d3,
        cbuf_p0_rd_sel_ram_b6c0_d3,
        cbuf_p0_rd_sel_ram_b6c1_d3,
        cbuf_p0_rd_sel_ram_b7c0_d3,
        cbuf_p0_rd_sel_ram_b7c1_d3,
        cbuf_p0_rd_sel_ram_b8c0_d3,
        cbuf_p0_rd_sel_ram_b8c1_d3,
        cbuf_p0_rd_sel_ram_b9c0_d3,
        cbuf_p0_rd_sel_ram_b9c1_d3,
        cbuf_p0_rd_sel_ram_b10c0_d3,
        cbuf_p0_rd_sel_ram_b10c1_d3,
        cbuf_p0_rd_sel_ram_b11c0_d3,
        cbuf_p0_rd_sel_ram_b11c1_d3,
        cbuf_p0_rd_sel_ram_b12c0_d3,
        cbuf_p0_rd_sel_ram_b12c1_d3,
        cbuf_p0_rd_sel_ram_b13c0_d3,
        cbuf_p0_rd_sel_ram_b13c1_d3,
        cbuf_p0_rd_sel_ram_b14c0_d3,
        cbuf_p0_rd_sel_ram_b14c1_d3,
        cbuf_p1_rd_sel_ram_b1c0_d3,
        cbuf_p1_rd_sel_ram_b1c1_d3,
        cbuf_p1_rd_sel_ram_b2c0_d3,
        cbuf_p1_rd_sel_ram_b2c1_d3,
        cbuf_p1_rd_sel_ram_b3c0_d3,
        cbuf_p1_rd_sel_ram_b3c1_d3,
        cbuf_p1_rd_sel_ram_b4c0_d3,
        cbuf_p1_rd_sel_ram_b4c1_d3,
        cbuf_p1_rd_sel_ram_b5c0_d3,
        cbuf_p1_rd_sel_ram_b5c1_d3,
        cbuf_p1_rd_sel_ram_b6c0_d3,
        cbuf_p1_rd_sel_ram_b6c1_d3,
        cbuf_p1_rd_sel_ram_b7c0_d3,
        cbuf_p1_rd_sel_ram_b7c1_d3,
        cbuf_p1_rd_sel_ram_b8c0_d3,
        cbuf_p1_rd_sel_ram_b8c1_d3,
        cbuf_p1_rd_sel_ram_b9c0_d3,
        cbuf_p1_rd_sel_ram_b9c1_d3,
        cbuf_p1_rd_sel_ram_b10c0_d3,
        cbuf_p1_rd_sel_ram_b10c1_d3,
        cbuf_p1_rd_sel_ram_b11c0_d3,
        cbuf_p1_rd_sel_ram_b11c1_d3,
        cbuf_p1_rd_sel_ram_b12c0_d3,
        cbuf_p1_rd_sel_ram_b12c1_d3,
        cbuf_p1_rd_sel_ram_b13c0_d3,
        cbuf_p1_rd_sel_ram_b13c1_d3,
        cbuf_p1_rd_sel_ram_b14c0_d3,
        cbuf_p1_rd_sel_ram_b14c1_d3,
        cbuf_p1_rd_sel_ram_b15c0_d3,
        cbuf_p1_rd_sel_ram_b15c1_d3,
        cbuf_p2_rd_sel_ram_b15c0_d3,
        cbuf_p2_rd_sel_ram_b15c1_d3} = cbuf_rd_sel_ram_d3;

assign {cbuf_p0_rd_en_d3,
        cbuf_p1_rd_en_d3,
        cbuf_p2_rd_en_d3} = cbuf_rd_en_d3;

always @(
  cbuf_p0_rd_sel_ram_b0c0_d3
  or cbuf_p0_rd_sel_ram_b0c1_d3
  or cbuf_rdat_b0c0_d3
  or cbuf_rdat_b0c1_d3
  or cbuf_p0_rd_sel_ram_b1c0_d3
  or cbuf_p0_rd_sel_ram_b1c1_d3
  or cbuf_rdat_b1c0_d3
  or cbuf_rdat_b1c1_d3
  or cbuf_p0_rd_sel_ram_b2c0_d3
  or cbuf_p0_rd_sel_ram_b2c1_d3
  or cbuf_rdat_b2c0_d3
  or cbuf_rdat_b2c1_d3
  or cbuf_p0_rd_sel_ram_b3c0_d3
  or cbuf_p0_rd_sel_ram_b3c1_d3
  or cbuf_rdat_b3c0_d3
  or cbuf_rdat_b3c1_d3
  or cbuf_p0_rd_sel_ram_b4c0_d3
  or cbuf_p0_rd_sel_ram_b4c1_d3
  or cbuf_rdat_b4c0_d3
  or cbuf_rdat_b4c1_d3
  or cbuf_p0_rd_sel_ram_b5c0_d3
  or cbuf_p0_rd_sel_ram_b5c1_d3
  or cbuf_rdat_b5c0_d3
  or cbuf_rdat_b5c1_d3
  or cbuf_p0_rd_sel_ram_b6c0_d3
  or cbuf_p0_rd_sel_ram_b6c1_d3
  or cbuf_rdat_b6c0_d3
  or cbuf_rdat_b6c1_d3
  or cbuf_p0_rd_sel_ram_b7c0_d3
  or cbuf_p0_rd_sel_ram_b7c1_d3
  or cbuf_rdat_b7c0_d3
  or cbuf_rdat_b7c1_d3
  or cbuf_p0_rd_sel_ram_b8c0_d3
  or cbuf_p0_rd_sel_ram_b8c1_d3
  or cbuf_rdat_b8c0_d3
  or cbuf_rdat_b8c1_d3
  or cbuf_p0_rd_sel_ram_b9c0_d3
  or cbuf_p0_rd_sel_ram_b9c1_d3
  or cbuf_rdat_b9c0_d3
  or cbuf_rdat_b9c1_d3
  or cbuf_p0_rd_sel_ram_b10c0_d3
  or cbuf_p0_rd_sel_ram_b10c1_d3
  or cbuf_rdat_b10c0_d3
  or cbuf_rdat_b10c1_d3
  or cbuf_p0_rd_sel_ram_b11c0_d3
  or cbuf_p0_rd_sel_ram_b11c1_d3
  or cbuf_rdat_b11c0_d3
  or cbuf_rdat_b11c1_d3
  or cbuf_p0_rd_sel_ram_b12c0_d3
  or cbuf_p0_rd_sel_ram_b12c1_d3
  or cbuf_rdat_b12c0_d3
  or cbuf_rdat_b12c1_d3
  or cbuf_p0_rd_sel_ram_b13c0_d3
  or cbuf_p0_rd_sel_ram_b13c1_d3
  or cbuf_rdat_b13c0_d3
  or cbuf_rdat_b13c1_d3
  or cbuf_p0_rd_sel_ram_b14c0_d3
  or cbuf_p0_rd_sel_ram_b14c1_d3
  or cbuf_rdat_b14c0_d3
  or cbuf_rdat_b14c1_d3
  ) begin
    cbuf_p0_rd_data_d4_w = ({{512{cbuf_p0_rd_sel_ram_b0c0_d3}}, {512{cbuf_p0_rd_sel_ram_b0c1_d3}}} & {cbuf_rdat_b0c0_d3, cbuf_rdat_b0c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b1c0_d3}}, {512{cbuf_p0_rd_sel_ram_b1c1_d3}}} & {cbuf_rdat_b1c0_d3, cbuf_rdat_b1c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b2c0_d3}}, {512{cbuf_p0_rd_sel_ram_b2c1_d3}}} & {cbuf_rdat_b2c0_d3, cbuf_rdat_b2c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b3c0_d3}}, {512{cbuf_p0_rd_sel_ram_b3c1_d3}}} & {cbuf_rdat_b3c0_d3, cbuf_rdat_b3c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b4c0_d3}}, {512{cbuf_p0_rd_sel_ram_b4c1_d3}}} & {cbuf_rdat_b4c0_d3, cbuf_rdat_b4c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b5c0_d3}}, {512{cbuf_p0_rd_sel_ram_b5c1_d3}}} & {cbuf_rdat_b5c0_d3, cbuf_rdat_b5c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b6c0_d3}}, {512{cbuf_p0_rd_sel_ram_b6c1_d3}}} & {cbuf_rdat_b6c0_d3, cbuf_rdat_b6c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b7c0_d3}}, {512{cbuf_p0_rd_sel_ram_b7c1_d3}}} & {cbuf_rdat_b7c0_d3, cbuf_rdat_b7c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b8c0_d3}}, {512{cbuf_p0_rd_sel_ram_b8c1_d3}}} & {cbuf_rdat_b8c0_d3, cbuf_rdat_b8c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b9c0_d3}}, {512{cbuf_p0_rd_sel_ram_b9c1_d3}}} & {cbuf_rdat_b9c0_d3, cbuf_rdat_b9c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b10c0_d3}}, {512{cbuf_p0_rd_sel_ram_b10c1_d3}}} & {cbuf_rdat_b10c0_d3, cbuf_rdat_b10c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b11c0_d3}}, {512{cbuf_p0_rd_sel_ram_b11c1_d3}}} & {cbuf_rdat_b11c0_d3, cbuf_rdat_b11c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b12c0_d3}}, {512{cbuf_p0_rd_sel_ram_b12c1_d3}}} & {cbuf_rdat_b12c0_d3, cbuf_rdat_b12c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b13c0_d3}}, {512{cbuf_p0_rd_sel_ram_b13c1_d3}}} & {cbuf_rdat_b13c0_d3, cbuf_rdat_b13c1_d3}) |
                               ({{512{cbuf_p0_rd_sel_ram_b14c0_d3}}, {512{cbuf_p0_rd_sel_ram_b14c1_d3}}} & {cbuf_rdat_b14c0_d3, cbuf_rdat_b14c1_d3});
end

always @(
  cbuf_p1_rd_sel_ram_b1c0_d3
  or cbuf_p1_rd_sel_ram_b1c1_d3
  or cbuf_rdat_b1c0_d3
  or cbuf_rdat_b1c1_d3
  or cbuf_p1_rd_sel_ram_b2c0_d3
  or cbuf_p1_rd_sel_ram_b2c1_d3
  or cbuf_rdat_b2c0_d3
  or cbuf_rdat_b2c1_d3
  or cbuf_p1_rd_sel_ram_b3c0_d3
  or cbuf_p1_rd_sel_ram_b3c1_d3
  or cbuf_rdat_b3c0_d3
  or cbuf_rdat_b3c1_d3
  or cbuf_p1_rd_sel_ram_b4c0_d3
  or cbuf_p1_rd_sel_ram_b4c1_d3
  or cbuf_rdat_b4c0_d3
  or cbuf_rdat_b4c1_d3
  or cbuf_p1_rd_sel_ram_b5c0_d3
  or cbuf_p1_rd_sel_ram_b5c1_d3
  or cbuf_rdat_b5c0_d3
  or cbuf_rdat_b5c1_d3
  or cbuf_p1_rd_sel_ram_b6c0_d3
  or cbuf_p1_rd_sel_ram_b6c1_d3
  or cbuf_rdat_b6c0_d3
  or cbuf_rdat_b6c1_d3
  or cbuf_p1_rd_sel_ram_b7c0_d3
  or cbuf_p1_rd_sel_ram_b7c1_d3
  or cbuf_rdat_b7c0_d3
  or cbuf_rdat_b7c1_d3
  or cbuf_p1_rd_sel_ram_b8c0_d3
  or cbuf_p1_rd_sel_ram_b8c1_d3
  or cbuf_rdat_b8c0_d3
  or cbuf_rdat_b8c1_d3
  or cbuf_p1_rd_sel_ram_b9c0_d3
  or cbuf_p1_rd_sel_ram_b9c1_d3
  or cbuf_rdat_b9c0_d3
  or cbuf_rdat_b9c1_d3
  or cbuf_p1_rd_sel_ram_b10c0_d3
  or cbuf_p1_rd_sel_ram_b10c1_d3
  or cbuf_rdat_b10c0_d3
  or cbuf_rdat_b10c1_d3
  or cbuf_p1_rd_sel_ram_b11c0_d3
  or cbuf_p1_rd_sel_ram_b11c1_d3
  or cbuf_rdat_b11c0_d3
  or cbuf_rdat_b11c1_d3
  or cbuf_p1_rd_sel_ram_b12c0_d3
  or cbuf_p1_rd_sel_ram_b12c1_d3
  or cbuf_rdat_b12c0_d3
  or cbuf_rdat_b12c1_d3
  or cbuf_p1_rd_sel_ram_b13c0_d3
  or cbuf_p1_rd_sel_ram_b13c1_d3
  or cbuf_rdat_b13c0_d3
  or cbuf_rdat_b13c1_d3
  or cbuf_p1_rd_sel_ram_b14c0_d3
  or cbuf_p1_rd_sel_ram_b14c1_d3
  or cbuf_rdat_b14c0_d3
  or cbuf_rdat_b14c1_d3
  or cbuf_p1_rd_sel_ram_b15c0_d3
  or cbuf_p1_rd_sel_ram_b15c1_d3
  or cbuf_rdat_b15c0_d3
  or cbuf_rdat_b15c1_d3
  ) begin
    cbuf_p1_rd_data_d4_w = ({{512{cbuf_p1_rd_sel_ram_b1c0_d3}}, {512{cbuf_p1_rd_sel_ram_b1c1_d3}}} & {cbuf_rdat_b1c0_d3, cbuf_rdat_b1c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b2c0_d3}}, {512{cbuf_p1_rd_sel_ram_b2c1_d3}}} & {cbuf_rdat_b2c0_d3, cbuf_rdat_b2c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b3c0_d3}}, {512{cbuf_p1_rd_sel_ram_b3c1_d3}}} & {cbuf_rdat_b3c0_d3, cbuf_rdat_b3c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b4c0_d3}}, {512{cbuf_p1_rd_sel_ram_b4c1_d3}}} & {cbuf_rdat_b4c0_d3, cbuf_rdat_b4c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b5c0_d3}}, {512{cbuf_p1_rd_sel_ram_b5c1_d3}}} & {cbuf_rdat_b5c0_d3, cbuf_rdat_b5c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b6c0_d3}}, {512{cbuf_p1_rd_sel_ram_b6c1_d3}}} & {cbuf_rdat_b6c0_d3, cbuf_rdat_b6c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b7c0_d3}}, {512{cbuf_p1_rd_sel_ram_b7c1_d3}}} & {cbuf_rdat_b7c0_d3, cbuf_rdat_b7c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b8c0_d3}}, {512{cbuf_p1_rd_sel_ram_b8c1_d3}}} & {cbuf_rdat_b8c0_d3, cbuf_rdat_b8c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b9c0_d3}}, {512{cbuf_p1_rd_sel_ram_b9c1_d3}}} & {cbuf_rdat_b9c0_d3, cbuf_rdat_b9c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b10c0_d3}}, {512{cbuf_p1_rd_sel_ram_b10c1_d3}}} & {cbuf_rdat_b10c0_d3, cbuf_rdat_b10c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b11c0_d3}}, {512{cbuf_p1_rd_sel_ram_b11c1_d3}}} & {cbuf_rdat_b11c0_d3, cbuf_rdat_b11c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b12c0_d3}}, {512{cbuf_p1_rd_sel_ram_b12c1_d3}}} & {cbuf_rdat_b12c0_d3, cbuf_rdat_b12c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b13c0_d3}}, {512{cbuf_p1_rd_sel_ram_b13c1_d3}}} & {cbuf_rdat_b13c0_d3, cbuf_rdat_b13c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b14c0_d3}}, {512{cbuf_p1_rd_sel_ram_b14c1_d3}}} & {cbuf_rdat_b14c0_d3, cbuf_rdat_b14c1_d3}) |
                               ({{512{cbuf_p1_rd_sel_ram_b15c0_d3}}, {512{cbuf_p1_rd_sel_ram_b15c1_d3}}} & {cbuf_rdat_b15c0_d3, cbuf_rdat_b15c1_d3});
end

always @(
  cbuf_p2_rd_sel_ram_b15c0_d3
  or cbuf_p2_rd_sel_ram_b15c1_d3
  or cbuf_rdat_b15c0_d3
  or cbuf_rdat_b15c1_d3
  ) begin
    cbuf_p2_rd_data_d4_w = ({{512{cbuf_p2_rd_sel_ram_b15c0_d3}}, {512{cbuf_p2_rd_sel_ram_b15c1_d3}}} & {cbuf_rdat_b15c0_d3, cbuf_rdat_b15c1_d3});
end

////////////////////////////////////////////////////////////////////////
// Input read stage4 registers                                        //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_rd_en_d4 <= {3{1'b0}};
  end else begin
  cbuf_rd_en_d4 <= cbuf_rd_en_d3;
  end
end

always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_rd_en_d3) == 1'b1) begin
    cbuf_p0_rd_data_d4[(0+1)*512-1:0*512] <= cbuf_p0_rd_data_d4_w[(0+1)*512-1:0*512];
  // VCS coverage off
  end else if ((cbuf_p0_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p0_rd_data_d4[(0+1)*512-1:0*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_rd_en_d3) == 1'b1) begin
    cbuf_p0_rd_data_d4[(1+1)*512-1:1*512] <= cbuf_p0_rd_data_d4_w[(1+1)*512-1:1*512];
  // VCS coverage off
  end else if ((cbuf_p0_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p0_rd_data_d4[(1+1)*512-1:1*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_rd_en_d3) == 1'b1) begin
    cbuf_p1_rd_data_d4[(0+1)*512-1:0*512] <= cbuf_p1_rd_data_d4_w[(0+1)*512-1:0*512];
  // VCS coverage off
  end else if ((cbuf_p1_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p1_rd_data_d4[(0+1)*512-1:0*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_rd_en_d3) == 1'b1) begin
    cbuf_p1_rd_data_d4[(1+1)*512-1:1*512] <= cbuf_p1_rd_data_d4_w[(1+1)*512-1:1*512];
  // VCS coverage off
  end else if ((cbuf_p1_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p1_rd_data_d4[(1+1)*512-1:1*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p2_rd_en_d3) == 1'b1) begin
    cbuf_p2_rd_data_d4[(0+1)*512-1:0*512] <= cbuf_p2_rd_data_d4_w[(0+1)*512-1:0*512];
  // VCS coverage off
  end else if ((cbuf_p2_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p2_rd_data_d4[(0+1)*512-1:0*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p2_rd_en_d3) == 1'b1) begin
    cbuf_p2_rd_data_d4[(1+1)*512-1:1*512] <= cbuf_p2_rd_data_d4_w[(1+1)*512-1:1*512];
  // VCS coverage off
  end else if ((cbuf_p2_rd_en_d3) == 1'b0) begin
  end else begin
    cbuf_p2_rd_data_d4[(1+1)*512-1:1*512] <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end


////////////////////////////////////////////////////////////////////////
// Input read stage5: connect to retiming register                    //
////////////////////////////////////////////////////////////////////////
assign {cbuf_p0_rd_en_d4,
        cbuf_p1_rd_en_d4,
        cbuf_p2_rd_en_d4} = cbuf_rd_en_d4;

assign {cbuf_p0_rd_c0_data_d4[512-1:0],
        cbuf_p0_rd_c1_data_d4[512-1:0]} = cbuf_p0_rd_data_d4;
assign {cbuf_p1_rd_c0_data_d4[512-1:0],
        cbuf_p1_rd_c1_data_d4[512-1:0]} = cbuf_p1_rd_data_d4;
assign {cbuf_p2_rd_c0_data_d4[512-1:0],
        cbuf_p2_rd_c1_data_d4[512-1:0]} = cbuf_p2_rd_data_d4;
////////////////////////////////////////////////////////////////////////
// Input read stage5: retiming register                               //
////////////////////////////////////////////////////////////////////////

always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p0_rd_c0_valid_d5 <= 1'b0;
  end else begin
  cbuf_p0_rd_c0_valid_d5 <= cbuf_p0_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_rd_en_d4) == 1'b1) begin
    cbuf_p0_rd_c0_data_d5 <= cbuf_p0_rd_c0_data_d4;
  // VCS coverage off
  end else if ((cbuf_p0_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p0_rd_c0_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p0_rd_c0_valid_d6_w = cbuf_p0_rd_c0_valid_d5;
assign cbuf_p0_rd_c0_data_d6_w  = cbuf_p0_rd_c0_data_d5;


always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p0_rd_c1_valid_d5 <= 1'b0;
  end else begin
  cbuf_p0_rd_c1_valid_d5 <= cbuf_p0_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p0_rd_en_d4) == 1'b1) begin
    cbuf_p0_rd_c1_data_d5 <= cbuf_p0_rd_c1_data_d4;
  // VCS coverage off
  end else if ((cbuf_p0_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p0_rd_c1_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p0_rd_c1_valid_d6_w = cbuf_p0_rd_c1_valid_d5;
assign cbuf_p0_rd_c1_data_d6_w  = cbuf_p0_rd_c1_data_d5;


always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p1_rd_c0_valid_d5 <= 1'b0;
  end else begin
  cbuf_p1_rd_c0_valid_d5 <= cbuf_p1_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_rd_en_d4) == 1'b1) begin
    cbuf_p1_rd_c0_data_d5 <= cbuf_p1_rd_c0_data_d4;
  // VCS coverage off
  end else if ((cbuf_p1_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p1_rd_c0_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p1_rd_c0_valid_d6_w = cbuf_p1_rd_c0_valid_d5;
assign cbuf_p1_rd_c0_data_d6_w  = cbuf_p1_rd_c0_data_d5;


always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p1_rd_c1_valid_d5 <= 1'b0;
  end else begin
  cbuf_p1_rd_c1_valid_d5 <= cbuf_p1_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p1_rd_en_d4) == 1'b1) begin
    cbuf_p1_rd_c1_data_d5 <= cbuf_p1_rd_c1_data_d4;
  // VCS coverage off
  end else if ((cbuf_p1_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p1_rd_c1_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p1_rd_c1_valid_d6_w = cbuf_p1_rd_c1_valid_d5;
assign cbuf_p1_rd_c1_data_d6_w  = cbuf_p1_rd_c1_data_d5;


always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p2_rd_c0_valid_d5 <= 1'b0;
  end else begin
  cbuf_p2_rd_c0_valid_d5 <= cbuf_p2_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p2_rd_en_d4) == 1'b1) begin
    cbuf_p2_rd_c0_data_d5 <= cbuf_p2_rd_c0_data_d4;
  // VCS coverage off
  end else if ((cbuf_p2_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p2_rd_c0_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p2_rd_c0_valid_d6_w = cbuf_p2_rd_c0_valid_d5;
assign cbuf_p2_rd_c0_data_d6_w  = cbuf_p2_rd_c0_data_d5;


always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p2_rd_c1_valid_d5 <= 1'b0;
  end else begin
  cbuf_p2_rd_c1_valid_d5 <= cbuf_p2_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk) begin
  if ((cbuf_p2_rd_en_d4) == 1'b1) begin
    cbuf_p2_rd_c1_data_d5 <= cbuf_p2_rd_c1_data_d4;
  // VCS coverage off
  end else if ((cbuf_p2_rd_en_d4) == 1'b0) begin
  end else begin
    cbuf_p2_rd_c1_data_d5 <= 'bx;  // spyglass disable STARC-2.10.1.6 W443 NoWidthInBasedNum-ML -- (Constant containing x or z used, Based number `bx contains an X, Width specification missing for based number)
  // VCS coverage on
  end
end
assign cbuf_p2_rd_c1_valid_d6_w = cbuf_p2_rd_c1_valid_d5;
assign cbuf_p2_rd_c1_data_d6_w  = cbuf_p2_rd_c1_data_d5;

////////////////////////////////////////////////////////////////////////
// Input read stage5 registers                                        //
////////////////////////////////////////////////////////////////////////
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p0_rd_en_d5 <= 1'b0;
  end else begin
  cbuf_p0_rd_en_d5 <= cbuf_p0_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p0_rd_valid_d6 <= 1'b0;
  end else begin
  cbuf_p0_rd_valid_d6 <= cbuf_p0_rd_en_d5;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p1_rd_en_d5 <= 1'b0;
  end else begin
  cbuf_p1_rd_en_d5 <= cbuf_p1_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p1_rd_valid_d6 <= 1'b0;
  end else begin
  cbuf_p1_rd_valid_d6 <= cbuf_p1_rd_en_d5;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p2_rd_en_d5 <= 1'b0;
  end else begin
  cbuf_p2_rd_en_d5 <= cbuf_p2_rd_en_d4;
  end
end
always @(posedge nvdla_core_clk or negedge nvdla_core_rstn) begin
  if (!nvdla_core_rstn) begin
    cbuf_p2_rd_valid_d6 <= 1'b0;
  end else begin
  cbuf_p2_rd_valid_d6 <= cbuf_p2_rd_en_d5;
  end
end
always @(posedge nvdla_core_clk) begin
    if(cbuf_p0_rd_c1_valid_d6_w)
    begin
        cbuf_p0_rd_data_d6[(1+1)*512-1:1*512] <= cbuf_p0_rd_c1_data_d6_w;    end
end

always @(posedge nvdla_core_clk) begin
    if(cbuf_p0_rd_c0_valid_d6_w)
    begin
        cbuf_p0_rd_data_d6[(0+1)*512-1:0*512] <= cbuf_p0_rd_c0_data_d6_w;    end
end

always @(posedge nvdla_core_clk) begin
    if(cbuf_p1_rd_c1_valid_d6_w)
    begin
        cbuf_p1_rd_data_d6[(1+1)*512-1:1*512] <= cbuf_p1_rd_c1_data_d6_w;    end
end

always @(posedge nvdla_core_clk) begin
    if(cbuf_p1_rd_c0_valid_d6_w)
    begin
        cbuf_p1_rd_data_d6[(0+1)*512-1:0*512] <= cbuf_p1_rd_c0_data_d6_w;    end
end

always @(posedge nvdla_core_clk) begin
    if(cbuf_p2_rd_c1_valid_d6_w)
    begin
        cbuf_p2_rd_data_d6[(1+1)*512-1:1*512] <= cbuf_p2_rd_c1_data_d6_w;    end
end

always @(posedge nvdla_core_clk) begin
    if(cbuf_p2_rd_c0_valid_d6_w)
    begin
        cbuf_p2_rd_data_d6[(0+1)*512-1:0*512] <= cbuf_p2_rd_c0_data_d6_w;    end
end

////////////////////////////////////////////////////////////////////////
// Connect to output signals                                          //
////////////////////////////////////////////////////////////////////////
// 读出口：rd_en 经 6 级打拍成 rd_valid（固定 6 拍延迟、无反压，下方
// nv_assert_at_time_interval #(0,6,...) 三个断言钉死该时序契约，CSC 端
// 的取数流水按此常数设计）；data_d6 只在对应半字 valid 时刷新，无读
// 期间保持旧值，下游必须只在 valid 拍采样

assign sc2buf_dat_rd_data       = cbuf_p0_rd_data_d6;
assign sc2buf_dat_rd_valid      = cbuf_p0_rd_valid_d6;

assign sc2buf_wt_rd_data       = cbuf_p1_rd_data_d6;
assign sc2buf_wt_rd_valid      = cbuf_p1_rd_valid_d6;

assign sc2buf_wmb_rd_data       = cbuf_p2_rd_data_d6;
assign sc2buf_wmb_rd_valid      = cbuf_p2_rd_valid_d6;

// ---------------- 以下为接口契约断言区（仅仿真） ----------------
// 访问规则汇总（cbuf 自身不做任何冲突仲裁，全靠这些断言把关）：
//   1) dat 写 hsel 不得为 0；dat 写/读不得碰 bank15；wt 写/读不得碰 bank0
//   2) 同拍不同客户端不撞 bank：dat写/wt写、dat读/wt读、dat写/wt读、
//      wt写/dat读均须异 bank；wt 读与 wmb 读不同时碰 bank15
//   3) 读写同拍不撞同 entry（dat、wt、wmb 各自）
//   4) 三个读口 en→valid 恰为 6 拍（nv_assert_at_time_interval #(0,6,..)）
// 注意：末尾 4 条 eccgen 断言引用的 *_ready_out 和 *_en_d1_w 在本配置
// 中无驱动（ECC 变体的残留），不构成有效检查



`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data write port invalid operation!")      zzz_assert_never_1x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_dat_wr_en & (cdma2buf_dat_wr_hsel == 2'h0))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data write port accesses BANK15!")      zzz_assert_never_2x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_dat_wr_en & (cdma2buf_dat_wr_addr[11:8] == 4'hf))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer weight write port accesses BANK0!")      zzz_assert_never_3x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_wt_wr_en & (cdma2buf_wt_wr_addr[11:8] == 4'h0))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data & weight write ports hazard!")      zzz_assert_never_4x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_dat_wr_en & cdma2buf_wt_wr_en & (cdma2buf_dat_wr_addr[11:8] == cdma2buf_wt_wr_addr[11:8]))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data read port accesses BANK15!")      zzz_assert_never_5x (nvdla_core_clk, `ASSERT_RESET, (sc2buf_dat_rd_en & (sc2buf_dat_rd_addr[11:8] == 4'hf))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer weight read port accesses BANK0!")      zzz_assert_never_6x (nvdla_core_clk, `ASSERT_RESET, (sc2buf_wt_rd_en & (sc2buf_wt_rd_addr[11:8] == 4'h0))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data & weight read ports hazard!")      zzz_assert_never_7x (nvdla_core_clk, `ASSERT_RESET, (sc2buf_dat_rd_en & sc2buf_wt_rd_en & (sc2buf_dat_rd_addr[11:8] == sc2buf_wt_rd_addr[11:8]))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer weight & wmb read ports hazard!")      zzz_assert_never_8x (nvdla_core_clk, `ASSERT_RESET, (sc2buf_wt_rd_en & sc2buf_wmb_rd_en & (sc2buf_wt_rd_addr[11:8] == 4'hf))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data read & write port hazard!")      zzz_assert_never_9x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_dat_wr_en & sc2buf_dat_rd_en & (cdma2buf_dat_wr_addr == sc2buf_dat_rd_addr))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer weight read & write port hazard!")      zzz_assert_never_10x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_wt_wr_en & sc2buf_wt_rd_en & (cdma2buf_wt_wr_addr == sc2buf_wt_rd_addr))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  // 【疑上游笔误·警示】本断言意图是抓"wt 写 bank15 与 wmb 读同 entry"，
  // 但地址比较用的是 sc2buf_wt_rd_addr（wt 读口，12 位）而非
  // sc2buf_wmb_rd_addr（wmb 读口，8 位）——8 位对 12 位比较且对象错口，
  // 检查目标错位，实际未覆盖 wmb 读写冲突。保留原逻辑不改，仅记录
  nv_assert_never #(0,0,"Error! Convolution buffer wmb read & write port hazard!")      zzz_assert_never_11x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_wt_wr_en & sc2buf_wmb_rd_en & (cdma2buf_wt_wr_addr[7:0] == sc2buf_wt_rd_addr) & (cdma2buf_wt_wr_addr[11:8] == 4'hf))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer data write port and weight read port access same bandk!")      zzz_assert_never_12x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_dat_wr_en & sc2buf_wt_rd_en & (cdma2buf_dat_wr_addr[11:8] == sc2buf_wt_rd_addr[11:8]))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer weight write port and data read port access same bandk!")      zzz_assert_never_13x (nvdla_core_clk, `ASSERT_RESET, (cdma2buf_wt_wr_en & sc2buf_dat_rd_en & (cdma2buf_wt_wr_addr[11:8] == sc2buf_dat_rd_addr[11:8]))); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_at_time_interval #(0,6,1,0,0,"Error! Convolution buffer data read port latency error!")      zzz_assert_at_time_interval_14x (nvdla_core_clk, `ASSERT_RESET, sc2buf_dat_rd_en, sc2buf_dat_rd_valid); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_at_time_interval #(0,6,1,0,0,"Error! Convolution buffer weight read port latency error!")      zzz_assert_at_time_interval_15x (nvdla_core_clk, `ASSERT_RESET, sc2buf_wt_rd_en, sc2buf_wt_rd_valid); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_at_time_interval #(0,6,1,0,0,"Error! Convolution buffer wmb read port latency error!")      zzz_assert_at_time_interval_16x (nvdla_core_clk, `ASSERT_RESET, sc2buf_wmb_rd_en, sc2buf_wmb_rd_valid); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer eccgen p0 lo is push back!")      zzz_assert_never_17x (nvdla_core_clk, `ASSERT_RESET, (cbuf_p0_wr_lo_en & ~cbuf_p0_wr_lo_ready_out)); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer eccgen p0 hi is push back!")      zzz_assert_never_18x (nvdla_core_clk, `ASSERT_RESET, (cbuf_p0_wr_hi_en & ~cbuf_p0_wr_hi_ready_out)); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer eccgen p1 is push back!")      zzz_assert_never_19x (nvdla_core_clk, `ASSERT_RESET, (cbuf_p1_wr_en & ~cbuf_p1_wr_ready_out)); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass disable_block NoWidthInBasedNum-ML 
// spyglass disable_block STARC-2.10.3.2a 
// spyglass disable_block STARC05-2.1.3.1 
// spyglass disable_block STARC-2.1.4.6 
// spyglass disable_block W116 
// spyglass disable_block W154 
// spyglass disable_block W239 
// spyglass disable_block W362 
// spyglass disable_block WRN_58 
// spyglass disable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON
`ifdef ASSERT_ON
`ifdef FV_ASSERT_ON
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef SYNTHESIS
`define ASSERT_RESET nvdla_core_rstn
`else
`ifdef ASSERT_OFF_RESET_IS_X
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b0 : nvdla_core_rstn)
`else
`define ASSERT_RESET ((1'bx === nvdla_core_rstn) ? 1'b1 : nvdla_core_rstn)
`endif // ASSERT_OFF_RESET_IS_X
`endif // SYNTHESIS
`endif // FV_ASSERT_ON
`ifndef SYNTHESIS
  // VCS coverage off 
  nv_assert_never #(0,0,"Error! Convolution buffer eccgen p1 valid mismatch!")      zzz_assert_never_20x (nvdla_core_clk, `ASSERT_RESET, (cbuf_p1_wr_en ^ cbuf_p1_wr_en_d1_w)); // spyglass disable W504 SelfDeterminedExpr-ML 
  // VCS coverage on
`endif
`undef ASSERT_RESET
`endif // ASSERT_ON
`ifdef SPYGLASS_ASSERT_ON
`else
// spyglass enable_block NoWidthInBasedNum-ML 
// spyglass enable_block STARC-2.10.3.2a 
// spyglass enable_block STARC05-2.1.3.1 
// spyglass enable_block STARC-2.1.4.6 
// spyglass enable_block W116 
// spyglass enable_block W154 
// spyglass enable_block W239 
// spyglass enable_block W362 
// spyglass enable_block WRN_58 
// spyglass enable_block WRN_61 
`endif // SPYGLASS_ASSERT_ON

// //==========================================================
// // OBS connection
// //==========================================================
// assign obs_bus_cbuf_cdma2buf_dat_wr_en   = cdma2buf_dat_wr_en;
// assign obs_bus_cbuf_cdma2buf_dat_wr_hsel = cdma2buf_dat_wr_hsel;
// assign obs_bus_cbuf_cdma2buf_dat_wr_addr = cdma2buf_dat_wr_addr;
// assign obs_bus_cbuf_cdma2buf_wt_wr_en    = cdma2buf_wt_wr_en;
// assign obs_bus_cbuf_cdma2buf_wt_wr_hsel  = cdma2buf_wt_wr_hsel;
// assign obs_bus_cbuf_cdma2buf_wt_wr_addr  = cdma2buf_wt_wr_addr;
// assign obs_bus_cbuf_sc2buf_dat_rd_en     = sc2buf_dat_rd_en;
// assign obs_bus_cbuf_sc2buf_dat_rd_addr   = sc2buf_dat_rd_addr;
// assign obs_bus_cbuf_sc2buf_dat_rd_valid  = sc2buf_dat_rd_valid;
// assign obs_bus_cbuf_sc2buf_wt_rd_en      = sc2buf_wt_rd_en;
// assign obs_bus_cbuf_sc2buf_wt_rd_addr    = sc2buf_wt_rd_addr;
// assign obs_bus_cbuf_sc2buf_wt_rd_valid   = sc2buf_wt_rd_valid;
// assign obs_bus_cbuf_sc2buf_wmb_rd_en     = sc2buf_wmb_rd_en;
// assign obs_bus_cbuf_sc2buf_wmb_rd_addr   = sc2buf_wmb_rd_addr;
// assign obs_bus_cbuf_sc2buf_wmb_rd_valid  = sc2buf_wmb_rd_valid;

endmodule // NV_NVDLA_cbuf


