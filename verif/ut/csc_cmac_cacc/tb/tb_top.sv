// -----------------------------------------------------------------------------
// tb_top : csc + cmac(A/B) + cacc 子流水线 UT 顶层（本文件由脚本生成，勿手编大段
//          端口表；生成器见 tb/gen_tb_top.py，端口清单解析自 outdir DUT 源文件）
//   - 7 实例：NV_NVDLA_csc + RT_csc2cmac_a/b + NV_NVDLA_cmac x2 +
//     RT_cmac_a2cacc/b + NV_NVDLA_cacc；RT 是纯打拍（vmod/nvdla/retiming/），
//     带上保持整芯节拍。连线权威：NV_nvdla.v u_partition_ma(:2523)/mb(:2817)
//     port map + partition_c(csc)/partition_a(cacc)
//   - cmac 模块 csb 口端口名固定带 _a_（csb2cmac_a_req/cmac_a2csb_resp），
//     b 例同名端口接 csb2cmac_b_*/cmac_b2csb_* 网线；数据口（sc2mac_*/mac2accu_*）
//     无 a/b 后缀，靠外部连线区分——照 NV_nvdla.v 两处 port map 核对
//   - CSB：单 csb master 面 + 4 目标译码（块号 6/7/8/9 分发 req_pvld，prdy 按
//     目标选择回送，4 路 resp OR-mux + onehot0 检查——driver 单笔阻塞保证无冲突）
//   - cbuf_model 三通道挂 sc2buf（响应侧，固定 6 拍延迟）；csc_cdma_stub 挂
//     cdma2sc/sc2cdma；sdp_sink_stub 挂 cacc2sdp；intr_if x2 按位挂
//     cacc2glb_done_intr_pd；accu2sc_credit cacc->csc 直连（DUT 内自闭环，
//     真实芯片同为分区间直连线，NV_nvdla.v:156-157 无 RT）
//   - L1 观测 monitor 挂点（Wave2 预留）：sc2mac_dat_a_*/sc2mac_wt_a_*（RT 前）、
//     mac_a2accu_src_*/mac_b2accu_src_*（RT 前）均为 tb 显式 wire，可直接挂接口
//   - tie-off：pwrbus_ram_pd=0、clk_ovr=0、tmc2slcg_disable_clock_gating=1
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import csc_cmac_cacc_ut_pkg::*;

  // ---------------- 时钟 / 复位 ----------------
  real core_period_ns = 7.0;

  logic nvdla_core_clk  = 1'b0;
  logic nvdla_core_rstn = 1'b0;

  initial begin
    void'($value$plusargs("core_period_ns=%f", core_period_ns));
    forever #(core_period_ns / 2.0) nvdla_core_clk = ~nvdla_core_clk;
  end

  initial begin
    nvdla_core_rstn = 1'b0;
    #101;
    nvdla_core_rstn = 1'b1;
  end

  // ---------------- 互连 wire（脚本自 DUT 端口表生成） ----------------
  wire            sc2cdma_dat_pending_req;
  wire            sc2cdma_wt_pending_req;
  wire            accu2sc_credit_vld;
  wire [2:0]      accu2sc_credit_size;
  wire            csb2csc_req_pvld;
  wire            csb2csc_req_prdy;
  wire [62:0]     csb2csc_req_pd;
  wire            csc2csb_resp_valid;
  wire [33:0]     csc2csb_resp_pd;
  wire            sc2cdma_dat_updt;
  wire [11:0]     sc2cdma_dat_entries;
  wire [11:0]     sc2cdma_dat_slices;
  wire            sc2buf_dat_rd_en;
  wire [11:0]     sc2buf_dat_rd_addr;
  wire            sc2buf_dat_rd_valid;
  wire [1023:0]   sc2buf_dat_rd_data;
  wire            sc2buf_wmb_rd_en;
  wire [7:0]      sc2buf_wmb_rd_addr;
  wire            sc2buf_wmb_rd_valid;
  wire [1023:0]   sc2buf_wmb_rd_data;
  wire            sc2buf_wt_rd_en;
  wire [11:0]     sc2buf_wt_rd_addr;
  wire            sc2buf_wt_rd_valid;
  wire [1023:0]   sc2buf_wt_rd_data;
  wire            sc2mac_dat_a_pvld;
  wire [127:0]    sc2mac_dat_a_mask;
  wire [7:0]      sc2mac_dat_a_data0;
  wire [7:0]      sc2mac_dat_a_data1;
  wire [7:0]      sc2mac_dat_a_data2;
  wire [7:0]      sc2mac_dat_a_data3;
  wire [7:0]      sc2mac_dat_a_data4;
  wire [7:0]      sc2mac_dat_a_data5;
  wire [7:0]      sc2mac_dat_a_data6;
  wire [7:0]      sc2mac_dat_a_data7;
  wire [7:0]      sc2mac_dat_a_data8;
  wire [7:0]      sc2mac_dat_a_data9;
  wire [7:0]      sc2mac_dat_a_data10;
  wire [7:0]      sc2mac_dat_a_data11;
  wire [7:0]      sc2mac_dat_a_data12;
  wire [7:0]      sc2mac_dat_a_data13;
  wire [7:0]      sc2mac_dat_a_data14;
  wire [7:0]      sc2mac_dat_a_data15;
  wire [7:0]      sc2mac_dat_a_data16;
  wire [7:0]      sc2mac_dat_a_data17;
  wire [7:0]      sc2mac_dat_a_data18;
  wire [7:0]      sc2mac_dat_a_data19;
  wire [7:0]      sc2mac_dat_a_data20;
  wire [7:0]      sc2mac_dat_a_data21;
  wire [7:0]      sc2mac_dat_a_data22;
  wire [7:0]      sc2mac_dat_a_data23;
  wire [7:0]      sc2mac_dat_a_data24;
  wire [7:0]      sc2mac_dat_a_data25;
  wire [7:0]      sc2mac_dat_a_data26;
  wire [7:0]      sc2mac_dat_a_data27;
  wire [7:0]      sc2mac_dat_a_data28;
  wire [7:0]      sc2mac_dat_a_data29;
  wire [7:0]      sc2mac_dat_a_data30;
  wire [7:0]      sc2mac_dat_a_data31;
  wire [7:0]      sc2mac_dat_a_data32;
  wire [7:0]      sc2mac_dat_a_data33;
  wire [7:0]      sc2mac_dat_a_data34;
  wire [7:0]      sc2mac_dat_a_data35;
  wire [7:0]      sc2mac_dat_a_data36;
  wire [7:0]      sc2mac_dat_a_data37;
  wire [7:0]      sc2mac_dat_a_data38;
  wire [7:0]      sc2mac_dat_a_data39;
  wire [7:0]      sc2mac_dat_a_data40;
  wire [7:0]      sc2mac_dat_a_data41;
  wire [7:0]      sc2mac_dat_a_data42;
  wire [7:0]      sc2mac_dat_a_data43;
  wire [7:0]      sc2mac_dat_a_data44;
  wire [7:0]      sc2mac_dat_a_data45;
  wire [7:0]      sc2mac_dat_a_data46;
  wire [7:0]      sc2mac_dat_a_data47;
  wire [7:0]      sc2mac_dat_a_data48;
  wire [7:0]      sc2mac_dat_a_data49;
  wire [7:0]      sc2mac_dat_a_data50;
  wire [7:0]      sc2mac_dat_a_data51;
  wire [7:0]      sc2mac_dat_a_data52;
  wire [7:0]      sc2mac_dat_a_data53;
  wire [7:0]      sc2mac_dat_a_data54;
  wire [7:0]      sc2mac_dat_a_data55;
  wire [7:0]      sc2mac_dat_a_data56;
  wire [7:0]      sc2mac_dat_a_data57;
  wire [7:0]      sc2mac_dat_a_data58;
  wire [7:0]      sc2mac_dat_a_data59;
  wire [7:0]      sc2mac_dat_a_data60;
  wire [7:0]      sc2mac_dat_a_data61;
  wire [7:0]      sc2mac_dat_a_data62;
  wire [7:0]      sc2mac_dat_a_data63;
  wire [7:0]      sc2mac_dat_a_data64;
  wire [7:0]      sc2mac_dat_a_data65;
  wire [7:0]      sc2mac_dat_a_data66;
  wire [7:0]      sc2mac_dat_a_data67;
  wire [7:0]      sc2mac_dat_a_data68;
  wire [7:0]      sc2mac_dat_a_data69;
  wire [7:0]      sc2mac_dat_a_data70;
  wire [7:0]      sc2mac_dat_a_data71;
  wire [7:0]      sc2mac_dat_a_data72;
  wire [7:0]      sc2mac_dat_a_data73;
  wire [7:0]      sc2mac_dat_a_data74;
  wire [7:0]      sc2mac_dat_a_data75;
  wire [7:0]      sc2mac_dat_a_data76;
  wire [7:0]      sc2mac_dat_a_data77;
  wire [7:0]      sc2mac_dat_a_data78;
  wire [7:0]      sc2mac_dat_a_data79;
  wire [7:0]      sc2mac_dat_a_data80;
  wire [7:0]      sc2mac_dat_a_data81;
  wire [7:0]      sc2mac_dat_a_data82;
  wire [7:0]      sc2mac_dat_a_data83;
  wire [7:0]      sc2mac_dat_a_data84;
  wire [7:0]      sc2mac_dat_a_data85;
  wire [7:0]      sc2mac_dat_a_data86;
  wire [7:0]      sc2mac_dat_a_data87;
  wire [7:0]      sc2mac_dat_a_data88;
  wire [7:0]      sc2mac_dat_a_data89;
  wire [7:0]      sc2mac_dat_a_data90;
  wire [7:0]      sc2mac_dat_a_data91;
  wire [7:0]      sc2mac_dat_a_data92;
  wire [7:0]      sc2mac_dat_a_data93;
  wire [7:0]      sc2mac_dat_a_data94;
  wire [7:0]      sc2mac_dat_a_data95;
  wire [7:0]      sc2mac_dat_a_data96;
  wire [7:0]      sc2mac_dat_a_data97;
  wire [7:0]      sc2mac_dat_a_data98;
  wire [7:0]      sc2mac_dat_a_data99;
  wire [7:0]      sc2mac_dat_a_data100;
  wire [7:0]      sc2mac_dat_a_data101;
  wire [7:0]      sc2mac_dat_a_data102;
  wire [7:0]      sc2mac_dat_a_data103;
  wire [7:0]      sc2mac_dat_a_data104;
  wire [7:0]      sc2mac_dat_a_data105;
  wire [7:0]      sc2mac_dat_a_data106;
  wire [7:0]      sc2mac_dat_a_data107;
  wire [7:0]      sc2mac_dat_a_data108;
  wire [7:0]      sc2mac_dat_a_data109;
  wire [7:0]      sc2mac_dat_a_data110;
  wire [7:0]      sc2mac_dat_a_data111;
  wire [7:0]      sc2mac_dat_a_data112;
  wire [7:0]      sc2mac_dat_a_data113;
  wire [7:0]      sc2mac_dat_a_data114;
  wire [7:0]      sc2mac_dat_a_data115;
  wire [7:0]      sc2mac_dat_a_data116;
  wire [7:0]      sc2mac_dat_a_data117;
  wire [7:0]      sc2mac_dat_a_data118;
  wire [7:0]      sc2mac_dat_a_data119;
  wire [7:0]      sc2mac_dat_a_data120;
  wire [7:0]      sc2mac_dat_a_data121;
  wire [7:0]      sc2mac_dat_a_data122;
  wire [7:0]      sc2mac_dat_a_data123;
  wire [7:0]      sc2mac_dat_a_data124;
  wire [7:0]      sc2mac_dat_a_data125;
  wire [7:0]      sc2mac_dat_a_data126;
  wire [7:0]      sc2mac_dat_a_data127;
  wire [8:0]      sc2mac_dat_a_pd;
  wire            sc2mac_dat_b_pvld;
  wire [127:0]    sc2mac_dat_b_mask;
  wire [7:0]      sc2mac_dat_b_data0;
  wire [7:0]      sc2mac_dat_b_data1;
  wire [7:0]      sc2mac_dat_b_data2;
  wire [7:0]      sc2mac_dat_b_data3;
  wire [7:0]      sc2mac_dat_b_data4;
  wire [7:0]      sc2mac_dat_b_data5;
  wire [7:0]      sc2mac_dat_b_data6;
  wire [7:0]      sc2mac_dat_b_data7;
  wire [7:0]      sc2mac_dat_b_data8;
  wire [7:0]      sc2mac_dat_b_data9;
  wire [7:0]      sc2mac_dat_b_data10;
  wire [7:0]      sc2mac_dat_b_data11;
  wire [7:0]      sc2mac_dat_b_data12;
  wire [7:0]      sc2mac_dat_b_data13;
  wire [7:0]      sc2mac_dat_b_data14;
  wire [7:0]      sc2mac_dat_b_data15;
  wire [7:0]      sc2mac_dat_b_data16;
  wire [7:0]      sc2mac_dat_b_data17;
  wire [7:0]      sc2mac_dat_b_data18;
  wire [7:0]      sc2mac_dat_b_data19;
  wire [7:0]      sc2mac_dat_b_data20;
  wire [7:0]      sc2mac_dat_b_data21;
  wire [7:0]      sc2mac_dat_b_data22;
  wire [7:0]      sc2mac_dat_b_data23;
  wire [7:0]      sc2mac_dat_b_data24;
  wire [7:0]      sc2mac_dat_b_data25;
  wire [7:0]      sc2mac_dat_b_data26;
  wire [7:0]      sc2mac_dat_b_data27;
  wire [7:0]      sc2mac_dat_b_data28;
  wire [7:0]      sc2mac_dat_b_data29;
  wire [7:0]      sc2mac_dat_b_data30;
  wire [7:0]      sc2mac_dat_b_data31;
  wire [7:0]      sc2mac_dat_b_data32;
  wire [7:0]      sc2mac_dat_b_data33;
  wire [7:0]      sc2mac_dat_b_data34;
  wire [7:0]      sc2mac_dat_b_data35;
  wire [7:0]      sc2mac_dat_b_data36;
  wire [7:0]      sc2mac_dat_b_data37;
  wire [7:0]      sc2mac_dat_b_data38;
  wire [7:0]      sc2mac_dat_b_data39;
  wire [7:0]      sc2mac_dat_b_data40;
  wire [7:0]      sc2mac_dat_b_data41;
  wire [7:0]      sc2mac_dat_b_data42;
  wire [7:0]      sc2mac_dat_b_data43;
  wire [7:0]      sc2mac_dat_b_data44;
  wire [7:0]      sc2mac_dat_b_data45;
  wire [7:0]      sc2mac_dat_b_data46;
  wire [7:0]      sc2mac_dat_b_data47;
  wire [7:0]      sc2mac_dat_b_data48;
  wire [7:0]      sc2mac_dat_b_data49;
  wire [7:0]      sc2mac_dat_b_data50;
  wire [7:0]      sc2mac_dat_b_data51;
  wire [7:0]      sc2mac_dat_b_data52;
  wire [7:0]      sc2mac_dat_b_data53;
  wire [7:0]      sc2mac_dat_b_data54;
  wire [7:0]      sc2mac_dat_b_data55;
  wire [7:0]      sc2mac_dat_b_data56;
  wire [7:0]      sc2mac_dat_b_data57;
  wire [7:0]      sc2mac_dat_b_data58;
  wire [7:0]      sc2mac_dat_b_data59;
  wire [7:0]      sc2mac_dat_b_data60;
  wire [7:0]      sc2mac_dat_b_data61;
  wire [7:0]      sc2mac_dat_b_data62;
  wire [7:0]      sc2mac_dat_b_data63;
  wire [7:0]      sc2mac_dat_b_data64;
  wire [7:0]      sc2mac_dat_b_data65;
  wire [7:0]      sc2mac_dat_b_data66;
  wire [7:0]      sc2mac_dat_b_data67;
  wire [7:0]      sc2mac_dat_b_data68;
  wire [7:0]      sc2mac_dat_b_data69;
  wire [7:0]      sc2mac_dat_b_data70;
  wire [7:0]      sc2mac_dat_b_data71;
  wire [7:0]      sc2mac_dat_b_data72;
  wire [7:0]      sc2mac_dat_b_data73;
  wire [7:0]      sc2mac_dat_b_data74;
  wire [7:0]      sc2mac_dat_b_data75;
  wire [7:0]      sc2mac_dat_b_data76;
  wire [7:0]      sc2mac_dat_b_data77;
  wire [7:0]      sc2mac_dat_b_data78;
  wire [7:0]      sc2mac_dat_b_data79;
  wire [7:0]      sc2mac_dat_b_data80;
  wire [7:0]      sc2mac_dat_b_data81;
  wire [7:0]      sc2mac_dat_b_data82;
  wire [7:0]      sc2mac_dat_b_data83;
  wire [7:0]      sc2mac_dat_b_data84;
  wire [7:0]      sc2mac_dat_b_data85;
  wire [7:0]      sc2mac_dat_b_data86;
  wire [7:0]      sc2mac_dat_b_data87;
  wire [7:0]      sc2mac_dat_b_data88;
  wire [7:0]      sc2mac_dat_b_data89;
  wire [7:0]      sc2mac_dat_b_data90;
  wire [7:0]      sc2mac_dat_b_data91;
  wire [7:0]      sc2mac_dat_b_data92;
  wire [7:0]      sc2mac_dat_b_data93;
  wire [7:0]      sc2mac_dat_b_data94;
  wire [7:0]      sc2mac_dat_b_data95;
  wire [7:0]      sc2mac_dat_b_data96;
  wire [7:0]      sc2mac_dat_b_data97;
  wire [7:0]      sc2mac_dat_b_data98;
  wire [7:0]      sc2mac_dat_b_data99;
  wire [7:0]      sc2mac_dat_b_data100;
  wire [7:0]      sc2mac_dat_b_data101;
  wire [7:0]      sc2mac_dat_b_data102;
  wire [7:0]      sc2mac_dat_b_data103;
  wire [7:0]      sc2mac_dat_b_data104;
  wire [7:0]      sc2mac_dat_b_data105;
  wire [7:0]      sc2mac_dat_b_data106;
  wire [7:0]      sc2mac_dat_b_data107;
  wire [7:0]      sc2mac_dat_b_data108;
  wire [7:0]      sc2mac_dat_b_data109;
  wire [7:0]      sc2mac_dat_b_data110;
  wire [7:0]      sc2mac_dat_b_data111;
  wire [7:0]      sc2mac_dat_b_data112;
  wire [7:0]      sc2mac_dat_b_data113;
  wire [7:0]      sc2mac_dat_b_data114;
  wire [7:0]      sc2mac_dat_b_data115;
  wire [7:0]      sc2mac_dat_b_data116;
  wire [7:0]      sc2mac_dat_b_data117;
  wire [7:0]      sc2mac_dat_b_data118;
  wire [7:0]      sc2mac_dat_b_data119;
  wire [7:0]      sc2mac_dat_b_data120;
  wire [7:0]      sc2mac_dat_b_data121;
  wire [7:0]      sc2mac_dat_b_data122;
  wire [7:0]      sc2mac_dat_b_data123;
  wire [7:0]      sc2mac_dat_b_data124;
  wire [7:0]      sc2mac_dat_b_data125;
  wire [7:0]      sc2mac_dat_b_data126;
  wire [7:0]      sc2mac_dat_b_data127;
  wire [8:0]      sc2mac_dat_b_pd;
  wire            sc2mac_wt_a_pvld;
  wire [127:0]    sc2mac_wt_a_mask;
  wire [7:0]      sc2mac_wt_a_data0;
  wire [7:0]      sc2mac_wt_a_data1;
  wire [7:0]      sc2mac_wt_a_data2;
  wire [7:0]      sc2mac_wt_a_data3;
  wire [7:0]      sc2mac_wt_a_data4;
  wire [7:0]      sc2mac_wt_a_data5;
  wire [7:0]      sc2mac_wt_a_data6;
  wire [7:0]      sc2mac_wt_a_data7;
  wire [7:0]      sc2mac_wt_a_data8;
  wire [7:0]      sc2mac_wt_a_data9;
  wire [7:0]      sc2mac_wt_a_data10;
  wire [7:0]      sc2mac_wt_a_data11;
  wire [7:0]      sc2mac_wt_a_data12;
  wire [7:0]      sc2mac_wt_a_data13;
  wire [7:0]      sc2mac_wt_a_data14;
  wire [7:0]      sc2mac_wt_a_data15;
  wire [7:0]      sc2mac_wt_a_data16;
  wire [7:0]      sc2mac_wt_a_data17;
  wire [7:0]      sc2mac_wt_a_data18;
  wire [7:0]      sc2mac_wt_a_data19;
  wire [7:0]      sc2mac_wt_a_data20;
  wire [7:0]      sc2mac_wt_a_data21;
  wire [7:0]      sc2mac_wt_a_data22;
  wire [7:0]      sc2mac_wt_a_data23;
  wire [7:0]      sc2mac_wt_a_data24;
  wire [7:0]      sc2mac_wt_a_data25;
  wire [7:0]      sc2mac_wt_a_data26;
  wire [7:0]      sc2mac_wt_a_data27;
  wire [7:0]      sc2mac_wt_a_data28;
  wire [7:0]      sc2mac_wt_a_data29;
  wire [7:0]      sc2mac_wt_a_data30;
  wire [7:0]      sc2mac_wt_a_data31;
  wire [7:0]      sc2mac_wt_a_data32;
  wire [7:0]      sc2mac_wt_a_data33;
  wire [7:0]      sc2mac_wt_a_data34;
  wire [7:0]      sc2mac_wt_a_data35;
  wire [7:0]      sc2mac_wt_a_data36;
  wire [7:0]      sc2mac_wt_a_data37;
  wire [7:0]      sc2mac_wt_a_data38;
  wire [7:0]      sc2mac_wt_a_data39;
  wire [7:0]      sc2mac_wt_a_data40;
  wire [7:0]      sc2mac_wt_a_data41;
  wire [7:0]      sc2mac_wt_a_data42;
  wire [7:0]      sc2mac_wt_a_data43;
  wire [7:0]      sc2mac_wt_a_data44;
  wire [7:0]      sc2mac_wt_a_data45;
  wire [7:0]      sc2mac_wt_a_data46;
  wire [7:0]      sc2mac_wt_a_data47;
  wire [7:0]      sc2mac_wt_a_data48;
  wire [7:0]      sc2mac_wt_a_data49;
  wire [7:0]      sc2mac_wt_a_data50;
  wire [7:0]      sc2mac_wt_a_data51;
  wire [7:0]      sc2mac_wt_a_data52;
  wire [7:0]      sc2mac_wt_a_data53;
  wire [7:0]      sc2mac_wt_a_data54;
  wire [7:0]      sc2mac_wt_a_data55;
  wire [7:0]      sc2mac_wt_a_data56;
  wire [7:0]      sc2mac_wt_a_data57;
  wire [7:0]      sc2mac_wt_a_data58;
  wire [7:0]      sc2mac_wt_a_data59;
  wire [7:0]      sc2mac_wt_a_data60;
  wire [7:0]      sc2mac_wt_a_data61;
  wire [7:0]      sc2mac_wt_a_data62;
  wire [7:0]      sc2mac_wt_a_data63;
  wire [7:0]      sc2mac_wt_a_data64;
  wire [7:0]      sc2mac_wt_a_data65;
  wire [7:0]      sc2mac_wt_a_data66;
  wire [7:0]      sc2mac_wt_a_data67;
  wire [7:0]      sc2mac_wt_a_data68;
  wire [7:0]      sc2mac_wt_a_data69;
  wire [7:0]      sc2mac_wt_a_data70;
  wire [7:0]      sc2mac_wt_a_data71;
  wire [7:0]      sc2mac_wt_a_data72;
  wire [7:0]      sc2mac_wt_a_data73;
  wire [7:0]      sc2mac_wt_a_data74;
  wire [7:0]      sc2mac_wt_a_data75;
  wire [7:0]      sc2mac_wt_a_data76;
  wire [7:0]      sc2mac_wt_a_data77;
  wire [7:0]      sc2mac_wt_a_data78;
  wire [7:0]      sc2mac_wt_a_data79;
  wire [7:0]      sc2mac_wt_a_data80;
  wire [7:0]      sc2mac_wt_a_data81;
  wire [7:0]      sc2mac_wt_a_data82;
  wire [7:0]      sc2mac_wt_a_data83;
  wire [7:0]      sc2mac_wt_a_data84;
  wire [7:0]      sc2mac_wt_a_data85;
  wire [7:0]      sc2mac_wt_a_data86;
  wire [7:0]      sc2mac_wt_a_data87;
  wire [7:0]      sc2mac_wt_a_data88;
  wire [7:0]      sc2mac_wt_a_data89;
  wire [7:0]      sc2mac_wt_a_data90;
  wire [7:0]      sc2mac_wt_a_data91;
  wire [7:0]      sc2mac_wt_a_data92;
  wire [7:0]      sc2mac_wt_a_data93;
  wire [7:0]      sc2mac_wt_a_data94;
  wire [7:0]      sc2mac_wt_a_data95;
  wire [7:0]      sc2mac_wt_a_data96;
  wire [7:0]      sc2mac_wt_a_data97;
  wire [7:0]      sc2mac_wt_a_data98;
  wire [7:0]      sc2mac_wt_a_data99;
  wire [7:0]      sc2mac_wt_a_data100;
  wire [7:0]      sc2mac_wt_a_data101;
  wire [7:0]      sc2mac_wt_a_data102;
  wire [7:0]      sc2mac_wt_a_data103;
  wire [7:0]      sc2mac_wt_a_data104;
  wire [7:0]      sc2mac_wt_a_data105;
  wire [7:0]      sc2mac_wt_a_data106;
  wire [7:0]      sc2mac_wt_a_data107;
  wire [7:0]      sc2mac_wt_a_data108;
  wire [7:0]      sc2mac_wt_a_data109;
  wire [7:0]      sc2mac_wt_a_data110;
  wire [7:0]      sc2mac_wt_a_data111;
  wire [7:0]      sc2mac_wt_a_data112;
  wire [7:0]      sc2mac_wt_a_data113;
  wire [7:0]      sc2mac_wt_a_data114;
  wire [7:0]      sc2mac_wt_a_data115;
  wire [7:0]      sc2mac_wt_a_data116;
  wire [7:0]      sc2mac_wt_a_data117;
  wire [7:0]      sc2mac_wt_a_data118;
  wire [7:0]      sc2mac_wt_a_data119;
  wire [7:0]      sc2mac_wt_a_data120;
  wire [7:0]      sc2mac_wt_a_data121;
  wire [7:0]      sc2mac_wt_a_data122;
  wire [7:0]      sc2mac_wt_a_data123;
  wire [7:0]      sc2mac_wt_a_data124;
  wire [7:0]      sc2mac_wt_a_data125;
  wire [7:0]      sc2mac_wt_a_data126;
  wire [7:0]      sc2mac_wt_a_data127;
  wire [7:0]      sc2mac_wt_a_sel;
  wire            sc2mac_wt_b_pvld;
  wire [127:0]    sc2mac_wt_b_mask;
  wire [7:0]      sc2mac_wt_b_data0;
  wire [7:0]      sc2mac_wt_b_data1;
  wire [7:0]      sc2mac_wt_b_data2;
  wire [7:0]      sc2mac_wt_b_data3;
  wire [7:0]      sc2mac_wt_b_data4;
  wire [7:0]      sc2mac_wt_b_data5;
  wire [7:0]      sc2mac_wt_b_data6;
  wire [7:0]      sc2mac_wt_b_data7;
  wire [7:0]      sc2mac_wt_b_data8;
  wire [7:0]      sc2mac_wt_b_data9;
  wire [7:0]      sc2mac_wt_b_data10;
  wire [7:0]      sc2mac_wt_b_data11;
  wire [7:0]      sc2mac_wt_b_data12;
  wire [7:0]      sc2mac_wt_b_data13;
  wire [7:0]      sc2mac_wt_b_data14;
  wire [7:0]      sc2mac_wt_b_data15;
  wire [7:0]      sc2mac_wt_b_data16;
  wire [7:0]      sc2mac_wt_b_data17;
  wire [7:0]      sc2mac_wt_b_data18;
  wire [7:0]      sc2mac_wt_b_data19;
  wire [7:0]      sc2mac_wt_b_data20;
  wire [7:0]      sc2mac_wt_b_data21;
  wire [7:0]      sc2mac_wt_b_data22;
  wire [7:0]      sc2mac_wt_b_data23;
  wire [7:0]      sc2mac_wt_b_data24;
  wire [7:0]      sc2mac_wt_b_data25;
  wire [7:0]      sc2mac_wt_b_data26;
  wire [7:0]      sc2mac_wt_b_data27;
  wire [7:0]      sc2mac_wt_b_data28;
  wire [7:0]      sc2mac_wt_b_data29;
  wire [7:0]      sc2mac_wt_b_data30;
  wire [7:0]      sc2mac_wt_b_data31;
  wire [7:0]      sc2mac_wt_b_data32;
  wire [7:0]      sc2mac_wt_b_data33;
  wire [7:0]      sc2mac_wt_b_data34;
  wire [7:0]      sc2mac_wt_b_data35;
  wire [7:0]      sc2mac_wt_b_data36;
  wire [7:0]      sc2mac_wt_b_data37;
  wire [7:0]      sc2mac_wt_b_data38;
  wire [7:0]      sc2mac_wt_b_data39;
  wire [7:0]      sc2mac_wt_b_data40;
  wire [7:0]      sc2mac_wt_b_data41;
  wire [7:0]      sc2mac_wt_b_data42;
  wire [7:0]      sc2mac_wt_b_data43;
  wire [7:0]      sc2mac_wt_b_data44;
  wire [7:0]      sc2mac_wt_b_data45;
  wire [7:0]      sc2mac_wt_b_data46;
  wire [7:0]      sc2mac_wt_b_data47;
  wire [7:0]      sc2mac_wt_b_data48;
  wire [7:0]      sc2mac_wt_b_data49;
  wire [7:0]      sc2mac_wt_b_data50;
  wire [7:0]      sc2mac_wt_b_data51;
  wire [7:0]      sc2mac_wt_b_data52;
  wire [7:0]      sc2mac_wt_b_data53;
  wire [7:0]      sc2mac_wt_b_data54;
  wire [7:0]      sc2mac_wt_b_data55;
  wire [7:0]      sc2mac_wt_b_data56;
  wire [7:0]      sc2mac_wt_b_data57;
  wire [7:0]      sc2mac_wt_b_data58;
  wire [7:0]      sc2mac_wt_b_data59;
  wire [7:0]      sc2mac_wt_b_data60;
  wire [7:0]      sc2mac_wt_b_data61;
  wire [7:0]      sc2mac_wt_b_data62;
  wire [7:0]      sc2mac_wt_b_data63;
  wire [7:0]      sc2mac_wt_b_data64;
  wire [7:0]      sc2mac_wt_b_data65;
  wire [7:0]      sc2mac_wt_b_data66;
  wire [7:0]      sc2mac_wt_b_data67;
  wire [7:0]      sc2mac_wt_b_data68;
  wire [7:0]      sc2mac_wt_b_data69;
  wire [7:0]      sc2mac_wt_b_data70;
  wire [7:0]      sc2mac_wt_b_data71;
  wire [7:0]      sc2mac_wt_b_data72;
  wire [7:0]      sc2mac_wt_b_data73;
  wire [7:0]      sc2mac_wt_b_data74;
  wire [7:0]      sc2mac_wt_b_data75;
  wire [7:0]      sc2mac_wt_b_data76;
  wire [7:0]      sc2mac_wt_b_data77;
  wire [7:0]      sc2mac_wt_b_data78;
  wire [7:0]      sc2mac_wt_b_data79;
  wire [7:0]      sc2mac_wt_b_data80;
  wire [7:0]      sc2mac_wt_b_data81;
  wire [7:0]      sc2mac_wt_b_data82;
  wire [7:0]      sc2mac_wt_b_data83;
  wire [7:0]      sc2mac_wt_b_data84;
  wire [7:0]      sc2mac_wt_b_data85;
  wire [7:0]      sc2mac_wt_b_data86;
  wire [7:0]      sc2mac_wt_b_data87;
  wire [7:0]      sc2mac_wt_b_data88;
  wire [7:0]      sc2mac_wt_b_data89;
  wire [7:0]      sc2mac_wt_b_data90;
  wire [7:0]      sc2mac_wt_b_data91;
  wire [7:0]      sc2mac_wt_b_data92;
  wire [7:0]      sc2mac_wt_b_data93;
  wire [7:0]      sc2mac_wt_b_data94;
  wire [7:0]      sc2mac_wt_b_data95;
  wire [7:0]      sc2mac_wt_b_data96;
  wire [7:0]      sc2mac_wt_b_data97;
  wire [7:0]      sc2mac_wt_b_data98;
  wire [7:0]      sc2mac_wt_b_data99;
  wire [7:0]      sc2mac_wt_b_data100;
  wire [7:0]      sc2mac_wt_b_data101;
  wire [7:0]      sc2mac_wt_b_data102;
  wire [7:0]      sc2mac_wt_b_data103;
  wire [7:0]      sc2mac_wt_b_data104;
  wire [7:0]      sc2mac_wt_b_data105;
  wire [7:0]      sc2mac_wt_b_data106;
  wire [7:0]      sc2mac_wt_b_data107;
  wire [7:0]      sc2mac_wt_b_data108;
  wire [7:0]      sc2mac_wt_b_data109;
  wire [7:0]      sc2mac_wt_b_data110;
  wire [7:0]      sc2mac_wt_b_data111;
  wire [7:0]      sc2mac_wt_b_data112;
  wire [7:0]      sc2mac_wt_b_data113;
  wire [7:0]      sc2mac_wt_b_data114;
  wire [7:0]      sc2mac_wt_b_data115;
  wire [7:0]      sc2mac_wt_b_data116;
  wire [7:0]      sc2mac_wt_b_data117;
  wire [7:0]      sc2mac_wt_b_data118;
  wire [7:0]      sc2mac_wt_b_data119;
  wire [7:0]      sc2mac_wt_b_data120;
  wire [7:0]      sc2mac_wt_b_data121;
  wire [7:0]      sc2mac_wt_b_data122;
  wire [7:0]      sc2mac_wt_b_data123;
  wire [7:0]      sc2mac_wt_b_data124;
  wire [7:0]      sc2mac_wt_b_data125;
  wire [7:0]      sc2mac_wt_b_data126;
  wire [7:0]      sc2mac_wt_b_data127;
  wire [7:0]      sc2mac_wt_b_sel;
  wire            sc2cdma_wt_updt;
  wire [13:0]     sc2cdma_wt_kernels;
  wire [11:0]     sc2cdma_wt_entries;
  wire [8:0]      sc2cdma_wmb_entries;
  wire            sc2mac_wt_a_dst_pvld;
  wire [127:0]    sc2mac_wt_a_dst_mask;
  wire [7:0]      sc2mac_wt_a_dst_data0;
  wire [7:0]      sc2mac_wt_a_dst_data1;
  wire [7:0]      sc2mac_wt_a_dst_data2;
  wire [7:0]      sc2mac_wt_a_dst_data3;
  wire [7:0]      sc2mac_wt_a_dst_data4;
  wire [7:0]      sc2mac_wt_a_dst_data5;
  wire [7:0]      sc2mac_wt_a_dst_data6;
  wire [7:0]      sc2mac_wt_a_dst_data7;
  wire [7:0]      sc2mac_wt_a_dst_data8;
  wire [7:0]      sc2mac_wt_a_dst_data9;
  wire [7:0]      sc2mac_wt_a_dst_data10;
  wire [7:0]      sc2mac_wt_a_dst_data11;
  wire [7:0]      sc2mac_wt_a_dst_data12;
  wire [7:0]      sc2mac_wt_a_dst_data13;
  wire [7:0]      sc2mac_wt_a_dst_data14;
  wire [7:0]      sc2mac_wt_a_dst_data15;
  wire [7:0]      sc2mac_wt_a_dst_data16;
  wire [7:0]      sc2mac_wt_a_dst_data17;
  wire [7:0]      sc2mac_wt_a_dst_data18;
  wire [7:0]      sc2mac_wt_a_dst_data19;
  wire [7:0]      sc2mac_wt_a_dst_data20;
  wire [7:0]      sc2mac_wt_a_dst_data21;
  wire [7:0]      sc2mac_wt_a_dst_data22;
  wire [7:0]      sc2mac_wt_a_dst_data23;
  wire [7:0]      sc2mac_wt_a_dst_data24;
  wire [7:0]      sc2mac_wt_a_dst_data25;
  wire [7:0]      sc2mac_wt_a_dst_data26;
  wire [7:0]      sc2mac_wt_a_dst_data27;
  wire [7:0]      sc2mac_wt_a_dst_data28;
  wire [7:0]      sc2mac_wt_a_dst_data29;
  wire [7:0]      sc2mac_wt_a_dst_data30;
  wire [7:0]      sc2mac_wt_a_dst_data31;
  wire [7:0]      sc2mac_wt_a_dst_data32;
  wire [7:0]      sc2mac_wt_a_dst_data33;
  wire [7:0]      sc2mac_wt_a_dst_data34;
  wire [7:0]      sc2mac_wt_a_dst_data35;
  wire [7:0]      sc2mac_wt_a_dst_data36;
  wire [7:0]      sc2mac_wt_a_dst_data37;
  wire [7:0]      sc2mac_wt_a_dst_data38;
  wire [7:0]      sc2mac_wt_a_dst_data39;
  wire [7:0]      sc2mac_wt_a_dst_data40;
  wire [7:0]      sc2mac_wt_a_dst_data41;
  wire [7:0]      sc2mac_wt_a_dst_data42;
  wire [7:0]      sc2mac_wt_a_dst_data43;
  wire [7:0]      sc2mac_wt_a_dst_data44;
  wire [7:0]      sc2mac_wt_a_dst_data45;
  wire [7:0]      sc2mac_wt_a_dst_data46;
  wire [7:0]      sc2mac_wt_a_dst_data47;
  wire [7:0]      sc2mac_wt_a_dst_data48;
  wire [7:0]      sc2mac_wt_a_dst_data49;
  wire [7:0]      sc2mac_wt_a_dst_data50;
  wire [7:0]      sc2mac_wt_a_dst_data51;
  wire [7:0]      sc2mac_wt_a_dst_data52;
  wire [7:0]      sc2mac_wt_a_dst_data53;
  wire [7:0]      sc2mac_wt_a_dst_data54;
  wire [7:0]      sc2mac_wt_a_dst_data55;
  wire [7:0]      sc2mac_wt_a_dst_data56;
  wire [7:0]      sc2mac_wt_a_dst_data57;
  wire [7:0]      sc2mac_wt_a_dst_data58;
  wire [7:0]      sc2mac_wt_a_dst_data59;
  wire [7:0]      sc2mac_wt_a_dst_data60;
  wire [7:0]      sc2mac_wt_a_dst_data61;
  wire [7:0]      sc2mac_wt_a_dst_data62;
  wire [7:0]      sc2mac_wt_a_dst_data63;
  wire [7:0]      sc2mac_wt_a_dst_data64;
  wire [7:0]      sc2mac_wt_a_dst_data65;
  wire [7:0]      sc2mac_wt_a_dst_data66;
  wire [7:0]      sc2mac_wt_a_dst_data67;
  wire [7:0]      sc2mac_wt_a_dst_data68;
  wire [7:0]      sc2mac_wt_a_dst_data69;
  wire [7:0]      sc2mac_wt_a_dst_data70;
  wire [7:0]      sc2mac_wt_a_dst_data71;
  wire [7:0]      sc2mac_wt_a_dst_data72;
  wire [7:0]      sc2mac_wt_a_dst_data73;
  wire [7:0]      sc2mac_wt_a_dst_data74;
  wire [7:0]      sc2mac_wt_a_dst_data75;
  wire [7:0]      sc2mac_wt_a_dst_data76;
  wire [7:0]      sc2mac_wt_a_dst_data77;
  wire [7:0]      sc2mac_wt_a_dst_data78;
  wire [7:0]      sc2mac_wt_a_dst_data79;
  wire [7:0]      sc2mac_wt_a_dst_data80;
  wire [7:0]      sc2mac_wt_a_dst_data81;
  wire [7:0]      sc2mac_wt_a_dst_data82;
  wire [7:0]      sc2mac_wt_a_dst_data83;
  wire [7:0]      sc2mac_wt_a_dst_data84;
  wire [7:0]      sc2mac_wt_a_dst_data85;
  wire [7:0]      sc2mac_wt_a_dst_data86;
  wire [7:0]      sc2mac_wt_a_dst_data87;
  wire [7:0]      sc2mac_wt_a_dst_data88;
  wire [7:0]      sc2mac_wt_a_dst_data89;
  wire [7:0]      sc2mac_wt_a_dst_data90;
  wire [7:0]      sc2mac_wt_a_dst_data91;
  wire [7:0]      sc2mac_wt_a_dst_data92;
  wire [7:0]      sc2mac_wt_a_dst_data93;
  wire [7:0]      sc2mac_wt_a_dst_data94;
  wire [7:0]      sc2mac_wt_a_dst_data95;
  wire [7:0]      sc2mac_wt_a_dst_data96;
  wire [7:0]      sc2mac_wt_a_dst_data97;
  wire [7:0]      sc2mac_wt_a_dst_data98;
  wire [7:0]      sc2mac_wt_a_dst_data99;
  wire [7:0]      sc2mac_wt_a_dst_data100;
  wire [7:0]      sc2mac_wt_a_dst_data101;
  wire [7:0]      sc2mac_wt_a_dst_data102;
  wire [7:0]      sc2mac_wt_a_dst_data103;
  wire [7:0]      sc2mac_wt_a_dst_data104;
  wire [7:0]      sc2mac_wt_a_dst_data105;
  wire [7:0]      sc2mac_wt_a_dst_data106;
  wire [7:0]      sc2mac_wt_a_dst_data107;
  wire [7:0]      sc2mac_wt_a_dst_data108;
  wire [7:0]      sc2mac_wt_a_dst_data109;
  wire [7:0]      sc2mac_wt_a_dst_data110;
  wire [7:0]      sc2mac_wt_a_dst_data111;
  wire [7:0]      sc2mac_wt_a_dst_data112;
  wire [7:0]      sc2mac_wt_a_dst_data113;
  wire [7:0]      sc2mac_wt_a_dst_data114;
  wire [7:0]      sc2mac_wt_a_dst_data115;
  wire [7:0]      sc2mac_wt_a_dst_data116;
  wire [7:0]      sc2mac_wt_a_dst_data117;
  wire [7:0]      sc2mac_wt_a_dst_data118;
  wire [7:0]      sc2mac_wt_a_dst_data119;
  wire [7:0]      sc2mac_wt_a_dst_data120;
  wire [7:0]      sc2mac_wt_a_dst_data121;
  wire [7:0]      sc2mac_wt_a_dst_data122;
  wire [7:0]      sc2mac_wt_a_dst_data123;
  wire [7:0]      sc2mac_wt_a_dst_data124;
  wire [7:0]      sc2mac_wt_a_dst_data125;
  wire [7:0]      sc2mac_wt_a_dst_data126;
  wire [7:0]      sc2mac_wt_a_dst_data127;
  wire [7:0]      sc2mac_wt_a_dst_sel;
  wire            sc2mac_dat_a_dst_pvld;
  wire [127:0]    sc2mac_dat_a_dst_mask;
  wire [7:0]      sc2mac_dat_a_dst_data0;
  wire [7:0]      sc2mac_dat_a_dst_data1;
  wire [7:0]      sc2mac_dat_a_dst_data2;
  wire [7:0]      sc2mac_dat_a_dst_data3;
  wire [7:0]      sc2mac_dat_a_dst_data4;
  wire [7:0]      sc2mac_dat_a_dst_data5;
  wire [7:0]      sc2mac_dat_a_dst_data6;
  wire [7:0]      sc2mac_dat_a_dst_data7;
  wire [7:0]      sc2mac_dat_a_dst_data8;
  wire [7:0]      sc2mac_dat_a_dst_data9;
  wire [7:0]      sc2mac_dat_a_dst_data10;
  wire [7:0]      sc2mac_dat_a_dst_data11;
  wire [7:0]      sc2mac_dat_a_dst_data12;
  wire [7:0]      sc2mac_dat_a_dst_data13;
  wire [7:0]      sc2mac_dat_a_dst_data14;
  wire [7:0]      sc2mac_dat_a_dst_data15;
  wire [7:0]      sc2mac_dat_a_dst_data16;
  wire [7:0]      sc2mac_dat_a_dst_data17;
  wire [7:0]      sc2mac_dat_a_dst_data18;
  wire [7:0]      sc2mac_dat_a_dst_data19;
  wire [7:0]      sc2mac_dat_a_dst_data20;
  wire [7:0]      sc2mac_dat_a_dst_data21;
  wire [7:0]      sc2mac_dat_a_dst_data22;
  wire [7:0]      sc2mac_dat_a_dst_data23;
  wire [7:0]      sc2mac_dat_a_dst_data24;
  wire [7:0]      sc2mac_dat_a_dst_data25;
  wire [7:0]      sc2mac_dat_a_dst_data26;
  wire [7:0]      sc2mac_dat_a_dst_data27;
  wire [7:0]      sc2mac_dat_a_dst_data28;
  wire [7:0]      sc2mac_dat_a_dst_data29;
  wire [7:0]      sc2mac_dat_a_dst_data30;
  wire [7:0]      sc2mac_dat_a_dst_data31;
  wire [7:0]      sc2mac_dat_a_dst_data32;
  wire [7:0]      sc2mac_dat_a_dst_data33;
  wire [7:0]      sc2mac_dat_a_dst_data34;
  wire [7:0]      sc2mac_dat_a_dst_data35;
  wire [7:0]      sc2mac_dat_a_dst_data36;
  wire [7:0]      sc2mac_dat_a_dst_data37;
  wire [7:0]      sc2mac_dat_a_dst_data38;
  wire [7:0]      sc2mac_dat_a_dst_data39;
  wire [7:0]      sc2mac_dat_a_dst_data40;
  wire [7:0]      sc2mac_dat_a_dst_data41;
  wire [7:0]      sc2mac_dat_a_dst_data42;
  wire [7:0]      sc2mac_dat_a_dst_data43;
  wire [7:0]      sc2mac_dat_a_dst_data44;
  wire [7:0]      sc2mac_dat_a_dst_data45;
  wire [7:0]      sc2mac_dat_a_dst_data46;
  wire [7:0]      sc2mac_dat_a_dst_data47;
  wire [7:0]      sc2mac_dat_a_dst_data48;
  wire [7:0]      sc2mac_dat_a_dst_data49;
  wire [7:0]      sc2mac_dat_a_dst_data50;
  wire [7:0]      sc2mac_dat_a_dst_data51;
  wire [7:0]      sc2mac_dat_a_dst_data52;
  wire [7:0]      sc2mac_dat_a_dst_data53;
  wire [7:0]      sc2mac_dat_a_dst_data54;
  wire [7:0]      sc2mac_dat_a_dst_data55;
  wire [7:0]      sc2mac_dat_a_dst_data56;
  wire [7:0]      sc2mac_dat_a_dst_data57;
  wire [7:0]      sc2mac_dat_a_dst_data58;
  wire [7:0]      sc2mac_dat_a_dst_data59;
  wire [7:0]      sc2mac_dat_a_dst_data60;
  wire [7:0]      sc2mac_dat_a_dst_data61;
  wire [7:0]      sc2mac_dat_a_dst_data62;
  wire [7:0]      sc2mac_dat_a_dst_data63;
  wire [7:0]      sc2mac_dat_a_dst_data64;
  wire [7:0]      sc2mac_dat_a_dst_data65;
  wire [7:0]      sc2mac_dat_a_dst_data66;
  wire [7:0]      sc2mac_dat_a_dst_data67;
  wire [7:0]      sc2mac_dat_a_dst_data68;
  wire [7:0]      sc2mac_dat_a_dst_data69;
  wire [7:0]      sc2mac_dat_a_dst_data70;
  wire [7:0]      sc2mac_dat_a_dst_data71;
  wire [7:0]      sc2mac_dat_a_dst_data72;
  wire [7:0]      sc2mac_dat_a_dst_data73;
  wire [7:0]      sc2mac_dat_a_dst_data74;
  wire [7:0]      sc2mac_dat_a_dst_data75;
  wire [7:0]      sc2mac_dat_a_dst_data76;
  wire [7:0]      sc2mac_dat_a_dst_data77;
  wire [7:0]      sc2mac_dat_a_dst_data78;
  wire [7:0]      sc2mac_dat_a_dst_data79;
  wire [7:0]      sc2mac_dat_a_dst_data80;
  wire [7:0]      sc2mac_dat_a_dst_data81;
  wire [7:0]      sc2mac_dat_a_dst_data82;
  wire [7:0]      sc2mac_dat_a_dst_data83;
  wire [7:0]      sc2mac_dat_a_dst_data84;
  wire [7:0]      sc2mac_dat_a_dst_data85;
  wire [7:0]      sc2mac_dat_a_dst_data86;
  wire [7:0]      sc2mac_dat_a_dst_data87;
  wire [7:0]      sc2mac_dat_a_dst_data88;
  wire [7:0]      sc2mac_dat_a_dst_data89;
  wire [7:0]      sc2mac_dat_a_dst_data90;
  wire [7:0]      sc2mac_dat_a_dst_data91;
  wire [7:0]      sc2mac_dat_a_dst_data92;
  wire [7:0]      sc2mac_dat_a_dst_data93;
  wire [7:0]      sc2mac_dat_a_dst_data94;
  wire [7:0]      sc2mac_dat_a_dst_data95;
  wire [7:0]      sc2mac_dat_a_dst_data96;
  wire [7:0]      sc2mac_dat_a_dst_data97;
  wire [7:0]      sc2mac_dat_a_dst_data98;
  wire [7:0]      sc2mac_dat_a_dst_data99;
  wire [7:0]      sc2mac_dat_a_dst_data100;
  wire [7:0]      sc2mac_dat_a_dst_data101;
  wire [7:0]      sc2mac_dat_a_dst_data102;
  wire [7:0]      sc2mac_dat_a_dst_data103;
  wire [7:0]      sc2mac_dat_a_dst_data104;
  wire [7:0]      sc2mac_dat_a_dst_data105;
  wire [7:0]      sc2mac_dat_a_dst_data106;
  wire [7:0]      sc2mac_dat_a_dst_data107;
  wire [7:0]      sc2mac_dat_a_dst_data108;
  wire [7:0]      sc2mac_dat_a_dst_data109;
  wire [7:0]      sc2mac_dat_a_dst_data110;
  wire [7:0]      sc2mac_dat_a_dst_data111;
  wire [7:0]      sc2mac_dat_a_dst_data112;
  wire [7:0]      sc2mac_dat_a_dst_data113;
  wire [7:0]      sc2mac_dat_a_dst_data114;
  wire [7:0]      sc2mac_dat_a_dst_data115;
  wire [7:0]      sc2mac_dat_a_dst_data116;
  wire [7:0]      sc2mac_dat_a_dst_data117;
  wire [7:0]      sc2mac_dat_a_dst_data118;
  wire [7:0]      sc2mac_dat_a_dst_data119;
  wire [7:0]      sc2mac_dat_a_dst_data120;
  wire [7:0]      sc2mac_dat_a_dst_data121;
  wire [7:0]      sc2mac_dat_a_dst_data122;
  wire [7:0]      sc2mac_dat_a_dst_data123;
  wire [7:0]      sc2mac_dat_a_dst_data124;
  wire [7:0]      sc2mac_dat_a_dst_data125;
  wire [7:0]      sc2mac_dat_a_dst_data126;
  wire [7:0]      sc2mac_dat_a_dst_data127;
  wire [8:0]      sc2mac_dat_a_dst_pd;
  wire            sc2mac_wt_b_dst_pvld;
  wire [127:0]    sc2mac_wt_b_dst_mask;
  wire [7:0]      sc2mac_wt_b_dst_data0;
  wire [7:0]      sc2mac_wt_b_dst_data1;
  wire [7:0]      sc2mac_wt_b_dst_data2;
  wire [7:0]      sc2mac_wt_b_dst_data3;
  wire [7:0]      sc2mac_wt_b_dst_data4;
  wire [7:0]      sc2mac_wt_b_dst_data5;
  wire [7:0]      sc2mac_wt_b_dst_data6;
  wire [7:0]      sc2mac_wt_b_dst_data7;
  wire [7:0]      sc2mac_wt_b_dst_data8;
  wire [7:0]      sc2mac_wt_b_dst_data9;
  wire [7:0]      sc2mac_wt_b_dst_data10;
  wire [7:0]      sc2mac_wt_b_dst_data11;
  wire [7:0]      sc2mac_wt_b_dst_data12;
  wire [7:0]      sc2mac_wt_b_dst_data13;
  wire [7:0]      sc2mac_wt_b_dst_data14;
  wire [7:0]      sc2mac_wt_b_dst_data15;
  wire [7:0]      sc2mac_wt_b_dst_data16;
  wire [7:0]      sc2mac_wt_b_dst_data17;
  wire [7:0]      sc2mac_wt_b_dst_data18;
  wire [7:0]      sc2mac_wt_b_dst_data19;
  wire [7:0]      sc2mac_wt_b_dst_data20;
  wire [7:0]      sc2mac_wt_b_dst_data21;
  wire [7:0]      sc2mac_wt_b_dst_data22;
  wire [7:0]      sc2mac_wt_b_dst_data23;
  wire [7:0]      sc2mac_wt_b_dst_data24;
  wire [7:0]      sc2mac_wt_b_dst_data25;
  wire [7:0]      sc2mac_wt_b_dst_data26;
  wire [7:0]      sc2mac_wt_b_dst_data27;
  wire [7:0]      sc2mac_wt_b_dst_data28;
  wire [7:0]      sc2mac_wt_b_dst_data29;
  wire [7:0]      sc2mac_wt_b_dst_data30;
  wire [7:0]      sc2mac_wt_b_dst_data31;
  wire [7:0]      sc2mac_wt_b_dst_data32;
  wire [7:0]      sc2mac_wt_b_dst_data33;
  wire [7:0]      sc2mac_wt_b_dst_data34;
  wire [7:0]      sc2mac_wt_b_dst_data35;
  wire [7:0]      sc2mac_wt_b_dst_data36;
  wire [7:0]      sc2mac_wt_b_dst_data37;
  wire [7:0]      sc2mac_wt_b_dst_data38;
  wire [7:0]      sc2mac_wt_b_dst_data39;
  wire [7:0]      sc2mac_wt_b_dst_data40;
  wire [7:0]      sc2mac_wt_b_dst_data41;
  wire [7:0]      sc2mac_wt_b_dst_data42;
  wire [7:0]      sc2mac_wt_b_dst_data43;
  wire [7:0]      sc2mac_wt_b_dst_data44;
  wire [7:0]      sc2mac_wt_b_dst_data45;
  wire [7:0]      sc2mac_wt_b_dst_data46;
  wire [7:0]      sc2mac_wt_b_dst_data47;
  wire [7:0]      sc2mac_wt_b_dst_data48;
  wire [7:0]      sc2mac_wt_b_dst_data49;
  wire [7:0]      sc2mac_wt_b_dst_data50;
  wire [7:0]      sc2mac_wt_b_dst_data51;
  wire [7:0]      sc2mac_wt_b_dst_data52;
  wire [7:0]      sc2mac_wt_b_dst_data53;
  wire [7:0]      sc2mac_wt_b_dst_data54;
  wire [7:0]      sc2mac_wt_b_dst_data55;
  wire [7:0]      sc2mac_wt_b_dst_data56;
  wire [7:0]      sc2mac_wt_b_dst_data57;
  wire [7:0]      sc2mac_wt_b_dst_data58;
  wire [7:0]      sc2mac_wt_b_dst_data59;
  wire [7:0]      sc2mac_wt_b_dst_data60;
  wire [7:0]      sc2mac_wt_b_dst_data61;
  wire [7:0]      sc2mac_wt_b_dst_data62;
  wire [7:0]      sc2mac_wt_b_dst_data63;
  wire [7:0]      sc2mac_wt_b_dst_data64;
  wire [7:0]      sc2mac_wt_b_dst_data65;
  wire [7:0]      sc2mac_wt_b_dst_data66;
  wire [7:0]      sc2mac_wt_b_dst_data67;
  wire [7:0]      sc2mac_wt_b_dst_data68;
  wire [7:0]      sc2mac_wt_b_dst_data69;
  wire [7:0]      sc2mac_wt_b_dst_data70;
  wire [7:0]      sc2mac_wt_b_dst_data71;
  wire [7:0]      sc2mac_wt_b_dst_data72;
  wire [7:0]      sc2mac_wt_b_dst_data73;
  wire [7:0]      sc2mac_wt_b_dst_data74;
  wire [7:0]      sc2mac_wt_b_dst_data75;
  wire [7:0]      sc2mac_wt_b_dst_data76;
  wire [7:0]      sc2mac_wt_b_dst_data77;
  wire [7:0]      sc2mac_wt_b_dst_data78;
  wire [7:0]      sc2mac_wt_b_dst_data79;
  wire [7:0]      sc2mac_wt_b_dst_data80;
  wire [7:0]      sc2mac_wt_b_dst_data81;
  wire [7:0]      sc2mac_wt_b_dst_data82;
  wire [7:0]      sc2mac_wt_b_dst_data83;
  wire [7:0]      sc2mac_wt_b_dst_data84;
  wire [7:0]      sc2mac_wt_b_dst_data85;
  wire [7:0]      sc2mac_wt_b_dst_data86;
  wire [7:0]      sc2mac_wt_b_dst_data87;
  wire [7:0]      sc2mac_wt_b_dst_data88;
  wire [7:0]      sc2mac_wt_b_dst_data89;
  wire [7:0]      sc2mac_wt_b_dst_data90;
  wire [7:0]      sc2mac_wt_b_dst_data91;
  wire [7:0]      sc2mac_wt_b_dst_data92;
  wire [7:0]      sc2mac_wt_b_dst_data93;
  wire [7:0]      sc2mac_wt_b_dst_data94;
  wire [7:0]      sc2mac_wt_b_dst_data95;
  wire [7:0]      sc2mac_wt_b_dst_data96;
  wire [7:0]      sc2mac_wt_b_dst_data97;
  wire [7:0]      sc2mac_wt_b_dst_data98;
  wire [7:0]      sc2mac_wt_b_dst_data99;
  wire [7:0]      sc2mac_wt_b_dst_data100;
  wire [7:0]      sc2mac_wt_b_dst_data101;
  wire [7:0]      sc2mac_wt_b_dst_data102;
  wire [7:0]      sc2mac_wt_b_dst_data103;
  wire [7:0]      sc2mac_wt_b_dst_data104;
  wire [7:0]      sc2mac_wt_b_dst_data105;
  wire [7:0]      sc2mac_wt_b_dst_data106;
  wire [7:0]      sc2mac_wt_b_dst_data107;
  wire [7:0]      sc2mac_wt_b_dst_data108;
  wire [7:0]      sc2mac_wt_b_dst_data109;
  wire [7:0]      sc2mac_wt_b_dst_data110;
  wire [7:0]      sc2mac_wt_b_dst_data111;
  wire [7:0]      sc2mac_wt_b_dst_data112;
  wire [7:0]      sc2mac_wt_b_dst_data113;
  wire [7:0]      sc2mac_wt_b_dst_data114;
  wire [7:0]      sc2mac_wt_b_dst_data115;
  wire [7:0]      sc2mac_wt_b_dst_data116;
  wire [7:0]      sc2mac_wt_b_dst_data117;
  wire [7:0]      sc2mac_wt_b_dst_data118;
  wire [7:0]      sc2mac_wt_b_dst_data119;
  wire [7:0]      sc2mac_wt_b_dst_data120;
  wire [7:0]      sc2mac_wt_b_dst_data121;
  wire [7:0]      sc2mac_wt_b_dst_data122;
  wire [7:0]      sc2mac_wt_b_dst_data123;
  wire [7:0]      sc2mac_wt_b_dst_data124;
  wire [7:0]      sc2mac_wt_b_dst_data125;
  wire [7:0]      sc2mac_wt_b_dst_data126;
  wire [7:0]      sc2mac_wt_b_dst_data127;
  wire [7:0]      sc2mac_wt_b_dst_sel;
  wire            sc2mac_dat_b_dst_pvld;
  wire [127:0]    sc2mac_dat_b_dst_mask;
  wire [7:0]      sc2mac_dat_b_dst_data0;
  wire [7:0]      sc2mac_dat_b_dst_data1;
  wire [7:0]      sc2mac_dat_b_dst_data2;
  wire [7:0]      sc2mac_dat_b_dst_data3;
  wire [7:0]      sc2mac_dat_b_dst_data4;
  wire [7:0]      sc2mac_dat_b_dst_data5;
  wire [7:0]      sc2mac_dat_b_dst_data6;
  wire [7:0]      sc2mac_dat_b_dst_data7;
  wire [7:0]      sc2mac_dat_b_dst_data8;
  wire [7:0]      sc2mac_dat_b_dst_data9;
  wire [7:0]      sc2mac_dat_b_dst_data10;
  wire [7:0]      sc2mac_dat_b_dst_data11;
  wire [7:0]      sc2mac_dat_b_dst_data12;
  wire [7:0]      sc2mac_dat_b_dst_data13;
  wire [7:0]      sc2mac_dat_b_dst_data14;
  wire [7:0]      sc2mac_dat_b_dst_data15;
  wire [7:0]      sc2mac_dat_b_dst_data16;
  wire [7:0]      sc2mac_dat_b_dst_data17;
  wire [7:0]      sc2mac_dat_b_dst_data18;
  wire [7:0]      sc2mac_dat_b_dst_data19;
  wire [7:0]      sc2mac_dat_b_dst_data20;
  wire [7:0]      sc2mac_dat_b_dst_data21;
  wire [7:0]      sc2mac_dat_b_dst_data22;
  wire [7:0]      sc2mac_dat_b_dst_data23;
  wire [7:0]      sc2mac_dat_b_dst_data24;
  wire [7:0]      sc2mac_dat_b_dst_data25;
  wire [7:0]      sc2mac_dat_b_dst_data26;
  wire [7:0]      sc2mac_dat_b_dst_data27;
  wire [7:0]      sc2mac_dat_b_dst_data28;
  wire [7:0]      sc2mac_dat_b_dst_data29;
  wire [7:0]      sc2mac_dat_b_dst_data30;
  wire [7:0]      sc2mac_dat_b_dst_data31;
  wire [7:0]      sc2mac_dat_b_dst_data32;
  wire [7:0]      sc2mac_dat_b_dst_data33;
  wire [7:0]      sc2mac_dat_b_dst_data34;
  wire [7:0]      sc2mac_dat_b_dst_data35;
  wire [7:0]      sc2mac_dat_b_dst_data36;
  wire [7:0]      sc2mac_dat_b_dst_data37;
  wire [7:0]      sc2mac_dat_b_dst_data38;
  wire [7:0]      sc2mac_dat_b_dst_data39;
  wire [7:0]      sc2mac_dat_b_dst_data40;
  wire [7:0]      sc2mac_dat_b_dst_data41;
  wire [7:0]      sc2mac_dat_b_dst_data42;
  wire [7:0]      sc2mac_dat_b_dst_data43;
  wire [7:0]      sc2mac_dat_b_dst_data44;
  wire [7:0]      sc2mac_dat_b_dst_data45;
  wire [7:0]      sc2mac_dat_b_dst_data46;
  wire [7:0]      sc2mac_dat_b_dst_data47;
  wire [7:0]      sc2mac_dat_b_dst_data48;
  wire [7:0]      sc2mac_dat_b_dst_data49;
  wire [7:0]      sc2mac_dat_b_dst_data50;
  wire [7:0]      sc2mac_dat_b_dst_data51;
  wire [7:0]      sc2mac_dat_b_dst_data52;
  wire [7:0]      sc2mac_dat_b_dst_data53;
  wire [7:0]      sc2mac_dat_b_dst_data54;
  wire [7:0]      sc2mac_dat_b_dst_data55;
  wire [7:0]      sc2mac_dat_b_dst_data56;
  wire [7:0]      sc2mac_dat_b_dst_data57;
  wire [7:0]      sc2mac_dat_b_dst_data58;
  wire [7:0]      sc2mac_dat_b_dst_data59;
  wire [7:0]      sc2mac_dat_b_dst_data60;
  wire [7:0]      sc2mac_dat_b_dst_data61;
  wire [7:0]      sc2mac_dat_b_dst_data62;
  wire [7:0]      sc2mac_dat_b_dst_data63;
  wire [7:0]      sc2mac_dat_b_dst_data64;
  wire [7:0]      sc2mac_dat_b_dst_data65;
  wire [7:0]      sc2mac_dat_b_dst_data66;
  wire [7:0]      sc2mac_dat_b_dst_data67;
  wire [7:0]      sc2mac_dat_b_dst_data68;
  wire [7:0]      sc2mac_dat_b_dst_data69;
  wire [7:0]      sc2mac_dat_b_dst_data70;
  wire [7:0]      sc2mac_dat_b_dst_data71;
  wire [7:0]      sc2mac_dat_b_dst_data72;
  wire [7:0]      sc2mac_dat_b_dst_data73;
  wire [7:0]      sc2mac_dat_b_dst_data74;
  wire [7:0]      sc2mac_dat_b_dst_data75;
  wire [7:0]      sc2mac_dat_b_dst_data76;
  wire [7:0]      sc2mac_dat_b_dst_data77;
  wire [7:0]      sc2mac_dat_b_dst_data78;
  wire [7:0]      sc2mac_dat_b_dst_data79;
  wire [7:0]      sc2mac_dat_b_dst_data80;
  wire [7:0]      sc2mac_dat_b_dst_data81;
  wire [7:0]      sc2mac_dat_b_dst_data82;
  wire [7:0]      sc2mac_dat_b_dst_data83;
  wire [7:0]      sc2mac_dat_b_dst_data84;
  wire [7:0]      sc2mac_dat_b_dst_data85;
  wire [7:0]      sc2mac_dat_b_dst_data86;
  wire [7:0]      sc2mac_dat_b_dst_data87;
  wire [7:0]      sc2mac_dat_b_dst_data88;
  wire [7:0]      sc2mac_dat_b_dst_data89;
  wire [7:0]      sc2mac_dat_b_dst_data90;
  wire [7:0]      sc2mac_dat_b_dst_data91;
  wire [7:0]      sc2mac_dat_b_dst_data92;
  wire [7:0]      sc2mac_dat_b_dst_data93;
  wire [7:0]      sc2mac_dat_b_dst_data94;
  wire [7:0]      sc2mac_dat_b_dst_data95;
  wire [7:0]      sc2mac_dat_b_dst_data96;
  wire [7:0]      sc2mac_dat_b_dst_data97;
  wire [7:0]      sc2mac_dat_b_dst_data98;
  wire [7:0]      sc2mac_dat_b_dst_data99;
  wire [7:0]      sc2mac_dat_b_dst_data100;
  wire [7:0]      sc2mac_dat_b_dst_data101;
  wire [7:0]      sc2mac_dat_b_dst_data102;
  wire [7:0]      sc2mac_dat_b_dst_data103;
  wire [7:0]      sc2mac_dat_b_dst_data104;
  wire [7:0]      sc2mac_dat_b_dst_data105;
  wire [7:0]      sc2mac_dat_b_dst_data106;
  wire [7:0]      sc2mac_dat_b_dst_data107;
  wire [7:0]      sc2mac_dat_b_dst_data108;
  wire [7:0]      sc2mac_dat_b_dst_data109;
  wire [7:0]      sc2mac_dat_b_dst_data110;
  wire [7:0]      sc2mac_dat_b_dst_data111;
  wire [7:0]      sc2mac_dat_b_dst_data112;
  wire [7:0]      sc2mac_dat_b_dst_data113;
  wire [7:0]      sc2mac_dat_b_dst_data114;
  wire [7:0]      sc2mac_dat_b_dst_data115;
  wire [7:0]      sc2mac_dat_b_dst_data116;
  wire [7:0]      sc2mac_dat_b_dst_data117;
  wire [7:0]      sc2mac_dat_b_dst_data118;
  wire [7:0]      sc2mac_dat_b_dst_data119;
  wire [7:0]      sc2mac_dat_b_dst_data120;
  wire [7:0]      sc2mac_dat_b_dst_data121;
  wire [7:0]      sc2mac_dat_b_dst_data122;
  wire [7:0]      sc2mac_dat_b_dst_data123;
  wire [7:0]      sc2mac_dat_b_dst_data124;
  wire [7:0]      sc2mac_dat_b_dst_data125;
  wire [7:0]      sc2mac_dat_b_dst_data126;
  wire [7:0]      sc2mac_dat_b_dst_data127;
  wire [8:0]      sc2mac_dat_b_dst_pd;
  wire            cmac_a2csb_resp_valid;
  wire [33:0]     cmac_a2csb_resp_pd;
  wire            csb2cmac_a_req_pvld;
  wire            csb2cmac_a_req_prdy;
  wire [62:0]     csb2cmac_a_req_pd;
  wire            mac_a2accu_src_pvld;
  wire [7:0]      mac_a2accu_src_mask;
  wire [7:0]      mac_a2accu_src_mode;
  wire [175:0]    mac_a2accu_src_data0;
  wire [175:0]    mac_a2accu_src_data1;
  wire [175:0]    mac_a2accu_src_data2;
  wire [175:0]    mac_a2accu_src_data3;
  wire [175:0]    mac_a2accu_src_data4;
  wire [175:0]    mac_a2accu_src_data5;
  wire [175:0]    mac_a2accu_src_data6;
  wire [175:0]    mac_a2accu_src_data7;
  wire [8:0]      mac_a2accu_src_pd;
  wire            cmac_b2csb_resp_valid;
  wire [33:0]     cmac_b2csb_resp_pd;
  wire            csb2cmac_b_req_pvld;
  wire            csb2cmac_b_req_prdy;
  wire [62:0]     csb2cmac_b_req_pd;
  wire            mac_b2accu_src_pvld;
  wire [7:0]      mac_b2accu_src_mask;
  wire [7:0]      mac_b2accu_src_mode;
  wire [175:0]    mac_b2accu_src_data0;
  wire [175:0]    mac_b2accu_src_data1;
  wire [175:0]    mac_b2accu_src_data2;
  wire [175:0]    mac_b2accu_src_data3;
  wire [175:0]    mac_b2accu_src_data4;
  wire [175:0]    mac_b2accu_src_data5;
  wire [175:0]    mac_b2accu_src_data6;
  wire [175:0]    mac_b2accu_src_data7;
  wire [8:0]      mac_b2accu_src_pd;
  wire            mac_a2accu_dst_pvld;
  wire [7:0]      mac_a2accu_dst_mask;
  wire [7:0]      mac_a2accu_dst_mode;
  wire [175:0]    mac_a2accu_dst_data0;
  wire [175:0]    mac_a2accu_dst_data1;
  wire [175:0]    mac_a2accu_dst_data2;
  wire [175:0]    mac_a2accu_dst_data3;
  wire [175:0]    mac_a2accu_dst_data4;
  wire [175:0]    mac_a2accu_dst_data5;
  wire [175:0]    mac_a2accu_dst_data6;
  wire [175:0]    mac_a2accu_dst_data7;
  wire [8:0]      mac_a2accu_dst_pd;
  wire            mac_b2accu_dst_pvld;
  wire [7:0]      mac_b2accu_dst_mask;
  wire [7:0]      mac_b2accu_dst_mode;
  wire [175:0]    mac_b2accu_dst_data0;
  wire [175:0]    mac_b2accu_dst_data1;
  wire [175:0]    mac_b2accu_dst_data2;
  wire [175:0]    mac_b2accu_dst_data3;
  wire [175:0]    mac_b2accu_dst_data4;
  wire [175:0]    mac_b2accu_dst_data5;
  wire [175:0]    mac_b2accu_dst_data6;
  wire [175:0]    mac_b2accu_dst_data7;
  wire [8:0]      mac_b2accu_dst_pd;
  wire            csb2cacc_req_pvld;
  wire            csb2cacc_req_prdy;
  wire [62:0]     csb2cacc_req_pd;
  wire            cacc2csb_resp_valid;
  wire [33:0]     cacc2csb_resp_pd;
  wire            cacc2sdp_valid;
  wire            cacc2sdp_ready;
  wire [513:0]    cacc2sdp_pd;
  wire [1:0]      cacc2glb_done_intr_pd;

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  cbuf_resp_if #(.ADDR_W(12)) u_cbuf_dat_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_resp_if #(.ADDR_W(12)) u_cbuf_wt_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_resp_if #(.ADDR_W(8))  u_cbuf_wmb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  csc_cdma_if u_cs_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  sdp_if u_sdp_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单 master 面 -> 4 目标译码 ----------------
  // 块号 blk = byte_addr[17:12] = word_addr[15:10]（同 ut_types.svh csb_target_of）
  // CSC=6(0x6000) CMAC_A=7(0x7000) CMAC_B=8(0x8000) CACC=9(0x9000)
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  wire [5:0]  csb_blk    = u_csb_if.addr[15:10];
  wire [62:0] csb_req_pd = {7'h0, u_csb_if.nposted, u_csb_if.write,
                            u_csb_if.wdat, 6'h0, u_csb_if.addr};

  assign csb2csc_req_pvld    = u_csb_if.valid && (csb_blk == 6'd6);
  assign csb2cmac_a_req_pvld = u_csb_if.valid && (csb_blk == 6'd7);
  assign csb2cmac_b_req_pvld = u_csb_if.valid && (csb_blk == 6'd8);
  assign csb2cacc_req_pvld   = u_csb_if.valid && (csb_blk == 6'd9);
  assign csb2csc_req_pd      = csb_req_pd;
  assign csb2cmac_a_req_pd   = csb_req_pd;
  assign csb2cmac_b_req_pd   = csb_req_pd;
  assign csb2cacc_req_pd     = csb_req_pd;

  // prdy 按目标选择回送（四路 RTL 实为常 1：CSC_regfile.v:745 / CMAC_reg.v:500 /
  // CACC_regfile.v:591；选择器保持结构正确性）
  assign u_csb_if.ready = (csb_blk == 6'd6) ? csb2csc_req_prdy    :
                          (csb_blk == 6'd7) ? csb2cmac_a_req_prdy :
                          (csb_blk == 6'd8) ? csb2cmac_b_req_prdy :
                          (csb_blk == 6'd9) ? csb2cacc_req_prdy   : 1'b1;

  // 4 路 resp OR-mux：driver 单笔阻塞（等响应才发下一笔）保证同刻至多 1 路 valid，
  // onehot0 检查兜底；resp_pd[33]=type：0=读数据 1=写完成（csb-link.md 6.2）
  wire [3:0] csb_resp_vld_vec = {cacc2csb_resp_valid, cmac_b2csb_resp_valid,
                                 cmac_a2csb_resp_valid, csc2csb_resp_valid};
  wire [33:0] csb_resp_pd_mux =
      ({34{csc2csb_resp_valid}}    & csc2csb_resp_pd)    |
      ({34{cmac_a2csb_resp_valid}} & cmac_a2csb_resp_pd) |
      ({34{cmac_b2csb_resp_valid}} & cmac_b2csb_resp_pd) |
      ({34{cacc2csb_resp_valid}}   & cacc2csb_resp_pd);
  wire csb_resp_any = |csb_resp_vld_vec;

  assign u_csb_if.rvalid      = csb_resp_any & ~csb_resp_pd_mux[33];
  assign u_csb_if.rdata       = csb_resp_pd_mux[31:0];
  assign u_csb_if.wr_complete = csb_resp_any &  csb_resp_pd_mux[33];

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 && !$onehot0(csb_resp_vld_vec))
      `uvm_error("tb_top",
                 $sformatf("CSB resp collision: {cacc,cmac_b,cmac_a,csc}=%b",
                           csb_resp_vld_vec))

  // ---------------- sc2buf 三读口 -> cbuf_model（响应侧） ----------------
  assign u_cbuf_dat_if.rd_en   = sc2buf_dat_rd_en;
  assign u_cbuf_dat_if.rd_addr = sc2buf_dat_rd_addr;
  assign sc2buf_dat_rd_valid   = u_cbuf_dat_if.rd_valid;
  assign sc2buf_dat_rd_data    = u_cbuf_dat_if.rd_data;
  assign u_cbuf_wt_if.rd_en    = sc2buf_wt_rd_en;
  assign u_cbuf_wt_if.rd_addr  = sc2buf_wt_rd_addr;
  assign sc2buf_wt_rd_valid    = u_cbuf_wt_if.rd_valid;
  assign sc2buf_wt_rd_data     = u_cbuf_wt_if.rd_data;
  assign u_cbuf_wmb_if.rd_en   = sc2buf_wmb_rd_en;
  assign u_cbuf_wmb_if.rd_addr = sc2buf_wmb_rd_addr;
  assign sc2buf_wmb_rd_valid   = u_cbuf_wmb_if.rd_valid;
  assign sc2buf_wmb_rd_data    = u_cbuf_wmb_if.rd_data;

  // ---------------- cdma_sc 状态-信用面（csc 输出 -> 监测；输入由 stub 驱） ----
  assign u_cs_if.sc2cdma_dat_updt        = sc2cdma_dat_updt;
  assign u_cs_if.sc2cdma_dat_entries     = sc2cdma_dat_entries;
  assign u_cs_if.sc2cdma_dat_slices      = sc2cdma_dat_slices;
  assign u_cs_if.sc2cdma_wt_updt         = sc2cdma_wt_updt;
  assign u_cs_if.sc2cdma_wt_kernels      = sc2cdma_wt_kernels;
  assign u_cs_if.sc2cdma_wt_entries      = sc2cdma_wt_entries;
  assign u_cs_if.sc2cdma_wmb_entries     = sc2cdma_wmb_entries;
  assign u_cs_if.sc2cdma_dat_pending_req = sc2cdma_dat_pending_req;
  assign u_cs_if.sc2cdma_wt_pending_req  = sc2cdma_wt_pending_req;

  // ---------------- cacc2sdp -> sdp_sink ----------------
  assign u_sdp_if.valid  = cacc2sdp_valid;
  assign u_sdp_if.pd     = cacc2sdp_pd;
  assign cacc2sdp_ready  = u_sdp_if.ready;

  // ---------------- 中断按位挂接 ----------------
  assign u_intr0_if.intr = cacc2glb_done_intr_pd[0];
  assign u_intr1_if.intr = cacc2glb_done_intr_pd[1];

  // ---------------- DUT：csc（partition_c 内例，端口 1:1 同名连线） ------
  NV_NVDLA_csc u_NV_NVDLA_csc (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.sc2cdma_dat_pending_req         (sc2cdma_dat_pending_req)
    ,.sc2cdma_wt_pending_req          (sc2cdma_wt_pending_req)
    ,.accu2sc_credit_vld              (accu2sc_credit_vld)
    ,.accu2sc_credit_size             (accu2sc_credit_size)
    ,.cdma2sc_dat_pending_ack         (u_cs_if.cdma2sc_dat_pending_ack)
    ,.cdma2sc_wt_pending_ack          (u_cs_if.cdma2sc_wt_pending_ack)
    ,.csb2csc_req_pvld                (csb2csc_req_pvld)
    ,.csb2csc_req_prdy                (csb2csc_req_prdy)
    ,.csb2csc_req_pd                  (csb2csc_req_pd)
    ,.csc2csb_resp_valid              (csc2csb_resp_valid)
    ,.csc2csb_resp_pd                 (csc2csb_resp_pd)
    ,.cdma2sc_dat_updt                (u_cs_if.cdma2sc_dat_updt)
    ,.cdma2sc_dat_entries             (u_cs_if.cdma2sc_dat_entries)
    ,.cdma2sc_dat_slices              (u_cs_if.cdma2sc_dat_slices)
    ,.sc2cdma_dat_updt                (sc2cdma_dat_updt)
    ,.sc2cdma_dat_entries             (sc2cdma_dat_entries)
    ,.sc2cdma_dat_slices              (sc2cdma_dat_slices)
    ,.pwrbus_ram_pd                   (32'b0)
    ,.sc2buf_dat_rd_en                (sc2buf_dat_rd_en)
    ,.sc2buf_dat_rd_addr              (sc2buf_dat_rd_addr)
    ,.sc2buf_dat_rd_valid             (sc2buf_dat_rd_valid)
    ,.sc2buf_dat_rd_data              (sc2buf_dat_rd_data)
    ,.sc2buf_wmb_rd_en                (sc2buf_wmb_rd_en)
    ,.sc2buf_wmb_rd_addr              (sc2buf_wmb_rd_addr)
    ,.sc2buf_wmb_rd_valid             (sc2buf_wmb_rd_valid)
    ,.sc2buf_wmb_rd_data              (sc2buf_wmb_rd_data)
    ,.sc2buf_wt_rd_en                 (sc2buf_wt_rd_en)
    ,.sc2buf_wt_rd_addr               (sc2buf_wt_rd_addr)
    ,.sc2buf_wt_rd_valid              (sc2buf_wt_rd_valid)
    ,.sc2buf_wt_rd_data               (sc2buf_wt_rd_data)
    ,.sc2mac_dat_a_pvld               (sc2mac_dat_a_pvld)
    ,.sc2mac_dat_a_mask               (sc2mac_dat_a_mask)
    ,.sc2mac_dat_a_data0              (sc2mac_dat_a_data0)
    ,.sc2mac_dat_a_data1              (sc2mac_dat_a_data1)
    ,.sc2mac_dat_a_data2              (sc2mac_dat_a_data2)
    ,.sc2mac_dat_a_data3              (sc2mac_dat_a_data3)
    ,.sc2mac_dat_a_data4              (sc2mac_dat_a_data4)
    ,.sc2mac_dat_a_data5              (sc2mac_dat_a_data5)
    ,.sc2mac_dat_a_data6              (sc2mac_dat_a_data6)
    ,.sc2mac_dat_a_data7              (sc2mac_dat_a_data7)
    ,.sc2mac_dat_a_data8              (sc2mac_dat_a_data8)
    ,.sc2mac_dat_a_data9              (sc2mac_dat_a_data9)
    ,.sc2mac_dat_a_data10             (sc2mac_dat_a_data10)
    ,.sc2mac_dat_a_data11             (sc2mac_dat_a_data11)
    ,.sc2mac_dat_a_data12             (sc2mac_dat_a_data12)
    ,.sc2mac_dat_a_data13             (sc2mac_dat_a_data13)
    ,.sc2mac_dat_a_data14             (sc2mac_dat_a_data14)
    ,.sc2mac_dat_a_data15             (sc2mac_dat_a_data15)
    ,.sc2mac_dat_a_data16             (sc2mac_dat_a_data16)
    ,.sc2mac_dat_a_data17             (sc2mac_dat_a_data17)
    ,.sc2mac_dat_a_data18             (sc2mac_dat_a_data18)
    ,.sc2mac_dat_a_data19             (sc2mac_dat_a_data19)
    ,.sc2mac_dat_a_data20             (sc2mac_dat_a_data20)
    ,.sc2mac_dat_a_data21             (sc2mac_dat_a_data21)
    ,.sc2mac_dat_a_data22             (sc2mac_dat_a_data22)
    ,.sc2mac_dat_a_data23             (sc2mac_dat_a_data23)
    ,.sc2mac_dat_a_data24             (sc2mac_dat_a_data24)
    ,.sc2mac_dat_a_data25             (sc2mac_dat_a_data25)
    ,.sc2mac_dat_a_data26             (sc2mac_dat_a_data26)
    ,.sc2mac_dat_a_data27             (sc2mac_dat_a_data27)
    ,.sc2mac_dat_a_data28             (sc2mac_dat_a_data28)
    ,.sc2mac_dat_a_data29             (sc2mac_dat_a_data29)
    ,.sc2mac_dat_a_data30             (sc2mac_dat_a_data30)
    ,.sc2mac_dat_a_data31             (sc2mac_dat_a_data31)
    ,.sc2mac_dat_a_data32             (sc2mac_dat_a_data32)
    ,.sc2mac_dat_a_data33             (sc2mac_dat_a_data33)
    ,.sc2mac_dat_a_data34             (sc2mac_dat_a_data34)
    ,.sc2mac_dat_a_data35             (sc2mac_dat_a_data35)
    ,.sc2mac_dat_a_data36             (sc2mac_dat_a_data36)
    ,.sc2mac_dat_a_data37             (sc2mac_dat_a_data37)
    ,.sc2mac_dat_a_data38             (sc2mac_dat_a_data38)
    ,.sc2mac_dat_a_data39             (sc2mac_dat_a_data39)
    ,.sc2mac_dat_a_data40             (sc2mac_dat_a_data40)
    ,.sc2mac_dat_a_data41             (sc2mac_dat_a_data41)
    ,.sc2mac_dat_a_data42             (sc2mac_dat_a_data42)
    ,.sc2mac_dat_a_data43             (sc2mac_dat_a_data43)
    ,.sc2mac_dat_a_data44             (sc2mac_dat_a_data44)
    ,.sc2mac_dat_a_data45             (sc2mac_dat_a_data45)
    ,.sc2mac_dat_a_data46             (sc2mac_dat_a_data46)
    ,.sc2mac_dat_a_data47             (sc2mac_dat_a_data47)
    ,.sc2mac_dat_a_data48             (sc2mac_dat_a_data48)
    ,.sc2mac_dat_a_data49             (sc2mac_dat_a_data49)
    ,.sc2mac_dat_a_data50             (sc2mac_dat_a_data50)
    ,.sc2mac_dat_a_data51             (sc2mac_dat_a_data51)
    ,.sc2mac_dat_a_data52             (sc2mac_dat_a_data52)
    ,.sc2mac_dat_a_data53             (sc2mac_dat_a_data53)
    ,.sc2mac_dat_a_data54             (sc2mac_dat_a_data54)
    ,.sc2mac_dat_a_data55             (sc2mac_dat_a_data55)
    ,.sc2mac_dat_a_data56             (sc2mac_dat_a_data56)
    ,.sc2mac_dat_a_data57             (sc2mac_dat_a_data57)
    ,.sc2mac_dat_a_data58             (sc2mac_dat_a_data58)
    ,.sc2mac_dat_a_data59             (sc2mac_dat_a_data59)
    ,.sc2mac_dat_a_data60             (sc2mac_dat_a_data60)
    ,.sc2mac_dat_a_data61             (sc2mac_dat_a_data61)
    ,.sc2mac_dat_a_data62             (sc2mac_dat_a_data62)
    ,.sc2mac_dat_a_data63             (sc2mac_dat_a_data63)
    ,.sc2mac_dat_a_data64             (sc2mac_dat_a_data64)
    ,.sc2mac_dat_a_data65             (sc2mac_dat_a_data65)
    ,.sc2mac_dat_a_data66             (sc2mac_dat_a_data66)
    ,.sc2mac_dat_a_data67             (sc2mac_dat_a_data67)
    ,.sc2mac_dat_a_data68             (sc2mac_dat_a_data68)
    ,.sc2mac_dat_a_data69             (sc2mac_dat_a_data69)
    ,.sc2mac_dat_a_data70             (sc2mac_dat_a_data70)
    ,.sc2mac_dat_a_data71             (sc2mac_dat_a_data71)
    ,.sc2mac_dat_a_data72             (sc2mac_dat_a_data72)
    ,.sc2mac_dat_a_data73             (sc2mac_dat_a_data73)
    ,.sc2mac_dat_a_data74             (sc2mac_dat_a_data74)
    ,.sc2mac_dat_a_data75             (sc2mac_dat_a_data75)
    ,.sc2mac_dat_a_data76             (sc2mac_dat_a_data76)
    ,.sc2mac_dat_a_data77             (sc2mac_dat_a_data77)
    ,.sc2mac_dat_a_data78             (sc2mac_dat_a_data78)
    ,.sc2mac_dat_a_data79             (sc2mac_dat_a_data79)
    ,.sc2mac_dat_a_data80             (sc2mac_dat_a_data80)
    ,.sc2mac_dat_a_data81             (sc2mac_dat_a_data81)
    ,.sc2mac_dat_a_data82             (sc2mac_dat_a_data82)
    ,.sc2mac_dat_a_data83             (sc2mac_dat_a_data83)
    ,.sc2mac_dat_a_data84             (sc2mac_dat_a_data84)
    ,.sc2mac_dat_a_data85             (sc2mac_dat_a_data85)
    ,.sc2mac_dat_a_data86             (sc2mac_dat_a_data86)
    ,.sc2mac_dat_a_data87             (sc2mac_dat_a_data87)
    ,.sc2mac_dat_a_data88             (sc2mac_dat_a_data88)
    ,.sc2mac_dat_a_data89             (sc2mac_dat_a_data89)
    ,.sc2mac_dat_a_data90             (sc2mac_dat_a_data90)
    ,.sc2mac_dat_a_data91             (sc2mac_dat_a_data91)
    ,.sc2mac_dat_a_data92             (sc2mac_dat_a_data92)
    ,.sc2mac_dat_a_data93             (sc2mac_dat_a_data93)
    ,.sc2mac_dat_a_data94             (sc2mac_dat_a_data94)
    ,.sc2mac_dat_a_data95             (sc2mac_dat_a_data95)
    ,.sc2mac_dat_a_data96             (sc2mac_dat_a_data96)
    ,.sc2mac_dat_a_data97             (sc2mac_dat_a_data97)
    ,.sc2mac_dat_a_data98             (sc2mac_dat_a_data98)
    ,.sc2mac_dat_a_data99             (sc2mac_dat_a_data99)
    ,.sc2mac_dat_a_data100            (sc2mac_dat_a_data100)
    ,.sc2mac_dat_a_data101            (sc2mac_dat_a_data101)
    ,.sc2mac_dat_a_data102            (sc2mac_dat_a_data102)
    ,.sc2mac_dat_a_data103            (sc2mac_dat_a_data103)
    ,.sc2mac_dat_a_data104            (sc2mac_dat_a_data104)
    ,.sc2mac_dat_a_data105            (sc2mac_dat_a_data105)
    ,.sc2mac_dat_a_data106            (sc2mac_dat_a_data106)
    ,.sc2mac_dat_a_data107            (sc2mac_dat_a_data107)
    ,.sc2mac_dat_a_data108            (sc2mac_dat_a_data108)
    ,.sc2mac_dat_a_data109            (sc2mac_dat_a_data109)
    ,.sc2mac_dat_a_data110            (sc2mac_dat_a_data110)
    ,.sc2mac_dat_a_data111            (sc2mac_dat_a_data111)
    ,.sc2mac_dat_a_data112            (sc2mac_dat_a_data112)
    ,.sc2mac_dat_a_data113            (sc2mac_dat_a_data113)
    ,.sc2mac_dat_a_data114            (sc2mac_dat_a_data114)
    ,.sc2mac_dat_a_data115            (sc2mac_dat_a_data115)
    ,.sc2mac_dat_a_data116            (sc2mac_dat_a_data116)
    ,.sc2mac_dat_a_data117            (sc2mac_dat_a_data117)
    ,.sc2mac_dat_a_data118            (sc2mac_dat_a_data118)
    ,.sc2mac_dat_a_data119            (sc2mac_dat_a_data119)
    ,.sc2mac_dat_a_data120            (sc2mac_dat_a_data120)
    ,.sc2mac_dat_a_data121            (sc2mac_dat_a_data121)
    ,.sc2mac_dat_a_data122            (sc2mac_dat_a_data122)
    ,.sc2mac_dat_a_data123            (sc2mac_dat_a_data123)
    ,.sc2mac_dat_a_data124            (sc2mac_dat_a_data124)
    ,.sc2mac_dat_a_data125            (sc2mac_dat_a_data125)
    ,.sc2mac_dat_a_data126            (sc2mac_dat_a_data126)
    ,.sc2mac_dat_a_data127            (sc2mac_dat_a_data127)
    ,.sc2mac_dat_a_pd                 (sc2mac_dat_a_pd)
    ,.sc2mac_dat_b_pvld               (sc2mac_dat_b_pvld)
    ,.sc2mac_dat_b_mask               (sc2mac_dat_b_mask)
    ,.sc2mac_dat_b_data0              (sc2mac_dat_b_data0)
    ,.sc2mac_dat_b_data1              (sc2mac_dat_b_data1)
    ,.sc2mac_dat_b_data2              (sc2mac_dat_b_data2)
    ,.sc2mac_dat_b_data3              (sc2mac_dat_b_data3)
    ,.sc2mac_dat_b_data4              (sc2mac_dat_b_data4)
    ,.sc2mac_dat_b_data5              (sc2mac_dat_b_data5)
    ,.sc2mac_dat_b_data6              (sc2mac_dat_b_data6)
    ,.sc2mac_dat_b_data7              (sc2mac_dat_b_data7)
    ,.sc2mac_dat_b_data8              (sc2mac_dat_b_data8)
    ,.sc2mac_dat_b_data9              (sc2mac_dat_b_data9)
    ,.sc2mac_dat_b_data10             (sc2mac_dat_b_data10)
    ,.sc2mac_dat_b_data11             (sc2mac_dat_b_data11)
    ,.sc2mac_dat_b_data12             (sc2mac_dat_b_data12)
    ,.sc2mac_dat_b_data13             (sc2mac_dat_b_data13)
    ,.sc2mac_dat_b_data14             (sc2mac_dat_b_data14)
    ,.sc2mac_dat_b_data15             (sc2mac_dat_b_data15)
    ,.sc2mac_dat_b_data16             (sc2mac_dat_b_data16)
    ,.sc2mac_dat_b_data17             (sc2mac_dat_b_data17)
    ,.sc2mac_dat_b_data18             (sc2mac_dat_b_data18)
    ,.sc2mac_dat_b_data19             (sc2mac_dat_b_data19)
    ,.sc2mac_dat_b_data20             (sc2mac_dat_b_data20)
    ,.sc2mac_dat_b_data21             (sc2mac_dat_b_data21)
    ,.sc2mac_dat_b_data22             (sc2mac_dat_b_data22)
    ,.sc2mac_dat_b_data23             (sc2mac_dat_b_data23)
    ,.sc2mac_dat_b_data24             (sc2mac_dat_b_data24)
    ,.sc2mac_dat_b_data25             (sc2mac_dat_b_data25)
    ,.sc2mac_dat_b_data26             (sc2mac_dat_b_data26)
    ,.sc2mac_dat_b_data27             (sc2mac_dat_b_data27)
    ,.sc2mac_dat_b_data28             (sc2mac_dat_b_data28)
    ,.sc2mac_dat_b_data29             (sc2mac_dat_b_data29)
    ,.sc2mac_dat_b_data30             (sc2mac_dat_b_data30)
    ,.sc2mac_dat_b_data31             (sc2mac_dat_b_data31)
    ,.sc2mac_dat_b_data32             (sc2mac_dat_b_data32)
    ,.sc2mac_dat_b_data33             (sc2mac_dat_b_data33)
    ,.sc2mac_dat_b_data34             (sc2mac_dat_b_data34)
    ,.sc2mac_dat_b_data35             (sc2mac_dat_b_data35)
    ,.sc2mac_dat_b_data36             (sc2mac_dat_b_data36)
    ,.sc2mac_dat_b_data37             (sc2mac_dat_b_data37)
    ,.sc2mac_dat_b_data38             (sc2mac_dat_b_data38)
    ,.sc2mac_dat_b_data39             (sc2mac_dat_b_data39)
    ,.sc2mac_dat_b_data40             (sc2mac_dat_b_data40)
    ,.sc2mac_dat_b_data41             (sc2mac_dat_b_data41)
    ,.sc2mac_dat_b_data42             (sc2mac_dat_b_data42)
    ,.sc2mac_dat_b_data43             (sc2mac_dat_b_data43)
    ,.sc2mac_dat_b_data44             (sc2mac_dat_b_data44)
    ,.sc2mac_dat_b_data45             (sc2mac_dat_b_data45)
    ,.sc2mac_dat_b_data46             (sc2mac_dat_b_data46)
    ,.sc2mac_dat_b_data47             (sc2mac_dat_b_data47)
    ,.sc2mac_dat_b_data48             (sc2mac_dat_b_data48)
    ,.sc2mac_dat_b_data49             (sc2mac_dat_b_data49)
    ,.sc2mac_dat_b_data50             (sc2mac_dat_b_data50)
    ,.sc2mac_dat_b_data51             (sc2mac_dat_b_data51)
    ,.sc2mac_dat_b_data52             (sc2mac_dat_b_data52)
    ,.sc2mac_dat_b_data53             (sc2mac_dat_b_data53)
    ,.sc2mac_dat_b_data54             (sc2mac_dat_b_data54)
    ,.sc2mac_dat_b_data55             (sc2mac_dat_b_data55)
    ,.sc2mac_dat_b_data56             (sc2mac_dat_b_data56)
    ,.sc2mac_dat_b_data57             (sc2mac_dat_b_data57)
    ,.sc2mac_dat_b_data58             (sc2mac_dat_b_data58)
    ,.sc2mac_dat_b_data59             (sc2mac_dat_b_data59)
    ,.sc2mac_dat_b_data60             (sc2mac_dat_b_data60)
    ,.sc2mac_dat_b_data61             (sc2mac_dat_b_data61)
    ,.sc2mac_dat_b_data62             (sc2mac_dat_b_data62)
    ,.sc2mac_dat_b_data63             (sc2mac_dat_b_data63)
    ,.sc2mac_dat_b_data64             (sc2mac_dat_b_data64)
    ,.sc2mac_dat_b_data65             (sc2mac_dat_b_data65)
    ,.sc2mac_dat_b_data66             (sc2mac_dat_b_data66)
    ,.sc2mac_dat_b_data67             (sc2mac_dat_b_data67)
    ,.sc2mac_dat_b_data68             (sc2mac_dat_b_data68)
    ,.sc2mac_dat_b_data69             (sc2mac_dat_b_data69)
    ,.sc2mac_dat_b_data70             (sc2mac_dat_b_data70)
    ,.sc2mac_dat_b_data71             (sc2mac_dat_b_data71)
    ,.sc2mac_dat_b_data72             (sc2mac_dat_b_data72)
    ,.sc2mac_dat_b_data73             (sc2mac_dat_b_data73)
    ,.sc2mac_dat_b_data74             (sc2mac_dat_b_data74)
    ,.sc2mac_dat_b_data75             (sc2mac_dat_b_data75)
    ,.sc2mac_dat_b_data76             (sc2mac_dat_b_data76)
    ,.sc2mac_dat_b_data77             (sc2mac_dat_b_data77)
    ,.sc2mac_dat_b_data78             (sc2mac_dat_b_data78)
    ,.sc2mac_dat_b_data79             (sc2mac_dat_b_data79)
    ,.sc2mac_dat_b_data80             (sc2mac_dat_b_data80)
    ,.sc2mac_dat_b_data81             (sc2mac_dat_b_data81)
    ,.sc2mac_dat_b_data82             (sc2mac_dat_b_data82)
    ,.sc2mac_dat_b_data83             (sc2mac_dat_b_data83)
    ,.sc2mac_dat_b_data84             (sc2mac_dat_b_data84)
    ,.sc2mac_dat_b_data85             (sc2mac_dat_b_data85)
    ,.sc2mac_dat_b_data86             (sc2mac_dat_b_data86)
    ,.sc2mac_dat_b_data87             (sc2mac_dat_b_data87)
    ,.sc2mac_dat_b_data88             (sc2mac_dat_b_data88)
    ,.sc2mac_dat_b_data89             (sc2mac_dat_b_data89)
    ,.sc2mac_dat_b_data90             (sc2mac_dat_b_data90)
    ,.sc2mac_dat_b_data91             (sc2mac_dat_b_data91)
    ,.sc2mac_dat_b_data92             (sc2mac_dat_b_data92)
    ,.sc2mac_dat_b_data93             (sc2mac_dat_b_data93)
    ,.sc2mac_dat_b_data94             (sc2mac_dat_b_data94)
    ,.sc2mac_dat_b_data95             (sc2mac_dat_b_data95)
    ,.sc2mac_dat_b_data96             (sc2mac_dat_b_data96)
    ,.sc2mac_dat_b_data97             (sc2mac_dat_b_data97)
    ,.sc2mac_dat_b_data98             (sc2mac_dat_b_data98)
    ,.sc2mac_dat_b_data99             (sc2mac_dat_b_data99)
    ,.sc2mac_dat_b_data100            (sc2mac_dat_b_data100)
    ,.sc2mac_dat_b_data101            (sc2mac_dat_b_data101)
    ,.sc2mac_dat_b_data102            (sc2mac_dat_b_data102)
    ,.sc2mac_dat_b_data103            (sc2mac_dat_b_data103)
    ,.sc2mac_dat_b_data104            (sc2mac_dat_b_data104)
    ,.sc2mac_dat_b_data105            (sc2mac_dat_b_data105)
    ,.sc2mac_dat_b_data106            (sc2mac_dat_b_data106)
    ,.sc2mac_dat_b_data107            (sc2mac_dat_b_data107)
    ,.sc2mac_dat_b_data108            (sc2mac_dat_b_data108)
    ,.sc2mac_dat_b_data109            (sc2mac_dat_b_data109)
    ,.sc2mac_dat_b_data110            (sc2mac_dat_b_data110)
    ,.sc2mac_dat_b_data111            (sc2mac_dat_b_data111)
    ,.sc2mac_dat_b_data112            (sc2mac_dat_b_data112)
    ,.sc2mac_dat_b_data113            (sc2mac_dat_b_data113)
    ,.sc2mac_dat_b_data114            (sc2mac_dat_b_data114)
    ,.sc2mac_dat_b_data115            (sc2mac_dat_b_data115)
    ,.sc2mac_dat_b_data116            (sc2mac_dat_b_data116)
    ,.sc2mac_dat_b_data117            (sc2mac_dat_b_data117)
    ,.sc2mac_dat_b_data118            (sc2mac_dat_b_data118)
    ,.sc2mac_dat_b_data119            (sc2mac_dat_b_data119)
    ,.sc2mac_dat_b_data120            (sc2mac_dat_b_data120)
    ,.sc2mac_dat_b_data121            (sc2mac_dat_b_data121)
    ,.sc2mac_dat_b_data122            (sc2mac_dat_b_data122)
    ,.sc2mac_dat_b_data123            (sc2mac_dat_b_data123)
    ,.sc2mac_dat_b_data124            (sc2mac_dat_b_data124)
    ,.sc2mac_dat_b_data125            (sc2mac_dat_b_data125)
    ,.sc2mac_dat_b_data126            (sc2mac_dat_b_data126)
    ,.sc2mac_dat_b_data127            (sc2mac_dat_b_data127)
    ,.sc2mac_dat_b_pd                 (sc2mac_dat_b_pd)
    ,.sc2mac_wt_a_pvld                (sc2mac_wt_a_pvld)
    ,.sc2mac_wt_a_mask                (sc2mac_wt_a_mask)
    ,.sc2mac_wt_a_data0               (sc2mac_wt_a_data0)
    ,.sc2mac_wt_a_data1               (sc2mac_wt_a_data1)
    ,.sc2mac_wt_a_data2               (sc2mac_wt_a_data2)
    ,.sc2mac_wt_a_data3               (sc2mac_wt_a_data3)
    ,.sc2mac_wt_a_data4               (sc2mac_wt_a_data4)
    ,.sc2mac_wt_a_data5               (sc2mac_wt_a_data5)
    ,.sc2mac_wt_a_data6               (sc2mac_wt_a_data6)
    ,.sc2mac_wt_a_data7               (sc2mac_wt_a_data7)
    ,.sc2mac_wt_a_data8               (sc2mac_wt_a_data8)
    ,.sc2mac_wt_a_data9               (sc2mac_wt_a_data9)
    ,.sc2mac_wt_a_data10              (sc2mac_wt_a_data10)
    ,.sc2mac_wt_a_data11              (sc2mac_wt_a_data11)
    ,.sc2mac_wt_a_data12              (sc2mac_wt_a_data12)
    ,.sc2mac_wt_a_data13              (sc2mac_wt_a_data13)
    ,.sc2mac_wt_a_data14              (sc2mac_wt_a_data14)
    ,.sc2mac_wt_a_data15              (sc2mac_wt_a_data15)
    ,.sc2mac_wt_a_data16              (sc2mac_wt_a_data16)
    ,.sc2mac_wt_a_data17              (sc2mac_wt_a_data17)
    ,.sc2mac_wt_a_data18              (sc2mac_wt_a_data18)
    ,.sc2mac_wt_a_data19              (sc2mac_wt_a_data19)
    ,.sc2mac_wt_a_data20              (sc2mac_wt_a_data20)
    ,.sc2mac_wt_a_data21              (sc2mac_wt_a_data21)
    ,.sc2mac_wt_a_data22              (sc2mac_wt_a_data22)
    ,.sc2mac_wt_a_data23              (sc2mac_wt_a_data23)
    ,.sc2mac_wt_a_data24              (sc2mac_wt_a_data24)
    ,.sc2mac_wt_a_data25              (sc2mac_wt_a_data25)
    ,.sc2mac_wt_a_data26              (sc2mac_wt_a_data26)
    ,.sc2mac_wt_a_data27              (sc2mac_wt_a_data27)
    ,.sc2mac_wt_a_data28              (sc2mac_wt_a_data28)
    ,.sc2mac_wt_a_data29              (sc2mac_wt_a_data29)
    ,.sc2mac_wt_a_data30              (sc2mac_wt_a_data30)
    ,.sc2mac_wt_a_data31              (sc2mac_wt_a_data31)
    ,.sc2mac_wt_a_data32              (sc2mac_wt_a_data32)
    ,.sc2mac_wt_a_data33              (sc2mac_wt_a_data33)
    ,.sc2mac_wt_a_data34              (sc2mac_wt_a_data34)
    ,.sc2mac_wt_a_data35              (sc2mac_wt_a_data35)
    ,.sc2mac_wt_a_data36              (sc2mac_wt_a_data36)
    ,.sc2mac_wt_a_data37              (sc2mac_wt_a_data37)
    ,.sc2mac_wt_a_data38              (sc2mac_wt_a_data38)
    ,.sc2mac_wt_a_data39              (sc2mac_wt_a_data39)
    ,.sc2mac_wt_a_data40              (sc2mac_wt_a_data40)
    ,.sc2mac_wt_a_data41              (sc2mac_wt_a_data41)
    ,.sc2mac_wt_a_data42              (sc2mac_wt_a_data42)
    ,.sc2mac_wt_a_data43              (sc2mac_wt_a_data43)
    ,.sc2mac_wt_a_data44              (sc2mac_wt_a_data44)
    ,.sc2mac_wt_a_data45              (sc2mac_wt_a_data45)
    ,.sc2mac_wt_a_data46              (sc2mac_wt_a_data46)
    ,.sc2mac_wt_a_data47              (sc2mac_wt_a_data47)
    ,.sc2mac_wt_a_data48              (sc2mac_wt_a_data48)
    ,.sc2mac_wt_a_data49              (sc2mac_wt_a_data49)
    ,.sc2mac_wt_a_data50              (sc2mac_wt_a_data50)
    ,.sc2mac_wt_a_data51              (sc2mac_wt_a_data51)
    ,.sc2mac_wt_a_data52              (sc2mac_wt_a_data52)
    ,.sc2mac_wt_a_data53              (sc2mac_wt_a_data53)
    ,.sc2mac_wt_a_data54              (sc2mac_wt_a_data54)
    ,.sc2mac_wt_a_data55              (sc2mac_wt_a_data55)
    ,.sc2mac_wt_a_data56              (sc2mac_wt_a_data56)
    ,.sc2mac_wt_a_data57              (sc2mac_wt_a_data57)
    ,.sc2mac_wt_a_data58              (sc2mac_wt_a_data58)
    ,.sc2mac_wt_a_data59              (sc2mac_wt_a_data59)
    ,.sc2mac_wt_a_data60              (sc2mac_wt_a_data60)
    ,.sc2mac_wt_a_data61              (sc2mac_wt_a_data61)
    ,.sc2mac_wt_a_data62              (sc2mac_wt_a_data62)
    ,.sc2mac_wt_a_data63              (sc2mac_wt_a_data63)
    ,.sc2mac_wt_a_data64              (sc2mac_wt_a_data64)
    ,.sc2mac_wt_a_data65              (sc2mac_wt_a_data65)
    ,.sc2mac_wt_a_data66              (sc2mac_wt_a_data66)
    ,.sc2mac_wt_a_data67              (sc2mac_wt_a_data67)
    ,.sc2mac_wt_a_data68              (sc2mac_wt_a_data68)
    ,.sc2mac_wt_a_data69              (sc2mac_wt_a_data69)
    ,.sc2mac_wt_a_data70              (sc2mac_wt_a_data70)
    ,.sc2mac_wt_a_data71              (sc2mac_wt_a_data71)
    ,.sc2mac_wt_a_data72              (sc2mac_wt_a_data72)
    ,.sc2mac_wt_a_data73              (sc2mac_wt_a_data73)
    ,.sc2mac_wt_a_data74              (sc2mac_wt_a_data74)
    ,.sc2mac_wt_a_data75              (sc2mac_wt_a_data75)
    ,.sc2mac_wt_a_data76              (sc2mac_wt_a_data76)
    ,.sc2mac_wt_a_data77              (sc2mac_wt_a_data77)
    ,.sc2mac_wt_a_data78              (sc2mac_wt_a_data78)
    ,.sc2mac_wt_a_data79              (sc2mac_wt_a_data79)
    ,.sc2mac_wt_a_data80              (sc2mac_wt_a_data80)
    ,.sc2mac_wt_a_data81              (sc2mac_wt_a_data81)
    ,.sc2mac_wt_a_data82              (sc2mac_wt_a_data82)
    ,.sc2mac_wt_a_data83              (sc2mac_wt_a_data83)
    ,.sc2mac_wt_a_data84              (sc2mac_wt_a_data84)
    ,.sc2mac_wt_a_data85              (sc2mac_wt_a_data85)
    ,.sc2mac_wt_a_data86              (sc2mac_wt_a_data86)
    ,.sc2mac_wt_a_data87              (sc2mac_wt_a_data87)
    ,.sc2mac_wt_a_data88              (sc2mac_wt_a_data88)
    ,.sc2mac_wt_a_data89              (sc2mac_wt_a_data89)
    ,.sc2mac_wt_a_data90              (sc2mac_wt_a_data90)
    ,.sc2mac_wt_a_data91              (sc2mac_wt_a_data91)
    ,.sc2mac_wt_a_data92              (sc2mac_wt_a_data92)
    ,.sc2mac_wt_a_data93              (sc2mac_wt_a_data93)
    ,.sc2mac_wt_a_data94              (sc2mac_wt_a_data94)
    ,.sc2mac_wt_a_data95              (sc2mac_wt_a_data95)
    ,.sc2mac_wt_a_data96              (sc2mac_wt_a_data96)
    ,.sc2mac_wt_a_data97              (sc2mac_wt_a_data97)
    ,.sc2mac_wt_a_data98              (sc2mac_wt_a_data98)
    ,.sc2mac_wt_a_data99              (sc2mac_wt_a_data99)
    ,.sc2mac_wt_a_data100             (sc2mac_wt_a_data100)
    ,.sc2mac_wt_a_data101             (sc2mac_wt_a_data101)
    ,.sc2mac_wt_a_data102             (sc2mac_wt_a_data102)
    ,.sc2mac_wt_a_data103             (sc2mac_wt_a_data103)
    ,.sc2mac_wt_a_data104             (sc2mac_wt_a_data104)
    ,.sc2mac_wt_a_data105             (sc2mac_wt_a_data105)
    ,.sc2mac_wt_a_data106             (sc2mac_wt_a_data106)
    ,.sc2mac_wt_a_data107             (sc2mac_wt_a_data107)
    ,.sc2mac_wt_a_data108             (sc2mac_wt_a_data108)
    ,.sc2mac_wt_a_data109             (sc2mac_wt_a_data109)
    ,.sc2mac_wt_a_data110             (sc2mac_wt_a_data110)
    ,.sc2mac_wt_a_data111             (sc2mac_wt_a_data111)
    ,.sc2mac_wt_a_data112             (sc2mac_wt_a_data112)
    ,.sc2mac_wt_a_data113             (sc2mac_wt_a_data113)
    ,.sc2mac_wt_a_data114             (sc2mac_wt_a_data114)
    ,.sc2mac_wt_a_data115             (sc2mac_wt_a_data115)
    ,.sc2mac_wt_a_data116             (sc2mac_wt_a_data116)
    ,.sc2mac_wt_a_data117             (sc2mac_wt_a_data117)
    ,.sc2mac_wt_a_data118             (sc2mac_wt_a_data118)
    ,.sc2mac_wt_a_data119             (sc2mac_wt_a_data119)
    ,.sc2mac_wt_a_data120             (sc2mac_wt_a_data120)
    ,.sc2mac_wt_a_data121             (sc2mac_wt_a_data121)
    ,.sc2mac_wt_a_data122             (sc2mac_wt_a_data122)
    ,.sc2mac_wt_a_data123             (sc2mac_wt_a_data123)
    ,.sc2mac_wt_a_data124             (sc2mac_wt_a_data124)
    ,.sc2mac_wt_a_data125             (sc2mac_wt_a_data125)
    ,.sc2mac_wt_a_data126             (sc2mac_wt_a_data126)
    ,.sc2mac_wt_a_data127             (sc2mac_wt_a_data127)
    ,.sc2mac_wt_a_sel                 (sc2mac_wt_a_sel)
    ,.sc2mac_wt_b_pvld                (sc2mac_wt_b_pvld)
    ,.sc2mac_wt_b_mask                (sc2mac_wt_b_mask)
    ,.sc2mac_wt_b_data0               (sc2mac_wt_b_data0)
    ,.sc2mac_wt_b_data1               (sc2mac_wt_b_data1)
    ,.sc2mac_wt_b_data2               (sc2mac_wt_b_data2)
    ,.sc2mac_wt_b_data3               (sc2mac_wt_b_data3)
    ,.sc2mac_wt_b_data4               (sc2mac_wt_b_data4)
    ,.sc2mac_wt_b_data5               (sc2mac_wt_b_data5)
    ,.sc2mac_wt_b_data6               (sc2mac_wt_b_data6)
    ,.sc2mac_wt_b_data7               (sc2mac_wt_b_data7)
    ,.sc2mac_wt_b_data8               (sc2mac_wt_b_data8)
    ,.sc2mac_wt_b_data9               (sc2mac_wt_b_data9)
    ,.sc2mac_wt_b_data10              (sc2mac_wt_b_data10)
    ,.sc2mac_wt_b_data11              (sc2mac_wt_b_data11)
    ,.sc2mac_wt_b_data12              (sc2mac_wt_b_data12)
    ,.sc2mac_wt_b_data13              (sc2mac_wt_b_data13)
    ,.sc2mac_wt_b_data14              (sc2mac_wt_b_data14)
    ,.sc2mac_wt_b_data15              (sc2mac_wt_b_data15)
    ,.sc2mac_wt_b_data16              (sc2mac_wt_b_data16)
    ,.sc2mac_wt_b_data17              (sc2mac_wt_b_data17)
    ,.sc2mac_wt_b_data18              (sc2mac_wt_b_data18)
    ,.sc2mac_wt_b_data19              (sc2mac_wt_b_data19)
    ,.sc2mac_wt_b_data20              (sc2mac_wt_b_data20)
    ,.sc2mac_wt_b_data21              (sc2mac_wt_b_data21)
    ,.sc2mac_wt_b_data22              (sc2mac_wt_b_data22)
    ,.sc2mac_wt_b_data23              (sc2mac_wt_b_data23)
    ,.sc2mac_wt_b_data24              (sc2mac_wt_b_data24)
    ,.sc2mac_wt_b_data25              (sc2mac_wt_b_data25)
    ,.sc2mac_wt_b_data26              (sc2mac_wt_b_data26)
    ,.sc2mac_wt_b_data27              (sc2mac_wt_b_data27)
    ,.sc2mac_wt_b_data28              (sc2mac_wt_b_data28)
    ,.sc2mac_wt_b_data29              (sc2mac_wt_b_data29)
    ,.sc2mac_wt_b_data30              (sc2mac_wt_b_data30)
    ,.sc2mac_wt_b_data31              (sc2mac_wt_b_data31)
    ,.sc2mac_wt_b_data32              (sc2mac_wt_b_data32)
    ,.sc2mac_wt_b_data33              (sc2mac_wt_b_data33)
    ,.sc2mac_wt_b_data34              (sc2mac_wt_b_data34)
    ,.sc2mac_wt_b_data35              (sc2mac_wt_b_data35)
    ,.sc2mac_wt_b_data36              (sc2mac_wt_b_data36)
    ,.sc2mac_wt_b_data37              (sc2mac_wt_b_data37)
    ,.sc2mac_wt_b_data38              (sc2mac_wt_b_data38)
    ,.sc2mac_wt_b_data39              (sc2mac_wt_b_data39)
    ,.sc2mac_wt_b_data40              (sc2mac_wt_b_data40)
    ,.sc2mac_wt_b_data41              (sc2mac_wt_b_data41)
    ,.sc2mac_wt_b_data42              (sc2mac_wt_b_data42)
    ,.sc2mac_wt_b_data43              (sc2mac_wt_b_data43)
    ,.sc2mac_wt_b_data44              (sc2mac_wt_b_data44)
    ,.sc2mac_wt_b_data45              (sc2mac_wt_b_data45)
    ,.sc2mac_wt_b_data46              (sc2mac_wt_b_data46)
    ,.sc2mac_wt_b_data47              (sc2mac_wt_b_data47)
    ,.sc2mac_wt_b_data48              (sc2mac_wt_b_data48)
    ,.sc2mac_wt_b_data49              (sc2mac_wt_b_data49)
    ,.sc2mac_wt_b_data50              (sc2mac_wt_b_data50)
    ,.sc2mac_wt_b_data51              (sc2mac_wt_b_data51)
    ,.sc2mac_wt_b_data52              (sc2mac_wt_b_data52)
    ,.sc2mac_wt_b_data53              (sc2mac_wt_b_data53)
    ,.sc2mac_wt_b_data54              (sc2mac_wt_b_data54)
    ,.sc2mac_wt_b_data55              (sc2mac_wt_b_data55)
    ,.sc2mac_wt_b_data56              (sc2mac_wt_b_data56)
    ,.sc2mac_wt_b_data57              (sc2mac_wt_b_data57)
    ,.sc2mac_wt_b_data58              (sc2mac_wt_b_data58)
    ,.sc2mac_wt_b_data59              (sc2mac_wt_b_data59)
    ,.sc2mac_wt_b_data60              (sc2mac_wt_b_data60)
    ,.sc2mac_wt_b_data61              (sc2mac_wt_b_data61)
    ,.sc2mac_wt_b_data62              (sc2mac_wt_b_data62)
    ,.sc2mac_wt_b_data63              (sc2mac_wt_b_data63)
    ,.sc2mac_wt_b_data64              (sc2mac_wt_b_data64)
    ,.sc2mac_wt_b_data65              (sc2mac_wt_b_data65)
    ,.sc2mac_wt_b_data66              (sc2mac_wt_b_data66)
    ,.sc2mac_wt_b_data67              (sc2mac_wt_b_data67)
    ,.sc2mac_wt_b_data68              (sc2mac_wt_b_data68)
    ,.sc2mac_wt_b_data69              (sc2mac_wt_b_data69)
    ,.sc2mac_wt_b_data70              (sc2mac_wt_b_data70)
    ,.sc2mac_wt_b_data71              (sc2mac_wt_b_data71)
    ,.sc2mac_wt_b_data72              (sc2mac_wt_b_data72)
    ,.sc2mac_wt_b_data73              (sc2mac_wt_b_data73)
    ,.sc2mac_wt_b_data74              (sc2mac_wt_b_data74)
    ,.sc2mac_wt_b_data75              (sc2mac_wt_b_data75)
    ,.sc2mac_wt_b_data76              (sc2mac_wt_b_data76)
    ,.sc2mac_wt_b_data77              (sc2mac_wt_b_data77)
    ,.sc2mac_wt_b_data78              (sc2mac_wt_b_data78)
    ,.sc2mac_wt_b_data79              (sc2mac_wt_b_data79)
    ,.sc2mac_wt_b_data80              (sc2mac_wt_b_data80)
    ,.sc2mac_wt_b_data81              (sc2mac_wt_b_data81)
    ,.sc2mac_wt_b_data82              (sc2mac_wt_b_data82)
    ,.sc2mac_wt_b_data83              (sc2mac_wt_b_data83)
    ,.sc2mac_wt_b_data84              (sc2mac_wt_b_data84)
    ,.sc2mac_wt_b_data85              (sc2mac_wt_b_data85)
    ,.sc2mac_wt_b_data86              (sc2mac_wt_b_data86)
    ,.sc2mac_wt_b_data87              (sc2mac_wt_b_data87)
    ,.sc2mac_wt_b_data88              (sc2mac_wt_b_data88)
    ,.sc2mac_wt_b_data89              (sc2mac_wt_b_data89)
    ,.sc2mac_wt_b_data90              (sc2mac_wt_b_data90)
    ,.sc2mac_wt_b_data91              (sc2mac_wt_b_data91)
    ,.sc2mac_wt_b_data92              (sc2mac_wt_b_data92)
    ,.sc2mac_wt_b_data93              (sc2mac_wt_b_data93)
    ,.sc2mac_wt_b_data94              (sc2mac_wt_b_data94)
    ,.sc2mac_wt_b_data95              (sc2mac_wt_b_data95)
    ,.sc2mac_wt_b_data96              (sc2mac_wt_b_data96)
    ,.sc2mac_wt_b_data97              (sc2mac_wt_b_data97)
    ,.sc2mac_wt_b_data98              (sc2mac_wt_b_data98)
    ,.sc2mac_wt_b_data99              (sc2mac_wt_b_data99)
    ,.sc2mac_wt_b_data100             (sc2mac_wt_b_data100)
    ,.sc2mac_wt_b_data101             (sc2mac_wt_b_data101)
    ,.sc2mac_wt_b_data102             (sc2mac_wt_b_data102)
    ,.sc2mac_wt_b_data103             (sc2mac_wt_b_data103)
    ,.sc2mac_wt_b_data104             (sc2mac_wt_b_data104)
    ,.sc2mac_wt_b_data105             (sc2mac_wt_b_data105)
    ,.sc2mac_wt_b_data106             (sc2mac_wt_b_data106)
    ,.sc2mac_wt_b_data107             (sc2mac_wt_b_data107)
    ,.sc2mac_wt_b_data108             (sc2mac_wt_b_data108)
    ,.sc2mac_wt_b_data109             (sc2mac_wt_b_data109)
    ,.sc2mac_wt_b_data110             (sc2mac_wt_b_data110)
    ,.sc2mac_wt_b_data111             (sc2mac_wt_b_data111)
    ,.sc2mac_wt_b_data112             (sc2mac_wt_b_data112)
    ,.sc2mac_wt_b_data113             (sc2mac_wt_b_data113)
    ,.sc2mac_wt_b_data114             (sc2mac_wt_b_data114)
    ,.sc2mac_wt_b_data115             (sc2mac_wt_b_data115)
    ,.sc2mac_wt_b_data116             (sc2mac_wt_b_data116)
    ,.sc2mac_wt_b_data117             (sc2mac_wt_b_data117)
    ,.sc2mac_wt_b_data118             (sc2mac_wt_b_data118)
    ,.sc2mac_wt_b_data119             (sc2mac_wt_b_data119)
    ,.sc2mac_wt_b_data120             (sc2mac_wt_b_data120)
    ,.sc2mac_wt_b_data121             (sc2mac_wt_b_data121)
    ,.sc2mac_wt_b_data122             (sc2mac_wt_b_data122)
    ,.sc2mac_wt_b_data123             (sc2mac_wt_b_data123)
    ,.sc2mac_wt_b_data124             (sc2mac_wt_b_data124)
    ,.sc2mac_wt_b_data125             (sc2mac_wt_b_data125)
    ,.sc2mac_wt_b_data126             (sc2mac_wt_b_data126)
    ,.sc2mac_wt_b_data127             (sc2mac_wt_b_data127)
    ,.sc2mac_wt_b_sel                 (sc2mac_wt_b_sel)
    ,.cdma2sc_wt_updt                 (u_cs_if.cdma2sc_wt_updt)
    ,.cdma2sc_wt_kernels              (u_cs_if.cdma2sc_wt_kernels)
    ,.cdma2sc_wt_entries              (u_cs_if.cdma2sc_wt_entries)
    ,.cdma2sc_wmb_entries             (u_cs_if.cdma2sc_wmb_entries)
    ,.sc2cdma_wt_updt                 (sc2cdma_wt_updt)
    ,.sc2cdma_wt_kernels              (sc2cdma_wt_kernels)
    ,.sc2cdma_wt_entries              (sc2cdma_wt_entries)
    ,.sc2cdma_wmb_entries             (sc2cdma_wmb_entries)
    ,.dla_clk_ovr_on_sync             (1'b0)
    ,.global_clk_ovr_on_sync          (1'b0)
    ,.tmc2slcg_disable_clock_gating   (1'b1)
  );

  // ---------------- RT：csc->cmac 打拍（a 例在 partition_o、b 例在 c） ----
  NV_NVDLA_RT_csc2cmac_a u_NV_NVDLA_RT_csc2cmac_a (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.sc2mac_wt_src_pvld              (sc2mac_wt_a_pvld)
    ,.sc2mac_wt_src_mask              (sc2mac_wt_a_mask)
    ,.sc2mac_wt_src_data0             (sc2mac_wt_a_data0)
    ,.sc2mac_wt_src_data1             (sc2mac_wt_a_data1)
    ,.sc2mac_wt_src_data2             (sc2mac_wt_a_data2)
    ,.sc2mac_wt_src_data3             (sc2mac_wt_a_data3)
    ,.sc2mac_wt_src_data4             (sc2mac_wt_a_data4)
    ,.sc2mac_wt_src_data5             (sc2mac_wt_a_data5)
    ,.sc2mac_wt_src_data6             (sc2mac_wt_a_data6)
    ,.sc2mac_wt_src_data7             (sc2mac_wt_a_data7)
    ,.sc2mac_wt_src_data8             (sc2mac_wt_a_data8)
    ,.sc2mac_wt_src_data9             (sc2mac_wt_a_data9)
    ,.sc2mac_wt_src_data10            (sc2mac_wt_a_data10)
    ,.sc2mac_wt_src_data11            (sc2mac_wt_a_data11)
    ,.sc2mac_wt_src_data12            (sc2mac_wt_a_data12)
    ,.sc2mac_wt_src_data13            (sc2mac_wt_a_data13)
    ,.sc2mac_wt_src_data14            (sc2mac_wt_a_data14)
    ,.sc2mac_wt_src_data15            (sc2mac_wt_a_data15)
    ,.sc2mac_wt_src_data16            (sc2mac_wt_a_data16)
    ,.sc2mac_wt_src_data17            (sc2mac_wt_a_data17)
    ,.sc2mac_wt_src_data18            (sc2mac_wt_a_data18)
    ,.sc2mac_wt_src_data19            (sc2mac_wt_a_data19)
    ,.sc2mac_wt_src_data20            (sc2mac_wt_a_data20)
    ,.sc2mac_wt_src_data21            (sc2mac_wt_a_data21)
    ,.sc2mac_wt_src_data22            (sc2mac_wt_a_data22)
    ,.sc2mac_wt_src_data23            (sc2mac_wt_a_data23)
    ,.sc2mac_wt_src_data24            (sc2mac_wt_a_data24)
    ,.sc2mac_wt_src_data25            (sc2mac_wt_a_data25)
    ,.sc2mac_wt_src_data26            (sc2mac_wt_a_data26)
    ,.sc2mac_wt_src_data27            (sc2mac_wt_a_data27)
    ,.sc2mac_wt_src_data28            (sc2mac_wt_a_data28)
    ,.sc2mac_wt_src_data29            (sc2mac_wt_a_data29)
    ,.sc2mac_wt_src_data30            (sc2mac_wt_a_data30)
    ,.sc2mac_wt_src_data31            (sc2mac_wt_a_data31)
    ,.sc2mac_wt_src_data32            (sc2mac_wt_a_data32)
    ,.sc2mac_wt_src_data33            (sc2mac_wt_a_data33)
    ,.sc2mac_wt_src_data34            (sc2mac_wt_a_data34)
    ,.sc2mac_wt_src_data35            (sc2mac_wt_a_data35)
    ,.sc2mac_wt_src_data36            (sc2mac_wt_a_data36)
    ,.sc2mac_wt_src_data37            (sc2mac_wt_a_data37)
    ,.sc2mac_wt_src_data38            (sc2mac_wt_a_data38)
    ,.sc2mac_wt_src_data39            (sc2mac_wt_a_data39)
    ,.sc2mac_wt_src_data40            (sc2mac_wt_a_data40)
    ,.sc2mac_wt_src_data41            (sc2mac_wt_a_data41)
    ,.sc2mac_wt_src_data42            (sc2mac_wt_a_data42)
    ,.sc2mac_wt_src_data43            (sc2mac_wt_a_data43)
    ,.sc2mac_wt_src_data44            (sc2mac_wt_a_data44)
    ,.sc2mac_wt_src_data45            (sc2mac_wt_a_data45)
    ,.sc2mac_wt_src_data46            (sc2mac_wt_a_data46)
    ,.sc2mac_wt_src_data47            (sc2mac_wt_a_data47)
    ,.sc2mac_wt_src_data48            (sc2mac_wt_a_data48)
    ,.sc2mac_wt_src_data49            (sc2mac_wt_a_data49)
    ,.sc2mac_wt_src_data50            (sc2mac_wt_a_data50)
    ,.sc2mac_wt_src_data51            (sc2mac_wt_a_data51)
    ,.sc2mac_wt_src_data52            (sc2mac_wt_a_data52)
    ,.sc2mac_wt_src_data53            (sc2mac_wt_a_data53)
    ,.sc2mac_wt_src_data54            (sc2mac_wt_a_data54)
    ,.sc2mac_wt_src_data55            (sc2mac_wt_a_data55)
    ,.sc2mac_wt_src_data56            (sc2mac_wt_a_data56)
    ,.sc2mac_wt_src_data57            (sc2mac_wt_a_data57)
    ,.sc2mac_wt_src_data58            (sc2mac_wt_a_data58)
    ,.sc2mac_wt_src_data59            (sc2mac_wt_a_data59)
    ,.sc2mac_wt_src_data60            (sc2mac_wt_a_data60)
    ,.sc2mac_wt_src_data61            (sc2mac_wt_a_data61)
    ,.sc2mac_wt_src_data62            (sc2mac_wt_a_data62)
    ,.sc2mac_wt_src_data63            (sc2mac_wt_a_data63)
    ,.sc2mac_wt_src_data64            (sc2mac_wt_a_data64)
    ,.sc2mac_wt_src_data65            (sc2mac_wt_a_data65)
    ,.sc2mac_wt_src_data66            (sc2mac_wt_a_data66)
    ,.sc2mac_wt_src_data67            (sc2mac_wt_a_data67)
    ,.sc2mac_wt_src_data68            (sc2mac_wt_a_data68)
    ,.sc2mac_wt_src_data69            (sc2mac_wt_a_data69)
    ,.sc2mac_wt_src_data70            (sc2mac_wt_a_data70)
    ,.sc2mac_wt_src_data71            (sc2mac_wt_a_data71)
    ,.sc2mac_wt_src_data72            (sc2mac_wt_a_data72)
    ,.sc2mac_wt_src_data73            (sc2mac_wt_a_data73)
    ,.sc2mac_wt_src_data74            (sc2mac_wt_a_data74)
    ,.sc2mac_wt_src_data75            (sc2mac_wt_a_data75)
    ,.sc2mac_wt_src_data76            (sc2mac_wt_a_data76)
    ,.sc2mac_wt_src_data77            (sc2mac_wt_a_data77)
    ,.sc2mac_wt_src_data78            (sc2mac_wt_a_data78)
    ,.sc2mac_wt_src_data79            (sc2mac_wt_a_data79)
    ,.sc2mac_wt_src_data80            (sc2mac_wt_a_data80)
    ,.sc2mac_wt_src_data81            (sc2mac_wt_a_data81)
    ,.sc2mac_wt_src_data82            (sc2mac_wt_a_data82)
    ,.sc2mac_wt_src_data83            (sc2mac_wt_a_data83)
    ,.sc2mac_wt_src_data84            (sc2mac_wt_a_data84)
    ,.sc2mac_wt_src_data85            (sc2mac_wt_a_data85)
    ,.sc2mac_wt_src_data86            (sc2mac_wt_a_data86)
    ,.sc2mac_wt_src_data87            (sc2mac_wt_a_data87)
    ,.sc2mac_wt_src_data88            (sc2mac_wt_a_data88)
    ,.sc2mac_wt_src_data89            (sc2mac_wt_a_data89)
    ,.sc2mac_wt_src_data90            (sc2mac_wt_a_data90)
    ,.sc2mac_wt_src_data91            (sc2mac_wt_a_data91)
    ,.sc2mac_wt_src_data92            (sc2mac_wt_a_data92)
    ,.sc2mac_wt_src_data93            (sc2mac_wt_a_data93)
    ,.sc2mac_wt_src_data94            (sc2mac_wt_a_data94)
    ,.sc2mac_wt_src_data95            (sc2mac_wt_a_data95)
    ,.sc2mac_wt_src_data96            (sc2mac_wt_a_data96)
    ,.sc2mac_wt_src_data97            (sc2mac_wt_a_data97)
    ,.sc2mac_wt_src_data98            (sc2mac_wt_a_data98)
    ,.sc2mac_wt_src_data99            (sc2mac_wt_a_data99)
    ,.sc2mac_wt_src_data100           (sc2mac_wt_a_data100)
    ,.sc2mac_wt_src_data101           (sc2mac_wt_a_data101)
    ,.sc2mac_wt_src_data102           (sc2mac_wt_a_data102)
    ,.sc2mac_wt_src_data103           (sc2mac_wt_a_data103)
    ,.sc2mac_wt_src_data104           (sc2mac_wt_a_data104)
    ,.sc2mac_wt_src_data105           (sc2mac_wt_a_data105)
    ,.sc2mac_wt_src_data106           (sc2mac_wt_a_data106)
    ,.sc2mac_wt_src_data107           (sc2mac_wt_a_data107)
    ,.sc2mac_wt_src_data108           (sc2mac_wt_a_data108)
    ,.sc2mac_wt_src_data109           (sc2mac_wt_a_data109)
    ,.sc2mac_wt_src_data110           (sc2mac_wt_a_data110)
    ,.sc2mac_wt_src_data111           (sc2mac_wt_a_data111)
    ,.sc2mac_wt_src_data112           (sc2mac_wt_a_data112)
    ,.sc2mac_wt_src_data113           (sc2mac_wt_a_data113)
    ,.sc2mac_wt_src_data114           (sc2mac_wt_a_data114)
    ,.sc2mac_wt_src_data115           (sc2mac_wt_a_data115)
    ,.sc2mac_wt_src_data116           (sc2mac_wt_a_data116)
    ,.sc2mac_wt_src_data117           (sc2mac_wt_a_data117)
    ,.sc2mac_wt_src_data118           (sc2mac_wt_a_data118)
    ,.sc2mac_wt_src_data119           (sc2mac_wt_a_data119)
    ,.sc2mac_wt_src_data120           (sc2mac_wt_a_data120)
    ,.sc2mac_wt_src_data121           (sc2mac_wt_a_data121)
    ,.sc2mac_wt_src_data122           (sc2mac_wt_a_data122)
    ,.sc2mac_wt_src_data123           (sc2mac_wt_a_data123)
    ,.sc2mac_wt_src_data124           (sc2mac_wt_a_data124)
    ,.sc2mac_wt_src_data125           (sc2mac_wt_a_data125)
    ,.sc2mac_wt_src_data126           (sc2mac_wt_a_data126)
    ,.sc2mac_wt_src_data127           (sc2mac_wt_a_data127)
    ,.sc2mac_wt_src_sel               (sc2mac_wt_a_sel)
    ,.sc2mac_dat_src_pvld             (sc2mac_dat_a_pvld)
    ,.sc2mac_dat_src_mask             (sc2mac_dat_a_mask)
    ,.sc2mac_dat_src_data0            (sc2mac_dat_a_data0)
    ,.sc2mac_dat_src_data1            (sc2mac_dat_a_data1)
    ,.sc2mac_dat_src_data2            (sc2mac_dat_a_data2)
    ,.sc2mac_dat_src_data3            (sc2mac_dat_a_data3)
    ,.sc2mac_dat_src_data4            (sc2mac_dat_a_data4)
    ,.sc2mac_dat_src_data5            (sc2mac_dat_a_data5)
    ,.sc2mac_dat_src_data6            (sc2mac_dat_a_data6)
    ,.sc2mac_dat_src_data7            (sc2mac_dat_a_data7)
    ,.sc2mac_dat_src_data8            (sc2mac_dat_a_data8)
    ,.sc2mac_dat_src_data9            (sc2mac_dat_a_data9)
    ,.sc2mac_dat_src_data10           (sc2mac_dat_a_data10)
    ,.sc2mac_dat_src_data11           (sc2mac_dat_a_data11)
    ,.sc2mac_dat_src_data12           (sc2mac_dat_a_data12)
    ,.sc2mac_dat_src_data13           (sc2mac_dat_a_data13)
    ,.sc2mac_dat_src_data14           (sc2mac_dat_a_data14)
    ,.sc2mac_dat_src_data15           (sc2mac_dat_a_data15)
    ,.sc2mac_dat_src_data16           (sc2mac_dat_a_data16)
    ,.sc2mac_dat_src_data17           (sc2mac_dat_a_data17)
    ,.sc2mac_dat_src_data18           (sc2mac_dat_a_data18)
    ,.sc2mac_dat_src_data19           (sc2mac_dat_a_data19)
    ,.sc2mac_dat_src_data20           (sc2mac_dat_a_data20)
    ,.sc2mac_dat_src_data21           (sc2mac_dat_a_data21)
    ,.sc2mac_dat_src_data22           (sc2mac_dat_a_data22)
    ,.sc2mac_dat_src_data23           (sc2mac_dat_a_data23)
    ,.sc2mac_dat_src_data24           (sc2mac_dat_a_data24)
    ,.sc2mac_dat_src_data25           (sc2mac_dat_a_data25)
    ,.sc2mac_dat_src_data26           (sc2mac_dat_a_data26)
    ,.sc2mac_dat_src_data27           (sc2mac_dat_a_data27)
    ,.sc2mac_dat_src_data28           (sc2mac_dat_a_data28)
    ,.sc2mac_dat_src_data29           (sc2mac_dat_a_data29)
    ,.sc2mac_dat_src_data30           (sc2mac_dat_a_data30)
    ,.sc2mac_dat_src_data31           (sc2mac_dat_a_data31)
    ,.sc2mac_dat_src_data32           (sc2mac_dat_a_data32)
    ,.sc2mac_dat_src_data33           (sc2mac_dat_a_data33)
    ,.sc2mac_dat_src_data34           (sc2mac_dat_a_data34)
    ,.sc2mac_dat_src_data35           (sc2mac_dat_a_data35)
    ,.sc2mac_dat_src_data36           (sc2mac_dat_a_data36)
    ,.sc2mac_dat_src_data37           (sc2mac_dat_a_data37)
    ,.sc2mac_dat_src_data38           (sc2mac_dat_a_data38)
    ,.sc2mac_dat_src_data39           (sc2mac_dat_a_data39)
    ,.sc2mac_dat_src_data40           (sc2mac_dat_a_data40)
    ,.sc2mac_dat_src_data41           (sc2mac_dat_a_data41)
    ,.sc2mac_dat_src_data42           (sc2mac_dat_a_data42)
    ,.sc2mac_dat_src_data43           (sc2mac_dat_a_data43)
    ,.sc2mac_dat_src_data44           (sc2mac_dat_a_data44)
    ,.sc2mac_dat_src_data45           (sc2mac_dat_a_data45)
    ,.sc2mac_dat_src_data46           (sc2mac_dat_a_data46)
    ,.sc2mac_dat_src_data47           (sc2mac_dat_a_data47)
    ,.sc2mac_dat_src_data48           (sc2mac_dat_a_data48)
    ,.sc2mac_dat_src_data49           (sc2mac_dat_a_data49)
    ,.sc2mac_dat_src_data50           (sc2mac_dat_a_data50)
    ,.sc2mac_dat_src_data51           (sc2mac_dat_a_data51)
    ,.sc2mac_dat_src_data52           (sc2mac_dat_a_data52)
    ,.sc2mac_dat_src_data53           (sc2mac_dat_a_data53)
    ,.sc2mac_dat_src_data54           (sc2mac_dat_a_data54)
    ,.sc2mac_dat_src_data55           (sc2mac_dat_a_data55)
    ,.sc2mac_dat_src_data56           (sc2mac_dat_a_data56)
    ,.sc2mac_dat_src_data57           (sc2mac_dat_a_data57)
    ,.sc2mac_dat_src_data58           (sc2mac_dat_a_data58)
    ,.sc2mac_dat_src_data59           (sc2mac_dat_a_data59)
    ,.sc2mac_dat_src_data60           (sc2mac_dat_a_data60)
    ,.sc2mac_dat_src_data61           (sc2mac_dat_a_data61)
    ,.sc2mac_dat_src_data62           (sc2mac_dat_a_data62)
    ,.sc2mac_dat_src_data63           (sc2mac_dat_a_data63)
    ,.sc2mac_dat_src_data64           (sc2mac_dat_a_data64)
    ,.sc2mac_dat_src_data65           (sc2mac_dat_a_data65)
    ,.sc2mac_dat_src_data66           (sc2mac_dat_a_data66)
    ,.sc2mac_dat_src_data67           (sc2mac_dat_a_data67)
    ,.sc2mac_dat_src_data68           (sc2mac_dat_a_data68)
    ,.sc2mac_dat_src_data69           (sc2mac_dat_a_data69)
    ,.sc2mac_dat_src_data70           (sc2mac_dat_a_data70)
    ,.sc2mac_dat_src_data71           (sc2mac_dat_a_data71)
    ,.sc2mac_dat_src_data72           (sc2mac_dat_a_data72)
    ,.sc2mac_dat_src_data73           (sc2mac_dat_a_data73)
    ,.sc2mac_dat_src_data74           (sc2mac_dat_a_data74)
    ,.sc2mac_dat_src_data75           (sc2mac_dat_a_data75)
    ,.sc2mac_dat_src_data76           (sc2mac_dat_a_data76)
    ,.sc2mac_dat_src_data77           (sc2mac_dat_a_data77)
    ,.sc2mac_dat_src_data78           (sc2mac_dat_a_data78)
    ,.sc2mac_dat_src_data79           (sc2mac_dat_a_data79)
    ,.sc2mac_dat_src_data80           (sc2mac_dat_a_data80)
    ,.sc2mac_dat_src_data81           (sc2mac_dat_a_data81)
    ,.sc2mac_dat_src_data82           (sc2mac_dat_a_data82)
    ,.sc2mac_dat_src_data83           (sc2mac_dat_a_data83)
    ,.sc2mac_dat_src_data84           (sc2mac_dat_a_data84)
    ,.sc2mac_dat_src_data85           (sc2mac_dat_a_data85)
    ,.sc2mac_dat_src_data86           (sc2mac_dat_a_data86)
    ,.sc2mac_dat_src_data87           (sc2mac_dat_a_data87)
    ,.sc2mac_dat_src_data88           (sc2mac_dat_a_data88)
    ,.sc2mac_dat_src_data89           (sc2mac_dat_a_data89)
    ,.sc2mac_dat_src_data90           (sc2mac_dat_a_data90)
    ,.sc2mac_dat_src_data91           (sc2mac_dat_a_data91)
    ,.sc2mac_dat_src_data92           (sc2mac_dat_a_data92)
    ,.sc2mac_dat_src_data93           (sc2mac_dat_a_data93)
    ,.sc2mac_dat_src_data94           (sc2mac_dat_a_data94)
    ,.sc2mac_dat_src_data95           (sc2mac_dat_a_data95)
    ,.sc2mac_dat_src_data96           (sc2mac_dat_a_data96)
    ,.sc2mac_dat_src_data97           (sc2mac_dat_a_data97)
    ,.sc2mac_dat_src_data98           (sc2mac_dat_a_data98)
    ,.sc2mac_dat_src_data99           (sc2mac_dat_a_data99)
    ,.sc2mac_dat_src_data100          (sc2mac_dat_a_data100)
    ,.sc2mac_dat_src_data101          (sc2mac_dat_a_data101)
    ,.sc2mac_dat_src_data102          (sc2mac_dat_a_data102)
    ,.sc2mac_dat_src_data103          (sc2mac_dat_a_data103)
    ,.sc2mac_dat_src_data104          (sc2mac_dat_a_data104)
    ,.sc2mac_dat_src_data105          (sc2mac_dat_a_data105)
    ,.sc2mac_dat_src_data106          (sc2mac_dat_a_data106)
    ,.sc2mac_dat_src_data107          (sc2mac_dat_a_data107)
    ,.sc2mac_dat_src_data108          (sc2mac_dat_a_data108)
    ,.sc2mac_dat_src_data109          (sc2mac_dat_a_data109)
    ,.sc2mac_dat_src_data110          (sc2mac_dat_a_data110)
    ,.sc2mac_dat_src_data111          (sc2mac_dat_a_data111)
    ,.sc2mac_dat_src_data112          (sc2mac_dat_a_data112)
    ,.sc2mac_dat_src_data113          (sc2mac_dat_a_data113)
    ,.sc2mac_dat_src_data114          (sc2mac_dat_a_data114)
    ,.sc2mac_dat_src_data115          (sc2mac_dat_a_data115)
    ,.sc2mac_dat_src_data116          (sc2mac_dat_a_data116)
    ,.sc2mac_dat_src_data117          (sc2mac_dat_a_data117)
    ,.sc2mac_dat_src_data118          (sc2mac_dat_a_data118)
    ,.sc2mac_dat_src_data119          (sc2mac_dat_a_data119)
    ,.sc2mac_dat_src_data120          (sc2mac_dat_a_data120)
    ,.sc2mac_dat_src_data121          (sc2mac_dat_a_data121)
    ,.sc2mac_dat_src_data122          (sc2mac_dat_a_data122)
    ,.sc2mac_dat_src_data123          (sc2mac_dat_a_data123)
    ,.sc2mac_dat_src_data124          (sc2mac_dat_a_data124)
    ,.sc2mac_dat_src_data125          (sc2mac_dat_a_data125)
    ,.sc2mac_dat_src_data126          (sc2mac_dat_a_data126)
    ,.sc2mac_dat_src_data127          (sc2mac_dat_a_data127)
    ,.sc2mac_dat_src_pd               (sc2mac_dat_a_pd)
    ,.sc2mac_wt_dst_pvld              (sc2mac_wt_a_dst_pvld)
    ,.sc2mac_wt_dst_mask              (sc2mac_wt_a_dst_mask)
    ,.sc2mac_wt_dst_data0             (sc2mac_wt_a_dst_data0)
    ,.sc2mac_wt_dst_data1             (sc2mac_wt_a_dst_data1)
    ,.sc2mac_wt_dst_data2             (sc2mac_wt_a_dst_data2)
    ,.sc2mac_wt_dst_data3             (sc2mac_wt_a_dst_data3)
    ,.sc2mac_wt_dst_data4             (sc2mac_wt_a_dst_data4)
    ,.sc2mac_wt_dst_data5             (sc2mac_wt_a_dst_data5)
    ,.sc2mac_wt_dst_data6             (sc2mac_wt_a_dst_data6)
    ,.sc2mac_wt_dst_data7             (sc2mac_wt_a_dst_data7)
    ,.sc2mac_wt_dst_data8             (sc2mac_wt_a_dst_data8)
    ,.sc2mac_wt_dst_data9             (sc2mac_wt_a_dst_data9)
    ,.sc2mac_wt_dst_data10            (sc2mac_wt_a_dst_data10)
    ,.sc2mac_wt_dst_data11            (sc2mac_wt_a_dst_data11)
    ,.sc2mac_wt_dst_data12            (sc2mac_wt_a_dst_data12)
    ,.sc2mac_wt_dst_data13            (sc2mac_wt_a_dst_data13)
    ,.sc2mac_wt_dst_data14            (sc2mac_wt_a_dst_data14)
    ,.sc2mac_wt_dst_data15            (sc2mac_wt_a_dst_data15)
    ,.sc2mac_wt_dst_data16            (sc2mac_wt_a_dst_data16)
    ,.sc2mac_wt_dst_data17            (sc2mac_wt_a_dst_data17)
    ,.sc2mac_wt_dst_data18            (sc2mac_wt_a_dst_data18)
    ,.sc2mac_wt_dst_data19            (sc2mac_wt_a_dst_data19)
    ,.sc2mac_wt_dst_data20            (sc2mac_wt_a_dst_data20)
    ,.sc2mac_wt_dst_data21            (sc2mac_wt_a_dst_data21)
    ,.sc2mac_wt_dst_data22            (sc2mac_wt_a_dst_data22)
    ,.sc2mac_wt_dst_data23            (sc2mac_wt_a_dst_data23)
    ,.sc2mac_wt_dst_data24            (sc2mac_wt_a_dst_data24)
    ,.sc2mac_wt_dst_data25            (sc2mac_wt_a_dst_data25)
    ,.sc2mac_wt_dst_data26            (sc2mac_wt_a_dst_data26)
    ,.sc2mac_wt_dst_data27            (sc2mac_wt_a_dst_data27)
    ,.sc2mac_wt_dst_data28            (sc2mac_wt_a_dst_data28)
    ,.sc2mac_wt_dst_data29            (sc2mac_wt_a_dst_data29)
    ,.sc2mac_wt_dst_data30            (sc2mac_wt_a_dst_data30)
    ,.sc2mac_wt_dst_data31            (sc2mac_wt_a_dst_data31)
    ,.sc2mac_wt_dst_data32            (sc2mac_wt_a_dst_data32)
    ,.sc2mac_wt_dst_data33            (sc2mac_wt_a_dst_data33)
    ,.sc2mac_wt_dst_data34            (sc2mac_wt_a_dst_data34)
    ,.sc2mac_wt_dst_data35            (sc2mac_wt_a_dst_data35)
    ,.sc2mac_wt_dst_data36            (sc2mac_wt_a_dst_data36)
    ,.sc2mac_wt_dst_data37            (sc2mac_wt_a_dst_data37)
    ,.sc2mac_wt_dst_data38            (sc2mac_wt_a_dst_data38)
    ,.sc2mac_wt_dst_data39            (sc2mac_wt_a_dst_data39)
    ,.sc2mac_wt_dst_data40            (sc2mac_wt_a_dst_data40)
    ,.sc2mac_wt_dst_data41            (sc2mac_wt_a_dst_data41)
    ,.sc2mac_wt_dst_data42            (sc2mac_wt_a_dst_data42)
    ,.sc2mac_wt_dst_data43            (sc2mac_wt_a_dst_data43)
    ,.sc2mac_wt_dst_data44            (sc2mac_wt_a_dst_data44)
    ,.sc2mac_wt_dst_data45            (sc2mac_wt_a_dst_data45)
    ,.sc2mac_wt_dst_data46            (sc2mac_wt_a_dst_data46)
    ,.sc2mac_wt_dst_data47            (sc2mac_wt_a_dst_data47)
    ,.sc2mac_wt_dst_data48            (sc2mac_wt_a_dst_data48)
    ,.sc2mac_wt_dst_data49            (sc2mac_wt_a_dst_data49)
    ,.sc2mac_wt_dst_data50            (sc2mac_wt_a_dst_data50)
    ,.sc2mac_wt_dst_data51            (sc2mac_wt_a_dst_data51)
    ,.sc2mac_wt_dst_data52            (sc2mac_wt_a_dst_data52)
    ,.sc2mac_wt_dst_data53            (sc2mac_wt_a_dst_data53)
    ,.sc2mac_wt_dst_data54            (sc2mac_wt_a_dst_data54)
    ,.sc2mac_wt_dst_data55            (sc2mac_wt_a_dst_data55)
    ,.sc2mac_wt_dst_data56            (sc2mac_wt_a_dst_data56)
    ,.sc2mac_wt_dst_data57            (sc2mac_wt_a_dst_data57)
    ,.sc2mac_wt_dst_data58            (sc2mac_wt_a_dst_data58)
    ,.sc2mac_wt_dst_data59            (sc2mac_wt_a_dst_data59)
    ,.sc2mac_wt_dst_data60            (sc2mac_wt_a_dst_data60)
    ,.sc2mac_wt_dst_data61            (sc2mac_wt_a_dst_data61)
    ,.sc2mac_wt_dst_data62            (sc2mac_wt_a_dst_data62)
    ,.sc2mac_wt_dst_data63            (sc2mac_wt_a_dst_data63)
    ,.sc2mac_wt_dst_data64            (sc2mac_wt_a_dst_data64)
    ,.sc2mac_wt_dst_data65            (sc2mac_wt_a_dst_data65)
    ,.sc2mac_wt_dst_data66            (sc2mac_wt_a_dst_data66)
    ,.sc2mac_wt_dst_data67            (sc2mac_wt_a_dst_data67)
    ,.sc2mac_wt_dst_data68            (sc2mac_wt_a_dst_data68)
    ,.sc2mac_wt_dst_data69            (sc2mac_wt_a_dst_data69)
    ,.sc2mac_wt_dst_data70            (sc2mac_wt_a_dst_data70)
    ,.sc2mac_wt_dst_data71            (sc2mac_wt_a_dst_data71)
    ,.sc2mac_wt_dst_data72            (sc2mac_wt_a_dst_data72)
    ,.sc2mac_wt_dst_data73            (sc2mac_wt_a_dst_data73)
    ,.sc2mac_wt_dst_data74            (sc2mac_wt_a_dst_data74)
    ,.sc2mac_wt_dst_data75            (sc2mac_wt_a_dst_data75)
    ,.sc2mac_wt_dst_data76            (sc2mac_wt_a_dst_data76)
    ,.sc2mac_wt_dst_data77            (sc2mac_wt_a_dst_data77)
    ,.sc2mac_wt_dst_data78            (sc2mac_wt_a_dst_data78)
    ,.sc2mac_wt_dst_data79            (sc2mac_wt_a_dst_data79)
    ,.sc2mac_wt_dst_data80            (sc2mac_wt_a_dst_data80)
    ,.sc2mac_wt_dst_data81            (sc2mac_wt_a_dst_data81)
    ,.sc2mac_wt_dst_data82            (sc2mac_wt_a_dst_data82)
    ,.sc2mac_wt_dst_data83            (sc2mac_wt_a_dst_data83)
    ,.sc2mac_wt_dst_data84            (sc2mac_wt_a_dst_data84)
    ,.sc2mac_wt_dst_data85            (sc2mac_wt_a_dst_data85)
    ,.sc2mac_wt_dst_data86            (sc2mac_wt_a_dst_data86)
    ,.sc2mac_wt_dst_data87            (sc2mac_wt_a_dst_data87)
    ,.sc2mac_wt_dst_data88            (sc2mac_wt_a_dst_data88)
    ,.sc2mac_wt_dst_data89            (sc2mac_wt_a_dst_data89)
    ,.sc2mac_wt_dst_data90            (sc2mac_wt_a_dst_data90)
    ,.sc2mac_wt_dst_data91            (sc2mac_wt_a_dst_data91)
    ,.sc2mac_wt_dst_data92            (sc2mac_wt_a_dst_data92)
    ,.sc2mac_wt_dst_data93            (sc2mac_wt_a_dst_data93)
    ,.sc2mac_wt_dst_data94            (sc2mac_wt_a_dst_data94)
    ,.sc2mac_wt_dst_data95            (sc2mac_wt_a_dst_data95)
    ,.sc2mac_wt_dst_data96            (sc2mac_wt_a_dst_data96)
    ,.sc2mac_wt_dst_data97            (sc2mac_wt_a_dst_data97)
    ,.sc2mac_wt_dst_data98            (sc2mac_wt_a_dst_data98)
    ,.sc2mac_wt_dst_data99            (sc2mac_wt_a_dst_data99)
    ,.sc2mac_wt_dst_data100           (sc2mac_wt_a_dst_data100)
    ,.sc2mac_wt_dst_data101           (sc2mac_wt_a_dst_data101)
    ,.sc2mac_wt_dst_data102           (sc2mac_wt_a_dst_data102)
    ,.sc2mac_wt_dst_data103           (sc2mac_wt_a_dst_data103)
    ,.sc2mac_wt_dst_data104           (sc2mac_wt_a_dst_data104)
    ,.sc2mac_wt_dst_data105           (sc2mac_wt_a_dst_data105)
    ,.sc2mac_wt_dst_data106           (sc2mac_wt_a_dst_data106)
    ,.sc2mac_wt_dst_data107           (sc2mac_wt_a_dst_data107)
    ,.sc2mac_wt_dst_data108           (sc2mac_wt_a_dst_data108)
    ,.sc2mac_wt_dst_data109           (sc2mac_wt_a_dst_data109)
    ,.sc2mac_wt_dst_data110           (sc2mac_wt_a_dst_data110)
    ,.sc2mac_wt_dst_data111           (sc2mac_wt_a_dst_data111)
    ,.sc2mac_wt_dst_data112           (sc2mac_wt_a_dst_data112)
    ,.sc2mac_wt_dst_data113           (sc2mac_wt_a_dst_data113)
    ,.sc2mac_wt_dst_data114           (sc2mac_wt_a_dst_data114)
    ,.sc2mac_wt_dst_data115           (sc2mac_wt_a_dst_data115)
    ,.sc2mac_wt_dst_data116           (sc2mac_wt_a_dst_data116)
    ,.sc2mac_wt_dst_data117           (sc2mac_wt_a_dst_data117)
    ,.sc2mac_wt_dst_data118           (sc2mac_wt_a_dst_data118)
    ,.sc2mac_wt_dst_data119           (sc2mac_wt_a_dst_data119)
    ,.sc2mac_wt_dst_data120           (sc2mac_wt_a_dst_data120)
    ,.sc2mac_wt_dst_data121           (sc2mac_wt_a_dst_data121)
    ,.sc2mac_wt_dst_data122           (sc2mac_wt_a_dst_data122)
    ,.sc2mac_wt_dst_data123           (sc2mac_wt_a_dst_data123)
    ,.sc2mac_wt_dst_data124           (sc2mac_wt_a_dst_data124)
    ,.sc2mac_wt_dst_data125           (sc2mac_wt_a_dst_data125)
    ,.sc2mac_wt_dst_data126           (sc2mac_wt_a_dst_data126)
    ,.sc2mac_wt_dst_data127           (sc2mac_wt_a_dst_data127)
    ,.sc2mac_wt_dst_sel               (sc2mac_wt_a_dst_sel)
    ,.sc2mac_dat_dst_pvld             (sc2mac_dat_a_dst_pvld)
    ,.sc2mac_dat_dst_mask             (sc2mac_dat_a_dst_mask)
    ,.sc2mac_dat_dst_data0            (sc2mac_dat_a_dst_data0)
    ,.sc2mac_dat_dst_data1            (sc2mac_dat_a_dst_data1)
    ,.sc2mac_dat_dst_data2            (sc2mac_dat_a_dst_data2)
    ,.sc2mac_dat_dst_data3            (sc2mac_dat_a_dst_data3)
    ,.sc2mac_dat_dst_data4            (sc2mac_dat_a_dst_data4)
    ,.sc2mac_dat_dst_data5            (sc2mac_dat_a_dst_data5)
    ,.sc2mac_dat_dst_data6            (sc2mac_dat_a_dst_data6)
    ,.sc2mac_dat_dst_data7            (sc2mac_dat_a_dst_data7)
    ,.sc2mac_dat_dst_data8            (sc2mac_dat_a_dst_data8)
    ,.sc2mac_dat_dst_data9            (sc2mac_dat_a_dst_data9)
    ,.sc2mac_dat_dst_data10           (sc2mac_dat_a_dst_data10)
    ,.sc2mac_dat_dst_data11           (sc2mac_dat_a_dst_data11)
    ,.sc2mac_dat_dst_data12           (sc2mac_dat_a_dst_data12)
    ,.sc2mac_dat_dst_data13           (sc2mac_dat_a_dst_data13)
    ,.sc2mac_dat_dst_data14           (sc2mac_dat_a_dst_data14)
    ,.sc2mac_dat_dst_data15           (sc2mac_dat_a_dst_data15)
    ,.sc2mac_dat_dst_data16           (sc2mac_dat_a_dst_data16)
    ,.sc2mac_dat_dst_data17           (sc2mac_dat_a_dst_data17)
    ,.sc2mac_dat_dst_data18           (sc2mac_dat_a_dst_data18)
    ,.sc2mac_dat_dst_data19           (sc2mac_dat_a_dst_data19)
    ,.sc2mac_dat_dst_data20           (sc2mac_dat_a_dst_data20)
    ,.sc2mac_dat_dst_data21           (sc2mac_dat_a_dst_data21)
    ,.sc2mac_dat_dst_data22           (sc2mac_dat_a_dst_data22)
    ,.sc2mac_dat_dst_data23           (sc2mac_dat_a_dst_data23)
    ,.sc2mac_dat_dst_data24           (sc2mac_dat_a_dst_data24)
    ,.sc2mac_dat_dst_data25           (sc2mac_dat_a_dst_data25)
    ,.sc2mac_dat_dst_data26           (sc2mac_dat_a_dst_data26)
    ,.sc2mac_dat_dst_data27           (sc2mac_dat_a_dst_data27)
    ,.sc2mac_dat_dst_data28           (sc2mac_dat_a_dst_data28)
    ,.sc2mac_dat_dst_data29           (sc2mac_dat_a_dst_data29)
    ,.sc2mac_dat_dst_data30           (sc2mac_dat_a_dst_data30)
    ,.sc2mac_dat_dst_data31           (sc2mac_dat_a_dst_data31)
    ,.sc2mac_dat_dst_data32           (sc2mac_dat_a_dst_data32)
    ,.sc2mac_dat_dst_data33           (sc2mac_dat_a_dst_data33)
    ,.sc2mac_dat_dst_data34           (sc2mac_dat_a_dst_data34)
    ,.sc2mac_dat_dst_data35           (sc2mac_dat_a_dst_data35)
    ,.sc2mac_dat_dst_data36           (sc2mac_dat_a_dst_data36)
    ,.sc2mac_dat_dst_data37           (sc2mac_dat_a_dst_data37)
    ,.sc2mac_dat_dst_data38           (sc2mac_dat_a_dst_data38)
    ,.sc2mac_dat_dst_data39           (sc2mac_dat_a_dst_data39)
    ,.sc2mac_dat_dst_data40           (sc2mac_dat_a_dst_data40)
    ,.sc2mac_dat_dst_data41           (sc2mac_dat_a_dst_data41)
    ,.sc2mac_dat_dst_data42           (sc2mac_dat_a_dst_data42)
    ,.sc2mac_dat_dst_data43           (sc2mac_dat_a_dst_data43)
    ,.sc2mac_dat_dst_data44           (sc2mac_dat_a_dst_data44)
    ,.sc2mac_dat_dst_data45           (sc2mac_dat_a_dst_data45)
    ,.sc2mac_dat_dst_data46           (sc2mac_dat_a_dst_data46)
    ,.sc2mac_dat_dst_data47           (sc2mac_dat_a_dst_data47)
    ,.sc2mac_dat_dst_data48           (sc2mac_dat_a_dst_data48)
    ,.sc2mac_dat_dst_data49           (sc2mac_dat_a_dst_data49)
    ,.sc2mac_dat_dst_data50           (sc2mac_dat_a_dst_data50)
    ,.sc2mac_dat_dst_data51           (sc2mac_dat_a_dst_data51)
    ,.sc2mac_dat_dst_data52           (sc2mac_dat_a_dst_data52)
    ,.sc2mac_dat_dst_data53           (sc2mac_dat_a_dst_data53)
    ,.sc2mac_dat_dst_data54           (sc2mac_dat_a_dst_data54)
    ,.sc2mac_dat_dst_data55           (sc2mac_dat_a_dst_data55)
    ,.sc2mac_dat_dst_data56           (sc2mac_dat_a_dst_data56)
    ,.sc2mac_dat_dst_data57           (sc2mac_dat_a_dst_data57)
    ,.sc2mac_dat_dst_data58           (sc2mac_dat_a_dst_data58)
    ,.sc2mac_dat_dst_data59           (sc2mac_dat_a_dst_data59)
    ,.sc2mac_dat_dst_data60           (sc2mac_dat_a_dst_data60)
    ,.sc2mac_dat_dst_data61           (sc2mac_dat_a_dst_data61)
    ,.sc2mac_dat_dst_data62           (sc2mac_dat_a_dst_data62)
    ,.sc2mac_dat_dst_data63           (sc2mac_dat_a_dst_data63)
    ,.sc2mac_dat_dst_data64           (sc2mac_dat_a_dst_data64)
    ,.sc2mac_dat_dst_data65           (sc2mac_dat_a_dst_data65)
    ,.sc2mac_dat_dst_data66           (sc2mac_dat_a_dst_data66)
    ,.sc2mac_dat_dst_data67           (sc2mac_dat_a_dst_data67)
    ,.sc2mac_dat_dst_data68           (sc2mac_dat_a_dst_data68)
    ,.sc2mac_dat_dst_data69           (sc2mac_dat_a_dst_data69)
    ,.sc2mac_dat_dst_data70           (sc2mac_dat_a_dst_data70)
    ,.sc2mac_dat_dst_data71           (sc2mac_dat_a_dst_data71)
    ,.sc2mac_dat_dst_data72           (sc2mac_dat_a_dst_data72)
    ,.sc2mac_dat_dst_data73           (sc2mac_dat_a_dst_data73)
    ,.sc2mac_dat_dst_data74           (sc2mac_dat_a_dst_data74)
    ,.sc2mac_dat_dst_data75           (sc2mac_dat_a_dst_data75)
    ,.sc2mac_dat_dst_data76           (sc2mac_dat_a_dst_data76)
    ,.sc2mac_dat_dst_data77           (sc2mac_dat_a_dst_data77)
    ,.sc2mac_dat_dst_data78           (sc2mac_dat_a_dst_data78)
    ,.sc2mac_dat_dst_data79           (sc2mac_dat_a_dst_data79)
    ,.sc2mac_dat_dst_data80           (sc2mac_dat_a_dst_data80)
    ,.sc2mac_dat_dst_data81           (sc2mac_dat_a_dst_data81)
    ,.sc2mac_dat_dst_data82           (sc2mac_dat_a_dst_data82)
    ,.sc2mac_dat_dst_data83           (sc2mac_dat_a_dst_data83)
    ,.sc2mac_dat_dst_data84           (sc2mac_dat_a_dst_data84)
    ,.sc2mac_dat_dst_data85           (sc2mac_dat_a_dst_data85)
    ,.sc2mac_dat_dst_data86           (sc2mac_dat_a_dst_data86)
    ,.sc2mac_dat_dst_data87           (sc2mac_dat_a_dst_data87)
    ,.sc2mac_dat_dst_data88           (sc2mac_dat_a_dst_data88)
    ,.sc2mac_dat_dst_data89           (sc2mac_dat_a_dst_data89)
    ,.sc2mac_dat_dst_data90           (sc2mac_dat_a_dst_data90)
    ,.sc2mac_dat_dst_data91           (sc2mac_dat_a_dst_data91)
    ,.sc2mac_dat_dst_data92           (sc2mac_dat_a_dst_data92)
    ,.sc2mac_dat_dst_data93           (sc2mac_dat_a_dst_data93)
    ,.sc2mac_dat_dst_data94           (sc2mac_dat_a_dst_data94)
    ,.sc2mac_dat_dst_data95           (sc2mac_dat_a_dst_data95)
    ,.sc2mac_dat_dst_data96           (sc2mac_dat_a_dst_data96)
    ,.sc2mac_dat_dst_data97           (sc2mac_dat_a_dst_data97)
    ,.sc2mac_dat_dst_data98           (sc2mac_dat_a_dst_data98)
    ,.sc2mac_dat_dst_data99           (sc2mac_dat_a_dst_data99)
    ,.sc2mac_dat_dst_data100          (sc2mac_dat_a_dst_data100)
    ,.sc2mac_dat_dst_data101          (sc2mac_dat_a_dst_data101)
    ,.sc2mac_dat_dst_data102          (sc2mac_dat_a_dst_data102)
    ,.sc2mac_dat_dst_data103          (sc2mac_dat_a_dst_data103)
    ,.sc2mac_dat_dst_data104          (sc2mac_dat_a_dst_data104)
    ,.sc2mac_dat_dst_data105          (sc2mac_dat_a_dst_data105)
    ,.sc2mac_dat_dst_data106          (sc2mac_dat_a_dst_data106)
    ,.sc2mac_dat_dst_data107          (sc2mac_dat_a_dst_data107)
    ,.sc2mac_dat_dst_data108          (sc2mac_dat_a_dst_data108)
    ,.sc2mac_dat_dst_data109          (sc2mac_dat_a_dst_data109)
    ,.sc2mac_dat_dst_data110          (sc2mac_dat_a_dst_data110)
    ,.sc2mac_dat_dst_data111          (sc2mac_dat_a_dst_data111)
    ,.sc2mac_dat_dst_data112          (sc2mac_dat_a_dst_data112)
    ,.sc2mac_dat_dst_data113          (sc2mac_dat_a_dst_data113)
    ,.sc2mac_dat_dst_data114          (sc2mac_dat_a_dst_data114)
    ,.sc2mac_dat_dst_data115          (sc2mac_dat_a_dst_data115)
    ,.sc2mac_dat_dst_data116          (sc2mac_dat_a_dst_data116)
    ,.sc2mac_dat_dst_data117          (sc2mac_dat_a_dst_data117)
    ,.sc2mac_dat_dst_data118          (sc2mac_dat_a_dst_data118)
    ,.sc2mac_dat_dst_data119          (sc2mac_dat_a_dst_data119)
    ,.sc2mac_dat_dst_data120          (sc2mac_dat_a_dst_data120)
    ,.sc2mac_dat_dst_data121          (sc2mac_dat_a_dst_data121)
    ,.sc2mac_dat_dst_data122          (sc2mac_dat_a_dst_data122)
    ,.sc2mac_dat_dst_data123          (sc2mac_dat_a_dst_data123)
    ,.sc2mac_dat_dst_data124          (sc2mac_dat_a_dst_data124)
    ,.sc2mac_dat_dst_data125          (sc2mac_dat_a_dst_data125)
    ,.sc2mac_dat_dst_data126          (sc2mac_dat_a_dst_data126)
    ,.sc2mac_dat_dst_data127          (sc2mac_dat_a_dst_data127)
    ,.sc2mac_dat_dst_pd               (sc2mac_dat_a_dst_pd)
  );

  NV_NVDLA_RT_csc2cmac_b u_NV_NVDLA_RT_csc2cmac_b (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.sc2mac_wt_src_pvld              (sc2mac_wt_b_pvld)
    ,.sc2mac_wt_src_mask              (sc2mac_wt_b_mask)
    ,.sc2mac_wt_src_data0             (sc2mac_wt_b_data0)
    ,.sc2mac_wt_src_data1             (sc2mac_wt_b_data1)
    ,.sc2mac_wt_src_data2             (sc2mac_wt_b_data2)
    ,.sc2mac_wt_src_data3             (sc2mac_wt_b_data3)
    ,.sc2mac_wt_src_data4             (sc2mac_wt_b_data4)
    ,.sc2mac_wt_src_data5             (sc2mac_wt_b_data5)
    ,.sc2mac_wt_src_data6             (sc2mac_wt_b_data6)
    ,.sc2mac_wt_src_data7             (sc2mac_wt_b_data7)
    ,.sc2mac_wt_src_data8             (sc2mac_wt_b_data8)
    ,.sc2mac_wt_src_data9             (sc2mac_wt_b_data9)
    ,.sc2mac_wt_src_data10            (sc2mac_wt_b_data10)
    ,.sc2mac_wt_src_data11            (sc2mac_wt_b_data11)
    ,.sc2mac_wt_src_data12            (sc2mac_wt_b_data12)
    ,.sc2mac_wt_src_data13            (sc2mac_wt_b_data13)
    ,.sc2mac_wt_src_data14            (sc2mac_wt_b_data14)
    ,.sc2mac_wt_src_data15            (sc2mac_wt_b_data15)
    ,.sc2mac_wt_src_data16            (sc2mac_wt_b_data16)
    ,.sc2mac_wt_src_data17            (sc2mac_wt_b_data17)
    ,.sc2mac_wt_src_data18            (sc2mac_wt_b_data18)
    ,.sc2mac_wt_src_data19            (sc2mac_wt_b_data19)
    ,.sc2mac_wt_src_data20            (sc2mac_wt_b_data20)
    ,.sc2mac_wt_src_data21            (sc2mac_wt_b_data21)
    ,.sc2mac_wt_src_data22            (sc2mac_wt_b_data22)
    ,.sc2mac_wt_src_data23            (sc2mac_wt_b_data23)
    ,.sc2mac_wt_src_data24            (sc2mac_wt_b_data24)
    ,.sc2mac_wt_src_data25            (sc2mac_wt_b_data25)
    ,.sc2mac_wt_src_data26            (sc2mac_wt_b_data26)
    ,.sc2mac_wt_src_data27            (sc2mac_wt_b_data27)
    ,.sc2mac_wt_src_data28            (sc2mac_wt_b_data28)
    ,.sc2mac_wt_src_data29            (sc2mac_wt_b_data29)
    ,.sc2mac_wt_src_data30            (sc2mac_wt_b_data30)
    ,.sc2mac_wt_src_data31            (sc2mac_wt_b_data31)
    ,.sc2mac_wt_src_data32            (sc2mac_wt_b_data32)
    ,.sc2mac_wt_src_data33            (sc2mac_wt_b_data33)
    ,.sc2mac_wt_src_data34            (sc2mac_wt_b_data34)
    ,.sc2mac_wt_src_data35            (sc2mac_wt_b_data35)
    ,.sc2mac_wt_src_data36            (sc2mac_wt_b_data36)
    ,.sc2mac_wt_src_data37            (sc2mac_wt_b_data37)
    ,.sc2mac_wt_src_data38            (sc2mac_wt_b_data38)
    ,.sc2mac_wt_src_data39            (sc2mac_wt_b_data39)
    ,.sc2mac_wt_src_data40            (sc2mac_wt_b_data40)
    ,.sc2mac_wt_src_data41            (sc2mac_wt_b_data41)
    ,.sc2mac_wt_src_data42            (sc2mac_wt_b_data42)
    ,.sc2mac_wt_src_data43            (sc2mac_wt_b_data43)
    ,.sc2mac_wt_src_data44            (sc2mac_wt_b_data44)
    ,.sc2mac_wt_src_data45            (sc2mac_wt_b_data45)
    ,.sc2mac_wt_src_data46            (sc2mac_wt_b_data46)
    ,.sc2mac_wt_src_data47            (sc2mac_wt_b_data47)
    ,.sc2mac_wt_src_data48            (sc2mac_wt_b_data48)
    ,.sc2mac_wt_src_data49            (sc2mac_wt_b_data49)
    ,.sc2mac_wt_src_data50            (sc2mac_wt_b_data50)
    ,.sc2mac_wt_src_data51            (sc2mac_wt_b_data51)
    ,.sc2mac_wt_src_data52            (sc2mac_wt_b_data52)
    ,.sc2mac_wt_src_data53            (sc2mac_wt_b_data53)
    ,.sc2mac_wt_src_data54            (sc2mac_wt_b_data54)
    ,.sc2mac_wt_src_data55            (sc2mac_wt_b_data55)
    ,.sc2mac_wt_src_data56            (sc2mac_wt_b_data56)
    ,.sc2mac_wt_src_data57            (sc2mac_wt_b_data57)
    ,.sc2mac_wt_src_data58            (sc2mac_wt_b_data58)
    ,.sc2mac_wt_src_data59            (sc2mac_wt_b_data59)
    ,.sc2mac_wt_src_data60            (sc2mac_wt_b_data60)
    ,.sc2mac_wt_src_data61            (sc2mac_wt_b_data61)
    ,.sc2mac_wt_src_data62            (sc2mac_wt_b_data62)
    ,.sc2mac_wt_src_data63            (sc2mac_wt_b_data63)
    ,.sc2mac_wt_src_data64            (sc2mac_wt_b_data64)
    ,.sc2mac_wt_src_data65            (sc2mac_wt_b_data65)
    ,.sc2mac_wt_src_data66            (sc2mac_wt_b_data66)
    ,.sc2mac_wt_src_data67            (sc2mac_wt_b_data67)
    ,.sc2mac_wt_src_data68            (sc2mac_wt_b_data68)
    ,.sc2mac_wt_src_data69            (sc2mac_wt_b_data69)
    ,.sc2mac_wt_src_data70            (sc2mac_wt_b_data70)
    ,.sc2mac_wt_src_data71            (sc2mac_wt_b_data71)
    ,.sc2mac_wt_src_data72            (sc2mac_wt_b_data72)
    ,.sc2mac_wt_src_data73            (sc2mac_wt_b_data73)
    ,.sc2mac_wt_src_data74            (sc2mac_wt_b_data74)
    ,.sc2mac_wt_src_data75            (sc2mac_wt_b_data75)
    ,.sc2mac_wt_src_data76            (sc2mac_wt_b_data76)
    ,.sc2mac_wt_src_data77            (sc2mac_wt_b_data77)
    ,.sc2mac_wt_src_data78            (sc2mac_wt_b_data78)
    ,.sc2mac_wt_src_data79            (sc2mac_wt_b_data79)
    ,.sc2mac_wt_src_data80            (sc2mac_wt_b_data80)
    ,.sc2mac_wt_src_data81            (sc2mac_wt_b_data81)
    ,.sc2mac_wt_src_data82            (sc2mac_wt_b_data82)
    ,.sc2mac_wt_src_data83            (sc2mac_wt_b_data83)
    ,.sc2mac_wt_src_data84            (sc2mac_wt_b_data84)
    ,.sc2mac_wt_src_data85            (sc2mac_wt_b_data85)
    ,.sc2mac_wt_src_data86            (sc2mac_wt_b_data86)
    ,.sc2mac_wt_src_data87            (sc2mac_wt_b_data87)
    ,.sc2mac_wt_src_data88            (sc2mac_wt_b_data88)
    ,.sc2mac_wt_src_data89            (sc2mac_wt_b_data89)
    ,.sc2mac_wt_src_data90            (sc2mac_wt_b_data90)
    ,.sc2mac_wt_src_data91            (sc2mac_wt_b_data91)
    ,.sc2mac_wt_src_data92            (sc2mac_wt_b_data92)
    ,.sc2mac_wt_src_data93            (sc2mac_wt_b_data93)
    ,.sc2mac_wt_src_data94            (sc2mac_wt_b_data94)
    ,.sc2mac_wt_src_data95            (sc2mac_wt_b_data95)
    ,.sc2mac_wt_src_data96            (sc2mac_wt_b_data96)
    ,.sc2mac_wt_src_data97            (sc2mac_wt_b_data97)
    ,.sc2mac_wt_src_data98            (sc2mac_wt_b_data98)
    ,.sc2mac_wt_src_data99            (sc2mac_wt_b_data99)
    ,.sc2mac_wt_src_data100           (sc2mac_wt_b_data100)
    ,.sc2mac_wt_src_data101           (sc2mac_wt_b_data101)
    ,.sc2mac_wt_src_data102           (sc2mac_wt_b_data102)
    ,.sc2mac_wt_src_data103           (sc2mac_wt_b_data103)
    ,.sc2mac_wt_src_data104           (sc2mac_wt_b_data104)
    ,.sc2mac_wt_src_data105           (sc2mac_wt_b_data105)
    ,.sc2mac_wt_src_data106           (sc2mac_wt_b_data106)
    ,.sc2mac_wt_src_data107           (sc2mac_wt_b_data107)
    ,.sc2mac_wt_src_data108           (sc2mac_wt_b_data108)
    ,.sc2mac_wt_src_data109           (sc2mac_wt_b_data109)
    ,.sc2mac_wt_src_data110           (sc2mac_wt_b_data110)
    ,.sc2mac_wt_src_data111           (sc2mac_wt_b_data111)
    ,.sc2mac_wt_src_data112           (sc2mac_wt_b_data112)
    ,.sc2mac_wt_src_data113           (sc2mac_wt_b_data113)
    ,.sc2mac_wt_src_data114           (sc2mac_wt_b_data114)
    ,.sc2mac_wt_src_data115           (sc2mac_wt_b_data115)
    ,.sc2mac_wt_src_data116           (sc2mac_wt_b_data116)
    ,.sc2mac_wt_src_data117           (sc2mac_wt_b_data117)
    ,.sc2mac_wt_src_data118           (sc2mac_wt_b_data118)
    ,.sc2mac_wt_src_data119           (sc2mac_wt_b_data119)
    ,.sc2mac_wt_src_data120           (sc2mac_wt_b_data120)
    ,.sc2mac_wt_src_data121           (sc2mac_wt_b_data121)
    ,.sc2mac_wt_src_data122           (sc2mac_wt_b_data122)
    ,.sc2mac_wt_src_data123           (sc2mac_wt_b_data123)
    ,.sc2mac_wt_src_data124           (sc2mac_wt_b_data124)
    ,.sc2mac_wt_src_data125           (sc2mac_wt_b_data125)
    ,.sc2mac_wt_src_data126           (sc2mac_wt_b_data126)
    ,.sc2mac_wt_src_data127           (sc2mac_wt_b_data127)
    ,.sc2mac_wt_src_sel               (sc2mac_wt_b_sel)
    ,.sc2mac_dat_src_pvld             (sc2mac_dat_b_pvld)
    ,.sc2mac_dat_src_mask             (sc2mac_dat_b_mask)
    ,.sc2mac_dat_src_data0            (sc2mac_dat_b_data0)
    ,.sc2mac_dat_src_data1            (sc2mac_dat_b_data1)
    ,.sc2mac_dat_src_data2            (sc2mac_dat_b_data2)
    ,.sc2mac_dat_src_data3            (sc2mac_dat_b_data3)
    ,.sc2mac_dat_src_data4            (sc2mac_dat_b_data4)
    ,.sc2mac_dat_src_data5            (sc2mac_dat_b_data5)
    ,.sc2mac_dat_src_data6            (sc2mac_dat_b_data6)
    ,.sc2mac_dat_src_data7            (sc2mac_dat_b_data7)
    ,.sc2mac_dat_src_data8            (sc2mac_dat_b_data8)
    ,.sc2mac_dat_src_data9            (sc2mac_dat_b_data9)
    ,.sc2mac_dat_src_data10           (sc2mac_dat_b_data10)
    ,.sc2mac_dat_src_data11           (sc2mac_dat_b_data11)
    ,.sc2mac_dat_src_data12           (sc2mac_dat_b_data12)
    ,.sc2mac_dat_src_data13           (sc2mac_dat_b_data13)
    ,.sc2mac_dat_src_data14           (sc2mac_dat_b_data14)
    ,.sc2mac_dat_src_data15           (sc2mac_dat_b_data15)
    ,.sc2mac_dat_src_data16           (sc2mac_dat_b_data16)
    ,.sc2mac_dat_src_data17           (sc2mac_dat_b_data17)
    ,.sc2mac_dat_src_data18           (sc2mac_dat_b_data18)
    ,.sc2mac_dat_src_data19           (sc2mac_dat_b_data19)
    ,.sc2mac_dat_src_data20           (sc2mac_dat_b_data20)
    ,.sc2mac_dat_src_data21           (sc2mac_dat_b_data21)
    ,.sc2mac_dat_src_data22           (sc2mac_dat_b_data22)
    ,.sc2mac_dat_src_data23           (sc2mac_dat_b_data23)
    ,.sc2mac_dat_src_data24           (sc2mac_dat_b_data24)
    ,.sc2mac_dat_src_data25           (sc2mac_dat_b_data25)
    ,.sc2mac_dat_src_data26           (sc2mac_dat_b_data26)
    ,.sc2mac_dat_src_data27           (sc2mac_dat_b_data27)
    ,.sc2mac_dat_src_data28           (sc2mac_dat_b_data28)
    ,.sc2mac_dat_src_data29           (sc2mac_dat_b_data29)
    ,.sc2mac_dat_src_data30           (sc2mac_dat_b_data30)
    ,.sc2mac_dat_src_data31           (sc2mac_dat_b_data31)
    ,.sc2mac_dat_src_data32           (sc2mac_dat_b_data32)
    ,.sc2mac_dat_src_data33           (sc2mac_dat_b_data33)
    ,.sc2mac_dat_src_data34           (sc2mac_dat_b_data34)
    ,.sc2mac_dat_src_data35           (sc2mac_dat_b_data35)
    ,.sc2mac_dat_src_data36           (sc2mac_dat_b_data36)
    ,.sc2mac_dat_src_data37           (sc2mac_dat_b_data37)
    ,.sc2mac_dat_src_data38           (sc2mac_dat_b_data38)
    ,.sc2mac_dat_src_data39           (sc2mac_dat_b_data39)
    ,.sc2mac_dat_src_data40           (sc2mac_dat_b_data40)
    ,.sc2mac_dat_src_data41           (sc2mac_dat_b_data41)
    ,.sc2mac_dat_src_data42           (sc2mac_dat_b_data42)
    ,.sc2mac_dat_src_data43           (sc2mac_dat_b_data43)
    ,.sc2mac_dat_src_data44           (sc2mac_dat_b_data44)
    ,.sc2mac_dat_src_data45           (sc2mac_dat_b_data45)
    ,.sc2mac_dat_src_data46           (sc2mac_dat_b_data46)
    ,.sc2mac_dat_src_data47           (sc2mac_dat_b_data47)
    ,.sc2mac_dat_src_data48           (sc2mac_dat_b_data48)
    ,.sc2mac_dat_src_data49           (sc2mac_dat_b_data49)
    ,.sc2mac_dat_src_data50           (sc2mac_dat_b_data50)
    ,.sc2mac_dat_src_data51           (sc2mac_dat_b_data51)
    ,.sc2mac_dat_src_data52           (sc2mac_dat_b_data52)
    ,.sc2mac_dat_src_data53           (sc2mac_dat_b_data53)
    ,.sc2mac_dat_src_data54           (sc2mac_dat_b_data54)
    ,.sc2mac_dat_src_data55           (sc2mac_dat_b_data55)
    ,.sc2mac_dat_src_data56           (sc2mac_dat_b_data56)
    ,.sc2mac_dat_src_data57           (sc2mac_dat_b_data57)
    ,.sc2mac_dat_src_data58           (sc2mac_dat_b_data58)
    ,.sc2mac_dat_src_data59           (sc2mac_dat_b_data59)
    ,.sc2mac_dat_src_data60           (sc2mac_dat_b_data60)
    ,.sc2mac_dat_src_data61           (sc2mac_dat_b_data61)
    ,.sc2mac_dat_src_data62           (sc2mac_dat_b_data62)
    ,.sc2mac_dat_src_data63           (sc2mac_dat_b_data63)
    ,.sc2mac_dat_src_data64           (sc2mac_dat_b_data64)
    ,.sc2mac_dat_src_data65           (sc2mac_dat_b_data65)
    ,.sc2mac_dat_src_data66           (sc2mac_dat_b_data66)
    ,.sc2mac_dat_src_data67           (sc2mac_dat_b_data67)
    ,.sc2mac_dat_src_data68           (sc2mac_dat_b_data68)
    ,.sc2mac_dat_src_data69           (sc2mac_dat_b_data69)
    ,.sc2mac_dat_src_data70           (sc2mac_dat_b_data70)
    ,.sc2mac_dat_src_data71           (sc2mac_dat_b_data71)
    ,.sc2mac_dat_src_data72           (sc2mac_dat_b_data72)
    ,.sc2mac_dat_src_data73           (sc2mac_dat_b_data73)
    ,.sc2mac_dat_src_data74           (sc2mac_dat_b_data74)
    ,.sc2mac_dat_src_data75           (sc2mac_dat_b_data75)
    ,.sc2mac_dat_src_data76           (sc2mac_dat_b_data76)
    ,.sc2mac_dat_src_data77           (sc2mac_dat_b_data77)
    ,.sc2mac_dat_src_data78           (sc2mac_dat_b_data78)
    ,.sc2mac_dat_src_data79           (sc2mac_dat_b_data79)
    ,.sc2mac_dat_src_data80           (sc2mac_dat_b_data80)
    ,.sc2mac_dat_src_data81           (sc2mac_dat_b_data81)
    ,.sc2mac_dat_src_data82           (sc2mac_dat_b_data82)
    ,.sc2mac_dat_src_data83           (sc2mac_dat_b_data83)
    ,.sc2mac_dat_src_data84           (sc2mac_dat_b_data84)
    ,.sc2mac_dat_src_data85           (sc2mac_dat_b_data85)
    ,.sc2mac_dat_src_data86           (sc2mac_dat_b_data86)
    ,.sc2mac_dat_src_data87           (sc2mac_dat_b_data87)
    ,.sc2mac_dat_src_data88           (sc2mac_dat_b_data88)
    ,.sc2mac_dat_src_data89           (sc2mac_dat_b_data89)
    ,.sc2mac_dat_src_data90           (sc2mac_dat_b_data90)
    ,.sc2mac_dat_src_data91           (sc2mac_dat_b_data91)
    ,.sc2mac_dat_src_data92           (sc2mac_dat_b_data92)
    ,.sc2mac_dat_src_data93           (sc2mac_dat_b_data93)
    ,.sc2mac_dat_src_data94           (sc2mac_dat_b_data94)
    ,.sc2mac_dat_src_data95           (sc2mac_dat_b_data95)
    ,.sc2mac_dat_src_data96           (sc2mac_dat_b_data96)
    ,.sc2mac_dat_src_data97           (sc2mac_dat_b_data97)
    ,.sc2mac_dat_src_data98           (sc2mac_dat_b_data98)
    ,.sc2mac_dat_src_data99           (sc2mac_dat_b_data99)
    ,.sc2mac_dat_src_data100          (sc2mac_dat_b_data100)
    ,.sc2mac_dat_src_data101          (sc2mac_dat_b_data101)
    ,.sc2mac_dat_src_data102          (sc2mac_dat_b_data102)
    ,.sc2mac_dat_src_data103          (sc2mac_dat_b_data103)
    ,.sc2mac_dat_src_data104          (sc2mac_dat_b_data104)
    ,.sc2mac_dat_src_data105          (sc2mac_dat_b_data105)
    ,.sc2mac_dat_src_data106          (sc2mac_dat_b_data106)
    ,.sc2mac_dat_src_data107          (sc2mac_dat_b_data107)
    ,.sc2mac_dat_src_data108          (sc2mac_dat_b_data108)
    ,.sc2mac_dat_src_data109          (sc2mac_dat_b_data109)
    ,.sc2mac_dat_src_data110          (sc2mac_dat_b_data110)
    ,.sc2mac_dat_src_data111          (sc2mac_dat_b_data111)
    ,.sc2mac_dat_src_data112          (sc2mac_dat_b_data112)
    ,.sc2mac_dat_src_data113          (sc2mac_dat_b_data113)
    ,.sc2mac_dat_src_data114          (sc2mac_dat_b_data114)
    ,.sc2mac_dat_src_data115          (sc2mac_dat_b_data115)
    ,.sc2mac_dat_src_data116          (sc2mac_dat_b_data116)
    ,.sc2mac_dat_src_data117          (sc2mac_dat_b_data117)
    ,.sc2mac_dat_src_data118          (sc2mac_dat_b_data118)
    ,.sc2mac_dat_src_data119          (sc2mac_dat_b_data119)
    ,.sc2mac_dat_src_data120          (sc2mac_dat_b_data120)
    ,.sc2mac_dat_src_data121          (sc2mac_dat_b_data121)
    ,.sc2mac_dat_src_data122          (sc2mac_dat_b_data122)
    ,.sc2mac_dat_src_data123          (sc2mac_dat_b_data123)
    ,.sc2mac_dat_src_data124          (sc2mac_dat_b_data124)
    ,.sc2mac_dat_src_data125          (sc2mac_dat_b_data125)
    ,.sc2mac_dat_src_data126          (sc2mac_dat_b_data126)
    ,.sc2mac_dat_src_data127          (sc2mac_dat_b_data127)
    ,.sc2mac_dat_src_pd               (sc2mac_dat_b_pd)
    ,.sc2mac_wt_dst_pvld              (sc2mac_wt_b_dst_pvld)
    ,.sc2mac_wt_dst_mask              (sc2mac_wt_b_dst_mask)
    ,.sc2mac_wt_dst_data0             (sc2mac_wt_b_dst_data0)
    ,.sc2mac_wt_dst_data1             (sc2mac_wt_b_dst_data1)
    ,.sc2mac_wt_dst_data2             (sc2mac_wt_b_dst_data2)
    ,.sc2mac_wt_dst_data3             (sc2mac_wt_b_dst_data3)
    ,.sc2mac_wt_dst_data4             (sc2mac_wt_b_dst_data4)
    ,.sc2mac_wt_dst_data5             (sc2mac_wt_b_dst_data5)
    ,.sc2mac_wt_dst_data6             (sc2mac_wt_b_dst_data6)
    ,.sc2mac_wt_dst_data7             (sc2mac_wt_b_dst_data7)
    ,.sc2mac_wt_dst_data8             (sc2mac_wt_b_dst_data8)
    ,.sc2mac_wt_dst_data9             (sc2mac_wt_b_dst_data9)
    ,.sc2mac_wt_dst_data10            (sc2mac_wt_b_dst_data10)
    ,.sc2mac_wt_dst_data11            (sc2mac_wt_b_dst_data11)
    ,.sc2mac_wt_dst_data12            (sc2mac_wt_b_dst_data12)
    ,.sc2mac_wt_dst_data13            (sc2mac_wt_b_dst_data13)
    ,.sc2mac_wt_dst_data14            (sc2mac_wt_b_dst_data14)
    ,.sc2mac_wt_dst_data15            (sc2mac_wt_b_dst_data15)
    ,.sc2mac_wt_dst_data16            (sc2mac_wt_b_dst_data16)
    ,.sc2mac_wt_dst_data17            (sc2mac_wt_b_dst_data17)
    ,.sc2mac_wt_dst_data18            (sc2mac_wt_b_dst_data18)
    ,.sc2mac_wt_dst_data19            (sc2mac_wt_b_dst_data19)
    ,.sc2mac_wt_dst_data20            (sc2mac_wt_b_dst_data20)
    ,.sc2mac_wt_dst_data21            (sc2mac_wt_b_dst_data21)
    ,.sc2mac_wt_dst_data22            (sc2mac_wt_b_dst_data22)
    ,.sc2mac_wt_dst_data23            (sc2mac_wt_b_dst_data23)
    ,.sc2mac_wt_dst_data24            (sc2mac_wt_b_dst_data24)
    ,.sc2mac_wt_dst_data25            (sc2mac_wt_b_dst_data25)
    ,.sc2mac_wt_dst_data26            (sc2mac_wt_b_dst_data26)
    ,.sc2mac_wt_dst_data27            (sc2mac_wt_b_dst_data27)
    ,.sc2mac_wt_dst_data28            (sc2mac_wt_b_dst_data28)
    ,.sc2mac_wt_dst_data29            (sc2mac_wt_b_dst_data29)
    ,.sc2mac_wt_dst_data30            (sc2mac_wt_b_dst_data30)
    ,.sc2mac_wt_dst_data31            (sc2mac_wt_b_dst_data31)
    ,.sc2mac_wt_dst_data32            (sc2mac_wt_b_dst_data32)
    ,.sc2mac_wt_dst_data33            (sc2mac_wt_b_dst_data33)
    ,.sc2mac_wt_dst_data34            (sc2mac_wt_b_dst_data34)
    ,.sc2mac_wt_dst_data35            (sc2mac_wt_b_dst_data35)
    ,.sc2mac_wt_dst_data36            (sc2mac_wt_b_dst_data36)
    ,.sc2mac_wt_dst_data37            (sc2mac_wt_b_dst_data37)
    ,.sc2mac_wt_dst_data38            (sc2mac_wt_b_dst_data38)
    ,.sc2mac_wt_dst_data39            (sc2mac_wt_b_dst_data39)
    ,.sc2mac_wt_dst_data40            (sc2mac_wt_b_dst_data40)
    ,.sc2mac_wt_dst_data41            (sc2mac_wt_b_dst_data41)
    ,.sc2mac_wt_dst_data42            (sc2mac_wt_b_dst_data42)
    ,.sc2mac_wt_dst_data43            (sc2mac_wt_b_dst_data43)
    ,.sc2mac_wt_dst_data44            (sc2mac_wt_b_dst_data44)
    ,.sc2mac_wt_dst_data45            (sc2mac_wt_b_dst_data45)
    ,.sc2mac_wt_dst_data46            (sc2mac_wt_b_dst_data46)
    ,.sc2mac_wt_dst_data47            (sc2mac_wt_b_dst_data47)
    ,.sc2mac_wt_dst_data48            (sc2mac_wt_b_dst_data48)
    ,.sc2mac_wt_dst_data49            (sc2mac_wt_b_dst_data49)
    ,.sc2mac_wt_dst_data50            (sc2mac_wt_b_dst_data50)
    ,.sc2mac_wt_dst_data51            (sc2mac_wt_b_dst_data51)
    ,.sc2mac_wt_dst_data52            (sc2mac_wt_b_dst_data52)
    ,.sc2mac_wt_dst_data53            (sc2mac_wt_b_dst_data53)
    ,.sc2mac_wt_dst_data54            (sc2mac_wt_b_dst_data54)
    ,.sc2mac_wt_dst_data55            (sc2mac_wt_b_dst_data55)
    ,.sc2mac_wt_dst_data56            (sc2mac_wt_b_dst_data56)
    ,.sc2mac_wt_dst_data57            (sc2mac_wt_b_dst_data57)
    ,.sc2mac_wt_dst_data58            (sc2mac_wt_b_dst_data58)
    ,.sc2mac_wt_dst_data59            (sc2mac_wt_b_dst_data59)
    ,.sc2mac_wt_dst_data60            (sc2mac_wt_b_dst_data60)
    ,.sc2mac_wt_dst_data61            (sc2mac_wt_b_dst_data61)
    ,.sc2mac_wt_dst_data62            (sc2mac_wt_b_dst_data62)
    ,.sc2mac_wt_dst_data63            (sc2mac_wt_b_dst_data63)
    ,.sc2mac_wt_dst_data64            (sc2mac_wt_b_dst_data64)
    ,.sc2mac_wt_dst_data65            (sc2mac_wt_b_dst_data65)
    ,.sc2mac_wt_dst_data66            (sc2mac_wt_b_dst_data66)
    ,.sc2mac_wt_dst_data67            (sc2mac_wt_b_dst_data67)
    ,.sc2mac_wt_dst_data68            (sc2mac_wt_b_dst_data68)
    ,.sc2mac_wt_dst_data69            (sc2mac_wt_b_dst_data69)
    ,.sc2mac_wt_dst_data70            (sc2mac_wt_b_dst_data70)
    ,.sc2mac_wt_dst_data71            (sc2mac_wt_b_dst_data71)
    ,.sc2mac_wt_dst_data72            (sc2mac_wt_b_dst_data72)
    ,.sc2mac_wt_dst_data73            (sc2mac_wt_b_dst_data73)
    ,.sc2mac_wt_dst_data74            (sc2mac_wt_b_dst_data74)
    ,.sc2mac_wt_dst_data75            (sc2mac_wt_b_dst_data75)
    ,.sc2mac_wt_dst_data76            (sc2mac_wt_b_dst_data76)
    ,.sc2mac_wt_dst_data77            (sc2mac_wt_b_dst_data77)
    ,.sc2mac_wt_dst_data78            (sc2mac_wt_b_dst_data78)
    ,.sc2mac_wt_dst_data79            (sc2mac_wt_b_dst_data79)
    ,.sc2mac_wt_dst_data80            (sc2mac_wt_b_dst_data80)
    ,.sc2mac_wt_dst_data81            (sc2mac_wt_b_dst_data81)
    ,.sc2mac_wt_dst_data82            (sc2mac_wt_b_dst_data82)
    ,.sc2mac_wt_dst_data83            (sc2mac_wt_b_dst_data83)
    ,.sc2mac_wt_dst_data84            (sc2mac_wt_b_dst_data84)
    ,.sc2mac_wt_dst_data85            (sc2mac_wt_b_dst_data85)
    ,.sc2mac_wt_dst_data86            (sc2mac_wt_b_dst_data86)
    ,.sc2mac_wt_dst_data87            (sc2mac_wt_b_dst_data87)
    ,.sc2mac_wt_dst_data88            (sc2mac_wt_b_dst_data88)
    ,.sc2mac_wt_dst_data89            (sc2mac_wt_b_dst_data89)
    ,.sc2mac_wt_dst_data90            (sc2mac_wt_b_dst_data90)
    ,.sc2mac_wt_dst_data91            (sc2mac_wt_b_dst_data91)
    ,.sc2mac_wt_dst_data92            (sc2mac_wt_b_dst_data92)
    ,.sc2mac_wt_dst_data93            (sc2mac_wt_b_dst_data93)
    ,.sc2mac_wt_dst_data94            (sc2mac_wt_b_dst_data94)
    ,.sc2mac_wt_dst_data95            (sc2mac_wt_b_dst_data95)
    ,.sc2mac_wt_dst_data96            (sc2mac_wt_b_dst_data96)
    ,.sc2mac_wt_dst_data97            (sc2mac_wt_b_dst_data97)
    ,.sc2mac_wt_dst_data98            (sc2mac_wt_b_dst_data98)
    ,.sc2mac_wt_dst_data99            (sc2mac_wt_b_dst_data99)
    ,.sc2mac_wt_dst_data100           (sc2mac_wt_b_dst_data100)
    ,.sc2mac_wt_dst_data101           (sc2mac_wt_b_dst_data101)
    ,.sc2mac_wt_dst_data102           (sc2mac_wt_b_dst_data102)
    ,.sc2mac_wt_dst_data103           (sc2mac_wt_b_dst_data103)
    ,.sc2mac_wt_dst_data104           (sc2mac_wt_b_dst_data104)
    ,.sc2mac_wt_dst_data105           (sc2mac_wt_b_dst_data105)
    ,.sc2mac_wt_dst_data106           (sc2mac_wt_b_dst_data106)
    ,.sc2mac_wt_dst_data107           (sc2mac_wt_b_dst_data107)
    ,.sc2mac_wt_dst_data108           (sc2mac_wt_b_dst_data108)
    ,.sc2mac_wt_dst_data109           (sc2mac_wt_b_dst_data109)
    ,.sc2mac_wt_dst_data110           (sc2mac_wt_b_dst_data110)
    ,.sc2mac_wt_dst_data111           (sc2mac_wt_b_dst_data111)
    ,.sc2mac_wt_dst_data112           (sc2mac_wt_b_dst_data112)
    ,.sc2mac_wt_dst_data113           (sc2mac_wt_b_dst_data113)
    ,.sc2mac_wt_dst_data114           (sc2mac_wt_b_dst_data114)
    ,.sc2mac_wt_dst_data115           (sc2mac_wt_b_dst_data115)
    ,.sc2mac_wt_dst_data116           (sc2mac_wt_b_dst_data116)
    ,.sc2mac_wt_dst_data117           (sc2mac_wt_b_dst_data117)
    ,.sc2mac_wt_dst_data118           (sc2mac_wt_b_dst_data118)
    ,.sc2mac_wt_dst_data119           (sc2mac_wt_b_dst_data119)
    ,.sc2mac_wt_dst_data120           (sc2mac_wt_b_dst_data120)
    ,.sc2mac_wt_dst_data121           (sc2mac_wt_b_dst_data121)
    ,.sc2mac_wt_dst_data122           (sc2mac_wt_b_dst_data122)
    ,.sc2mac_wt_dst_data123           (sc2mac_wt_b_dst_data123)
    ,.sc2mac_wt_dst_data124           (sc2mac_wt_b_dst_data124)
    ,.sc2mac_wt_dst_data125           (sc2mac_wt_b_dst_data125)
    ,.sc2mac_wt_dst_data126           (sc2mac_wt_b_dst_data126)
    ,.sc2mac_wt_dst_data127           (sc2mac_wt_b_dst_data127)
    ,.sc2mac_wt_dst_sel               (sc2mac_wt_b_dst_sel)
    ,.sc2mac_dat_dst_pvld             (sc2mac_dat_b_dst_pvld)
    ,.sc2mac_dat_dst_mask             (sc2mac_dat_b_dst_mask)
    ,.sc2mac_dat_dst_data0            (sc2mac_dat_b_dst_data0)
    ,.sc2mac_dat_dst_data1            (sc2mac_dat_b_dst_data1)
    ,.sc2mac_dat_dst_data2            (sc2mac_dat_b_dst_data2)
    ,.sc2mac_dat_dst_data3            (sc2mac_dat_b_dst_data3)
    ,.sc2mac_dat_dst_data4            (sc2mac_dat_b_dst_data4)
    ,.sc2mac_dat_dst_data5            (sc2mac_dat_b_dst_data5)
    ,.sc2mac_dat_dst_data6            (sc2mac_dat_b_dst_data6)
    ,.sc2mac_dat_dst_data7            (sc2mac_dat_b_dst_data7)
    ,.sc2mac_dat_dst_data8            (sc2mac_dat_b_dst_data8)
    ,.sc2mac_dat_dst_data9            (sc2mac_dat_b_dst_data9)
    ,.sc2mac_dat_dst_data10           (sc2mac_dat_b_dst_data10)
    ,.sc2mac_dat_dst_data11           (sc2mac_dat_b_dst_data11)
    ,.sc2mac_dat_dst_data12           (sc2mac_dat_b_dst_data12)
    ,.sc2mac_dat_dst_data13           (sc2mac_dat_b_dst_data13)
    ,.sc2mac_dat_dst_data14           (sc2mac_dat_b_dst_data14)
    ,.sc2mac_dat_dst_data15           (sc2mac_dat_b_dst_data15)
    ,.sc2mac_dat_dst_data16           (sc2mac_dat_b_dst_data16)
    ,.sc2mac_dat_dst_data17           (sc2mac_dat_b_dst_data17)
    ,.sc2mac_dat_dst_data18           (sc2mac_dat_b_dst_data18)
    ,.sc2mac_dat_dst_data19           (sc2mac_dat_b_dst_data19)
    ,.sc2mac_dat_dst_data20           (sc2mac_dat_b_dst_data20)
    ,.sc2mac_dat_dst_data21           (sc2mac_dat_b_dst_data21)
    ,.sc2mac_dat_dst_data22           (sc2mac_dat_b_dst_data22)
    ,.sc2mac_dat_dst_data23           (sc2mac_dat_b_dst_data23)
    ,.sc2mac_dat_dst_data24           (sc2mac_dat_b_dst_data24)
    ,.sc2mac_dat_dst_data25           (sc2mac_dat_b_dst_data25)
    ,.sc2mac_dat_dst_data26           (sc2mac_dat_b_dst_data26)
    ,.sc2mac_dat_dst_data27           (sc2mac_dat_b_dst_data27)
    ,.sc2mac_dat_dst_data28           (sc2mac_dat_b_dst_data28)
    ,.sc2mac_dat_dst_data29           (sc2mac_dat_b_dst_data29)
    ,.sc2mac_dat_dst_data30           (sc2mac_dat_b_dst_data30)
    ,.sc2mac_dat_dst_data31           (sc2mac_dat_b_dst_data31)
    ,.sc2mac_dat_dst_data32           (sc2mac_dat_b_dst_data32)
    ,.sc2mac_dat_dst_data33           (sc2mac_dat_b_dst_data33)
    ,.sc2mac_dat_dst_data34           (sc2mac_dat_b_dst_data34)
    ,.sc2mac_dat_dst_data35           (sc2mac_dat_b_dst_data35)
    ,.sc2mac_dat_dst_data36           (sc2mac_dat_b_dst_data36)
    ,.sc2mac_dat_dst_data37           (sc2mac_dat_b_dst_data37)
    ,.sc2mac_dat_dst_data38           (sc2mac_dat_b_dst_data38)
    ,.sc2mac_dat_dst_data39           (sc2mac_dat_b_dst_data39)
    ,.sc2mac_dat_dst_data40           (sc2mac_dat_b_dst_data40)
    ,.sc2mac_dat_dst_data41           (sc2mac_dat_b_dst_data41)
    ,.sc2mac_dat_dst_data42           (sc2mac_dat_b_dst_data42)
    ,.sc2mac_dat_dst_data43           (sc2mac_dat_b_dst_data43)
    ,.sc2mac_dat_dst_data44           (sc2mac_dat_b_dst_data44)
    ,.sc2mac_dat_dst_data45           (sc2mac_dat_b_dst_data45)
    ,.sc2mac_dat_dst_data46           (sc2mac_dat_b_dst_data46)
    ,.sc2mac_dat_dst_data47           (sc2mac_dat_b_dst_data47)
    ,.sc2mac_dat_dst_data48           (sc2mac_dat_b_dst_data48)
    ,.sc2mac_dat_dst_data49           (sc2mac_dat_b_dst_data49)
    ,.sc2mac_dat_dst_data50           (sc2mac_dat_b_dst_data50)
    ,.sc2mac_dat_dst_data51           (sc2mac_dat_b_dst_data51)
    ,.sc2mac_dat_dst_data52           (sc2mac_dat_b_dst_data52)
    ,.sc2mac_dat_dst_data53           (sc2mac_dat_b_dst_data53)
    ,.sc2mac_dat_dst_data54           (sc2mac_dat_b_dst_data54)
    ,.sc2mac_dat_dst_data55           (sc2mac_dat_b_dst_data55)
    ,.sc2mac_dat_dst_data56           (sc2mac_dat_b_dst_data56)
    ,.sc2mac_dat_dst_data57           (sc2mac_dat_b_dst_data57)
    ,.sc2mac_dat_dst_data58           (sc2mac_dat_b_dst_data58)
    ,.sc2mac_dat_dst_data59           (sc2mac_dat_b_dst_data59)
    ,.sc2mac_dat_dst_data60           (sc2mac_dat_b_dst_data60)
    ,.sc2mac_dat_dst_data61           (sc2mac_dat_b_dst_data61)
    ,.sc2mac_dat_dst_data62           (sc2mac_dat_b_dst_data62)
    ,.sc2mac_dat_dst_data63           (sc2mac_dat_b_dst_data63)
    ,.sc2mac_dat_dst_data64           (sc2mac_dat_b_dst_data64)
    ,.sc2mac_dat_dst_data65           (sc2mac_dat_b_dst_data65)
    ,.sc2mac_dat_dst_data66           (sc2mac_dat_b_dst_data66)
    ,.sc2mac_dat_dst_data67           (sc2mac_dat_b_dst_data67)
    ,.sc2mac_dat_dst_data68           (sc2mac_dat_b_dst_data68)
    ,.sc2mac_dat_dst_data69           (sc2mac_dat_b_dst_data69)
    ,.sc2mac_dat_dst_data70           (sc2mac_dat_b_dst_data70)
    ,.sc2mac_dat_dst_data71           (sc2mac_dat_b_dst_data71)
    ,.sc2mac_dat_dst_data72           (sc2mac_dat_b_dst_data72)
    ,.sc2mac_dat_dst_data73           (sc2mac_dat_b_dst_data73)
    ,.sc2mac_dat_dst_data74           (sc2mac_dat_b_dst_data74)
    ,.sc2mac_dat_dst_data75           (sc2mac_dat_b_dst_data75)
    ,.sc2mac_dat_dst_data76           (sc2mac_dat_b_dst_data76)
    ,.sc2mac_dat_dst_data77           (sc2mac_dat_b_dst_data77)
    ,.sc2mac_dat_dst_data78           (sc2mac_dat_b_dst_data78)
    ,.sc2mac_dat_dst_data79           (sc2mac_dat_b_dst_data79)
    ,.sc2mac_dat_dst_data80           (sc2mac_dat_b_dst_data80)
    ,.sc2mac_dat_dst_data81           (sc2mac_dat_b_dst_data81)
    ,.sc2mac_dat_dst_data82           (sc2mac_dat_b_dst_data82)
    ,.sc2mac_dat_dst_data83           (sc2mac_dat_b_dst_data83)
    ,.sc2mac_dat_dst_data84           (sc2mac_dat_b_dst_data84)
    ,.sc2mac_dat_dst_data85           (sc2mac_dat_b_dst_data85)
    ,.sc2mac_dat_dst_data86           (sc2mac_dat_b_dst_data86)
    ,.sc2mac_dat_dst_data87           (sc2mac_dat_b_dst_data87)
    ,.sc2mac_dat_dst_data88           (sc2mac_dat_b_dst_data88)
    ,.sc2mac_dat_dst_data89           (sc2mac_dat_b_dst_data89)
    ,.sc2mac_dat_dst_data90           (sc2mac_dat_b_dst_data90)
    ,.sc2mac_dat_dst_data91           (sc2mac_dat_b_dst_data91)
    ,.sc2mac_dat_dst_data92           (sc2mac_dat_b_dst_data92)
    ,.sc2mac_dat_dst_data93           (sc2mac_dat_b_dst_data93)
    ,.sc2mac_dat_dst_data94           (sc2mac_dat_b_dst_data94)
    ,.sc2mac_dat_dst_data95           (sc2mac_dat_b_dst_data95)
    ,.sc2mac_dat_dst_data96           (sc2mac_dat_b_dst_data96)
    ,.sc2mac_dat_dst_data97           (sc2mac_dat_b_dst_data97)
    ,.sc2mac_dat_dst_data98           (sc2mac_dat_b_dst_data98)
    ,.sc2mac_dat_dst_data99           (sc2mac_dat_b_dst_data99)
    ,.sc2mac_dat_dst_data100          (sc2mac_dat_b_dst_data100)
    ,.sc2mac_dat_dst_data101          (sc2mac_dat_b_dst_data101)
    ,.sc2mac_dat_dst_data102          (sc2mac_dat_b_dst_data102)
    ,.sc2mac_dat_dst_data103          (sc2mac_dat_b_dst_data103)
    ,.sc2mac_dat_dst_data104          (sc2mac_dat_b_dst_data104)
    ,.sc2mac_dat_dst_data105          (sc2mac_dat_b_dst_data105)
    ,.sc2mac_dat_dst_data106          (sc2mac_dat_b_dst_data106)
    ,.sc2mac_dat_dst_data107          (sc2mac_dat_b_dst_data107)
    ,.sc2mac_dat_dst_data108          (sc2mac_dat_b_dst_data108)
    ,.sc2mac_dat_dst_data109          (sc2mac_dat_b_dst_data109)
    ,.sc2mac_dat_dst_data110          (sc2mac_dat_b_dst_data110)
    ,.sc2mac_dat_dst_data111          (sc2mac_dat_b_dst_data111)
    ,.sc2mac_dat_dst_data112          (sc2mac_dat_b_dst_data112)
    ,.sc2mac_dat_dst_data113          (sc2mac_dat_b_dst_data113)
    ,.sc2mac_dat_dst_data114          (sc2mac_dat_b_dst_data114)
    ,.sc2mac_dat_dst_data115          (sc2mac_dat_b_dst_data115)
    ,.sc2mac_dat_dst_data116          (sc2mac_dat_b_dst_data116)
    ,.sc2mac_dat_dst_data117          (sc2mac_dat_b_dst_data117)
    ,.sc2mac_dat_dst_data118          (sc2mac_dat_b_dst_data118)
    ,.sc2mac_dat_dst_data119          (sc2mac_dat_b_dst_data119)
    ,.sc2mac_dat_dst_data120          (sc2mac_dat_b_dst_data120)
    ,.sc2mac_dat_dst_data121          (sc2mac_dat_b_dst_data121)
    ,.sc2mac_dat_dst_data122          (sc2mac_dat_b_dst_data122)
    ,.sc2mac_dat_dst_data123          (sc2mac_dat_b_dst_data123)
    ,.sc2mac_dat_dst_data124          (sc2mac_dat_b_dst_data124)
    ,.sc2mac_dat_dst_data125          (sc2mac_dat_b_dst_data125)
    ,.sc2mac_dat_dst_data126          (sc2mac_dat_b_dst_data126)
    ,.sc2mac_dat_dst_data127          (sc2mac_dat_b_dst_data127)
    ,.sc2mac_dat_dst_pd               (sc2mac_dat_b_dst_pd)
  );

  // ---------------- DUT：cmac A/B（模块端口同名，外部连线区分） ----------
  NV_NVDLA_cmac u_NV_NVDLA_cmac_a (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.cmac_a2csb_resp_valid           (cmac_a2csb_resp_valid)
    ,.cmac_a2csb_resp_pd              (cmac_a2csb_resp_pd)
    ,.csb2cmac_a_req_pvld             (csb2cmac_a_req_pvld)
    ,.csb2cmac_a_req_prdy             (csb2cmac_a_req_prdy)
    ,.csb2cmac_a_req_pd               (csb2cmac_a_req_pd)
    ,.mac2accu_pvld                   (mac_a2accu_src_pvld)
    ,.mac2accu_mask                   (mac_a2accu_src_mask)
    ,.mac2accu_mode                   (mac_a2accu_src_mode)
    ,.mac2accu_data0                  (mac_a2accu_src_data0)
    ,.mac2accu_data1                  (mac_a2accu_src_data1)
    ,.mac2accu_data2                  (mac_a2accu_src_data2)
    ,.mac2accu_data3                  (mac_a2accu_src_data3)
    ,.mac2accu_data4                  (mac_a2accu_src_data4)
    ,.mac2accu_data5                  (mac_a2accu_src_data5)
    ,.mac2accu_data6                  (mac_a2accu_src_data6)
    ,.mac2accu_data7                  (mac_a2accu_src_data7)
    ,.mac2accu_pd                     (mac_a2accu_src_pd)
    ,.sc2mac_dat_pvld                 (sc2mac_dat_a_dst_pvld)
    ,.sc2mac_dat_mask                 (sc2mac_dat_a_dst_mask)
    ,.sc2mac_dat_data0                (sc2mac_dat_a_dst_data0)
    ,.sc2mac_dat_data1                (sc2mac_dat_a_dst_data1)
    ,.sc2mac_dat_data2                (sc2mac_dat_a_dst_data2)
    ,.sc2mac_dat_data3                (sc2mac_dat_a_dst_data3)
    ,.sc2mac_dat_data4                (sc2mac_dat_a_dst_data4)
    ,.sc2mac_dat_data5                (sc2mac_dat_a_dst_data5)
    ,.sc2mac_dat_data6                (sc2mac_dat_a_dst_data6)
    ,.sc2mac_dat_data7                (sc2mac_dat_a_dst_data7)
    ,.sc2mac_dat_data8                (sc2mac_dat_a_dst_data8)
    ,.sc2mac_dat_data9                (sc2mac_dat_a_dst_data9)
    ,.sc2mac_dat_data10               (sc2mac_dat_a_dst_data10)
    ,.sc2mac_dat_data11               (sc2mac_dat_a_dst_data11)
    ,.sc2mac_dat_data12               (sc2mac_dat_a_dst_data12)
    ,.sc2mac_dat_data13               (sc2mac_dat_a_dst_data13)
    ,.sc2mac_dat_data14               (sc2mac_dat_a_dst_data14)
    ,.sc2mac_dat_data15               (sc2mac_dat_a_dst_data15)
    ,.sc2mac_dat_data16               (sc2mac_dat_a_dst_data16)
    ,.sc2mac_dat_data17               (sc2mac_dat_a_dst_data17)
    ,.sc2mac_dat_data18               (sc2mac_dat_a_dst_data18)
    ,.sc2mac_dat_data19               (sc2mac_dat_a_dst_data19)
    ,.sc2mac_dat_data20               (sc2mac_dat_a_dst_data20)
    ,.sc2mac_dat_data21               (sc2mac_dat_a_dst_data21)
    ,.sc2mac_dat_data22               (sc2mac_dat_a_dst_data22)
    ,.sc2mac_dat_data23               (sc2mac_dat_a_dst_data23)
    ,.sc2mac_dat_data24               (sc2mac_dat_a_dst_data24)
    ,.sc2mac_dat_data25               (sc2mac_dat_a_dst_data25)
    ,.sc2mac_dat_data26               (sc2mac_dat_a_dst_data26)
    ,.sc2mac_dat_data27               (sc2mac_dat_a_dst_data27)
    ,.sc2mac_dat_data28               (sc2mac_dat_a_dst_data28)
    ,.sc2mac_dat_data29               (sc2mac_dat_a_dst_data29)
    ,.sc2mac_dat_data30               (sc2mac_dat_a_dst_data30)
    ,.sc2mac_dat_data31               (sc2mac_dat_a_dst_data31)
    ,.sc2mac_dat_data32               (sc2mac_dat_a_dst_data32)
    ,.sc2mac_dat_data33               (sc2mac_dat_a_dst_data33)
    ,.sc2mac_dat_data34               (sc2mac_dat_a_dst_data34)
    ,.sc2mac_dat_data35               (sc2mac_dat_a_dst_data35)
    ,.sc2mac_dat_data36               (sc2mac_dat_a_dst_data36)
    ,.sc2mac_dat_data37               (sc2mac_dat_a_dst_data37)
    ,.sc2mac_dat_data38               (sc2mac_dat_a_dst_data38)
    ,.sc2mac_dat_data39               (sc2mac_dat_a_dst_data39)
    ,.sc2mac_dat_data40               (sc2mac_dat_a_dst_data40)
    ,.sc2mac_dat_data41               (sc2mac_dat_a_dst_data41)
    ,.sc2mac_dat_data42               (sc2mac_dat_a_dst_data42)
    ,.sc2mac_dat_data43               (sc2mac_dat_a_dst_data43)
    ,.sc2mac_dat_data44               (sc2mac_dat_a_dst_data44)
    ,.sc2mac_dat_data45               (sc2mac_dat_a_dst_data45)
    ,.sc2mac_dat_data46               (sc2mac_dat_a_dst_data46)
    ,.sc2mac_dat_data47               (sc2mac_dat_a_dst_data47)
    ,.sc2mac_dat_data48               (sc2mac_dat_a_dst_data48)
    ,.sc2mac_dat_data49               (sc2mac_dat_a_dst_data49)
    ,.sc2mac_dat_data50               (sc2mac_dat_a_dst_data50)
    ,.sc2mac_dat_data51               (sc2mac_dat_a_dst_data51)
    ,.sc2mac_dat_data52               (sc2mac_dat_a_dst_data52)
    ,.sc2mac_dat_data53               (sc2mac_dat_a_dst_data53)
    ,.sc2mac_dat_data54               (sc2mac_dat_a_dst_data54)
    ,.sc2mac_dat_data55               (sc2mac_dat_a_dst_data55)
    ,.sc2mac_dat_data56               (sc2mac_dat_a_dst_data56)
    ,.sc2mac_dat_data57               (sc2mac_dat_a_dst_data57)
    ,.sc2mac_dat_data58               (sc2mac_dat_a_dst_data58)
    ,.sc2mac_dat_data59               (sc2mac_dat_a_dst_data59)
    ,.sc2mac_dat_data60               (sc2mac_dat_a_dst_data60)
    ,.sc2mac_dat_data61               (sc2mac_dat_a_dst_data61)
    ,.sc2mac_dat_data62               (sc2mac_dat_a_dst_data62)
    ,.sc2mac_dat_data63               (sc2mac_dat_a_dst_data63)
    ,.sc2mac_dat_data64               (sc2mac_dat_a_dst_data64)
    ,.sc2mac_dat_data65               (sc2mac_dat_a_dst_data65)
    ,.sc2mac_dat_data66               (sc2mac_dat_a_dst_data66)
    ,.sc2mac_dat_data67               (sc2mac_dat_a_dst_data67)
    ,.sc2mac_dat_data68               (sc2mac_dat_a_dst_data68)
    ,.sc2mac_dat_data69               (sc2mac_dat_a_dst_data69)
    ,.sc2mac_dat_data70               (sc2mac_dat_a_dst_data70)
    ,.sc2mac_dat_data71               (sc2mac_dat_a_dst_data71)
    ,.sc2mac_dat_data72               (sc2mac_dat_a_dst_data72)
    ,.sc2mac_dat_data73               (sc2mac_dat_a_dst_data73)
    ,.sc2mac_dat_data74               (sc2mac_dat_a_dst_data74)
    ,.sc2mac_dat_data75               (sc2mac_dat_a_dst_data75)
    ,.sc2mac_dat_data76               (sc2mac_dat_a_dst_data76)
    ,.sc2mac_dat_data77               (sc2mac_dat_a_dst_data77)
    ,.sc2mac_dat_data78               (sc2mac_dat_a_dst_data78)
    ,.sc2mac_dat_data79               (sc2mac_dat_a_dst_data79)
    ,.sc2mac_dat_data80               (sc2mac_dat_a_dst_data80)
    ,.sc2mac_dat_data81               (sc2mac_dat_a_dst_data81)
    ,.sc2mac_dat_data82               (sc2mac_dat_a_dst_data82)
    ,.sc2mac_dat_data83               (sc2mac_dat_a_dst_data83)
    ,.sc2mac_dat_data84               (sc2mac_dat_a_dst_data84)
    ,.sc2mac_dat_data85               (sc2mac_dat_a_dst_data85)
    ,.sc2mac_dat_data86               (sc2mac_dat_a_dst_data86)
    ,.sc2mac_dat_data87               (sc2mac_dat_a_dst_data87)
    ,.sc2mac_dat_data88               (sc2mac_dat_a_dst_data88)
    ,.sc2mac_dat_data89               (sc2mac_dat_a_dst_data89)
    ,.sc2mac_dat_data90               (sc2mac_dat_a_dst_data90)
    ,.sc2mac_dat_data91               (sc2mac_dat_a_dst_data91)
    ,.sc2mac_dat_data92               (sc2mac_dat_a_dst_data92)
    ,.sc2mac_dat_data93               (sc2mac_dat_a_dst_data93)
    ,.sc2mac_dat_data94               (sc2mac_dat_a_dst_data94)
    ,.sc2mac_dat_data95               (sc2mac_dat_a_dst_data95)
    ,.sc2mac_dat_data96               (sc2mac_dat_a_dst_data96)
    ,.sc2mac_dat_data97               (sc2mac_dat_a_dst_data97)
    ,.sc2mac_dat_data98               (sc2mac_dat_a_dst_data98)
    ,.sc2mac_dat_data99               (sc2mac_dat_a_dst_data99)
    ,.sc2mac_dat_data100              (sc2mac_dat_a_dst_data100)
    ,.sc2mac_dat_data101              (sc2mac_dat_a_dst_data101)
    ,.sc2mac_dat_data102              (sc2mac_dat_a_dst_data102)
    ,.sc2mac_dat_data103              (sc2mac_dat_a_dst_data103)
    ,.sc2mac_dat_data104              (sc2mac_dat_a_dst_data104)
    ,.sc2mac_dat_data105              (sc2mac_dat_a_dst_data105)
    ,.sc2mac_dat_data106              (sc2mac_dat_a_dst_data106)
    ,.sc2mac_dat_data107              (sc2mac_dat_a_dst_data107)
    ,.sc2mac_dat_data108              (sc2mac_dat_a_dst_data108)
    ,.sc2mac_dat_data109              (sc2mac_dat_a_dst_data109)
    ,.sc2mac_dat_data110              (sc2mac_dat_a_dst_data110)
    ,.sc2mac_dat_data111              (sc2mac_dat_a_dst_data111)
    ,.sc2mac_dat_data112              (sc2mac_dat_a_dst_data112)
    ,.sc2mac_dat_data113              (sc2mac_dat_a_dst_data113)
    ,.sc2mac_dat_data114              (sc2mac_dat_a_dst_data114)
    ,.sc2mac_dat_data115              (sc2mac_dat_a_dst_data115)
    ,.sc2mac_dat_data116              (sc2mac_dat_a_dst_data116)
    ,.sc2mac_dat_data117              (sc2mac_dat_a_dst_data117)
    ,.sc2mac_dat_data118              (sc2mac_dat_a_dst_data118)
    ,.sc2mac_dat_data119              (sc2mac_dat_a_dst_data119)
    ,.sc2mac_dat_data120              (sc2mac_dat_a_dst_data120)
    ,.sc2mac_dat_data121              (sc2mac_dat_a_dst_data121)
    ,.sc2mac_dat_data122              (sc2mac_dat_a_dst_data122)
    ,.sc2mac_dat_data123              (sc2mac_dat_a_dst_data123)
    ,.sc2mac_dat_data124              (sc2mac_dat_a_dst_data124)
    ,.sc2mac_dat_data125              (sc2mac_dat_a_dst_data125)
    ,.sc2mac_dat_data126              (sc2mac_dat_a_dst_data126)
    ,.sc2mac_dat_data127              (sc2mac_dat_a_dst_data127)
    ,.sc2mac_dat_pd                   (sc2mac_dat_a_dst_pd)
    ,.sc2mac_wt_pvld                  (sc2mac_wt_a_dst_pvld)
    ,.sc2mac_wt_mask                  (sc2mac_wt_a_dst_mask)
    ,.sc2mac_wt_data0                 (sc2mac_wt_a_dst_data0)
    ,.sc2mac_wt_data1                 (sc2mac_wt_a_dst_data1)
    ,.sc2mac_wt_data2                 (sc2mac_wt_a_dst_data2)
    ,.sc2mac_wt_data3                 (sc2mac_wt_a_dst_data3)
    ,.sc2mac_wt_data4                 (sc2mac_wt_a_dst_data4)
    ,.sc2mac_wt_data5                 (sc2mac_wt_a_dst_data5)
    ,.sc2mac_wt_data6                 (sc2mac_wt_a_dst_data6)
    ,.sc2mac_wt_data7                 (sc2mac_wt_a_dst_data7)
    ,.sc2mac_wt_data8                 (sc2mac_wt_a_dst_data8)
    ,.sc2mac_wt_data9                 (sc2mac_wt_a_dst_data9)
    ,.sc2mac_wt_data10                (sc2mac_wt_a_dst_data10)
    ,.sc2mac_wt_data11                (sc2mac_wt_a_dst_data11)
    ,.sc2mac_wt_data12                (sc2mac_wt_a_dst_data12)
    ,.sc2mac_wt_data13                (sc2mac_wt_a_dst_data13)
    ,.sc2mac_wt_data14                (sc2mac_wt_a_dst_data14)
    ,.sc2mac_wt_data15                (sc2mac_wt_a_dst_data15)
    ,.sc2mac_wt_data16                (sc2mac_wt_a_dst_data16)
    ,.sc2mac_wt_data17                (sc2mac_wt_a_dst_data17)
    ,.sc2mac_wt_data18                (sc2mac_wt_a_dst_data18)
    ,.sc2mac_wt_data19                (sc2mac_wt_a_dst_data19)
    ,.sc2mac_wt_data20                (sc2mac_wt_a_dst_data20)
    ,.sc2mac_wt_data21                (sc2mac_wt_a_dst_data21)
    ,.sc2mac_wt_data22                (sc2mac_wt_a_dst_data22)
    ,.sc2mac_wt_data23                (sc2mac_wt_a_dst_data23)
    ,.sc2mac_wt_data24                (sc2mac_wt_a_dst_data24)
    ,.sc2mac_wt_data25                (sc2mac_wt_a_dst_data25)
    ,.sc2mac_wt_data26                (sc2mac_wt_a_dst_data26)
    ,.sc2mac_wt_data27                (sc2mac_wt_a_dst_data27)
    ,.sc2mac_wt_data28                (sc2mac_wt_a_dst_data28)
    ,.sc2mac_wt_data29                (sc2mac_wt_a_dst_data29)
    ,.sc2mac_wt_data30                (sc2mac_wt_a_dst_data30)
    ,.sc2mac_wt_data31                (sc2mac_wt_a_dst_data31)
    ,.sc2mac_wt_data32                (sc2mac_wt_a_dst_data32)
    ,.sc2mac_wt_data33                (sc2mac_wt_a_dst_data33)
    ,.sc2mac_wt_data34                (sc2mac_wt_a_dst_data34)
    ,.sc2mac_wt_data35                (sc2mac_wt_a_dst_data35)
    ,.sc2mac_wt_data36                (sc2mac_wt_a_dst_data36)
    ,.sc2mac_wt_data37                (sc2mac_wt_a_dst_data37)
    ,.sc2mac_wt_data38                (sc2mac_wt_a_dst_data38)
    ,.sc2mac_wt_data39                (sc2mac_wt_a_dst_data39)
    ,.sc2mac_wt_data40                (sc2mac_wt_a_dst_data40)
    ,.sc2mac_wt_data41                (sc2mac_wt_a_dst_data41)
    ,.sc2mac_wt_data42                (sc2mac_wt_a_dst_data42)
    ,.sc2mac_wt_data43                (sc2mac_wt_a_dst_data43)
    ,.sc2mac_wt_data44                (sc2mac_wt_a_dst_data44)
    ,.sc2mac_wt_data45                (sc2mac_wt_a_dst_data45)
    ,.sc2mac_wt_data46                (sc2mac_wt_a_dst_data46)
    ,.sc2mac_wt_data47                (sc2mac_wt_a_dst_data47)
    ,.sc2mac_wt_data48                (sc2mac_wt_a_dst_data48)
    ,.sc2mac_wt_data49                (sc2mac_wt_a_dst_data49)
    ,.sc2mac_wt_data50                (sc2mac_wt_a_dst_data50)
    ,.sc2mac_wt_data51                (sc2mac_wt_a_dst_data51)
    ,.sc2mac_wt_data52                (sc2mac_wt_a_dst_data52)
    ,.sc2mac_wt_data53                (sc2mac_wt_a_dst_data53)
    ,.sc2mac_wt_data54                (sc2mac_wt_a_dst_data54)
    ,.sc2mac_wt_data55                (sc2mac_wt_a_dst_data55)
    ,.sc2mac_wt_data56                (sc2mac_wt_a_dst_data56)
    ,.sc2mac_wt_data57                (sc2mac_wt_a_dst_data57)
    ,.sc2mac_wt_data58                (sc2mac_wt_a_dst_data58)
    ,.sc2mac_wt_data59                (sc2mac_wt_a_dst_data59)
    ,.sc2mac_wt_data60                (sc2mac_wt_a_dst_data60)
    ,.sc2mac_wt_data61                (sc2mac_wt_a_dst_data61)
    ,.sc2mac_wt_data62                (sc2mac_wt_a_dst_data62)
    ,.sc2mac_wt_data63                (sc2mac_wt_a_dst_data63)
    ,.sc2mac_wt_data64                (sc2mac_wt_a_dst_data64)
    ,.sc2mac_wt_data65                (sc2mac_wt_a_dst_data65)
    ,.sc2mac_wt_data66                (sc2mac_wt_a_dst_data66)
    ,.sc2mac_wt_data67                (sc2mac_wt_a_dst_data67)
    ,.sc2mac_wt_data68                (sc2mac_wt_a_dst_data68)
    ,.sc2mac_wt_data69                (sc2mac_wt_a_dst_data69)
    ,.sc2mac_wt_data70                (sc2mac_wt_a_dst_data70)
    ,.sc2mac_wt_data71                (sc2mac_wt_a_dst_data71)
    ,.sc2mac_wt_data72                (sc2mac_wt_a_dst_data72)
    ,.sc2mac_wt_data73                (sc2mac_wt_a_dst_data73)
    ,.sc2mac_wt_data74                (sc2mac_wt_a_dst_data74)
    ,.sc2mac_wt_data75                (sc2mac_wt_a_dst_data75)
    ,.sc2mac_wt_data76                (sc2mac_wt_a_dst_data76)
    ,.sc2mac_wt_data77                (sc2mac_wt_a_dst_data77)
    ,.sc2mac_wt_data78                (sc2mac_wt_a_dst_data78)
    ,.sc2mac_wt_data79                (sc2mac_wt_a_dst_data79)
    ,.sc2mac_wt_data80                (sc2mac_wt_a_dst_data80)
    ,.sc2mac_wt_data81                (sc2mac_wt_a_dst_data81)
    ,.sc2mac_wt_data82                (sc2mac_wt_a_dst_data82)
    ,.sc2mac_wt_data83                (sc2mac_wt_a_dst_data83)
    ,.sc2mac_wt_data84                (sc2mac_wt_a_dst_data84)
    ,.sc2mac_wt_data85                (sc2mac_wt_a_dst_data85)
    ,.sc2mac_wt_data86                (sc2mac_wt_a_dst_data86)
    ,.sc2mac_wt_data87                (sc2mac_wt_a_dst_data87)
    ,.sc2mac_wt_data88                (sc2mac_wt_a_dst_data88)
    ,.sc2mac_wt_data89                (sc2mac_wt_a_dst_data89)
    ,.sc2mac_wt_data90                (sc2mac_wt_a_dst_data90)
    ,.sc2mac_wt_data91                (sc2mac_wt_a_dst_data91)
    ,.sc2mac_wt_data92                (sc2mac_wt_a_dst_data92)
    ,.sc2mac_wt_data93                (sc2mac_wt_a_dst_data93)
    ,.sc2mac_wt_data94                (sc2mac_wt_a_dst_data94)
    ,.sc2mac_wt_data95                (sc2mac_wt_a_dst_data95)
    ,.sc2mac_wt_data96                (sc2mac_wt_a_dst_data96)
    ,.sc2mac_wt_data97                (sc2mac_wt_a_dst_data97)
    ,.sc2mac_wt_data98                (sc2mac_wt_a_dst_data98)
    ,.sc2mac_wt_data99                (sc2mac_wt_a_dst_data99)
    ,.sc2mac_wt_data100               (sc2mac_wt_a_dst_data100)
    ,.sc2mac_wt_data101               (sc2mac_wt_a_dst_data101)
    ,.sc2mac_wt_data102               (sc2mac_wt_a_dst_data102)
    ,.sc2mac_wt_data103               (sc2mac_wt_a_dst_data103)
    ,.sc2mac_wt_data104               (sc2mac_wt_a_dst_data104)
    ,.sc2mac_wt_data105               (sc2mac_wt_a_dst_data105)
    ,.sc2mac_wt_data106               (sc2mac_wt_a_dst_data106)
    ,.sc2mac_wt_data107               (sc2mac_wt_a_dst_data107)
    ,.sc2mac_wt_data108               (sc2mac_wt_a_dst_data108)
    ,.sc2mac_wt_data109               (sc2mac_wt_a_dst_data109)
    ,.sc2mac_wt_data110               (sc2mac_wt_a_dst_data110)
    ,.sc2mac_wt_data111               (sc2mac_wt_a_dst_data111)
    ,.sc2mac_wt_data112               (sc2mac_wt_a_dst_data112)
    ,.sc2mac_wt_data113               (sc2mac_wt_a_dst_data113)
    ,.sc2mac_wt_data114               (sc2mac_wt_a_dst_data114)
    ,.sc2mac_wt_data115               (sc2mac_wt_a_dst_data115)
    ,.sc2mac_wt_data116               (sc2mac_wt_a_dst_data116)
    ,.sc2mac_wt_data117               (sc2mac_wt_a_dst_data117)
    ,.sc2mac_wt_data118               (sc2mac_wt_a_dst_data118)
    ,.sc2mac_wt_data119               (sc2mac_wt_a_dst_data119)
    ,.sc2mac_wt_data120               (sc2mac_wt_a_dst_data120)
    ,.sc2mac_wt_data121               (sc2mac_wt_a_dst_data121)
    ,.sc2mac_wt_data122               (sc2mac_wt_a_dst_data122)
    ,.sc2mac_wt_data123               (sc2mac_wt_a_dst_data123)
    ,.sc2mac_wt_data124               (sc2mac_wt_a_dst_data124)
    ,.sc2mac_wt_data125               (sc2mac_wt_a_dst_data125)
    ,.sc2mac_wt_data126               (sc2mac_wt_a_dst_data126)
    ,.sc2mac_wt_data127               (sc2mac_wt_a_dst_data127)
    ,.sc2mac_wt_sel                   (sc2mac_wt_a_dst_sel)
    ,.dla_clk_ovr_on_sync             (1'b0)
    ,.global_clk_ovr_on_sync          (1'b0)
    ,.tmc2slcg_disable_clock_gating   (1'b1)
  );

  NV_NVDLA_cmac u_NV_NVDLA_cmac_b (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.cmac_a2csb_resp_valid           (cmac_b2csb_resp_valid)
    ,.cmac_a2csb_resp_pd              (cmac_b2csb_resp_pd)
    ,.csb2cmac_a_req_pvld             (csb2cmac_b_req_pvld)
    ,.csb2cmac_a_req_prdy             (csb2cmac_b_req_prdy)
    ,.csb2cmac_a_req_pd               (csb2cmac_b_req_pd)
    ,.mac2accu_pvld                   (mac_b2accu_src_pvld)
    ,.mac2accu_mask                   (mac_b2accu_src_mask)
    ,.mac2accu_mode                   (mac_b2accu_src_mode)
    ,.mac2accu_data0                  (mac_b2accu_src_data0)
    ,.mac2accu_data1                  (mac_b2accu_src_data1)
    ,.mac2accu_data2                  (mac_b2accu_src_data2)
    ,.mac2accu_data3                  (mac_b2accu_src_data3)
    ,.mac2accu_data4                  (mac_b2accu_src_data4)
    ,.mac2accu_data5                  (mac_b2accu_src_data5)
    ,.mac2accu_data6                  (mac_b2accu_src_data6)
    ,.mac2accu_data7                  (mac_b2accu_src_data7)
    ,.mac2accu_pd                     (mac_b2accu_src_pd)
    ,.sc2mac_dat_pvld                 (sc2mac_dat_b_dst_pvld)
    ,.sc2mac_dat_mask                 (sc2mac_dat_b_dst_mask)
    ,.sc2mac_dat_data0                (sc2mac_dat_b_dst_data0)
    ,.sc2mac_dat_data1                (sc2mac_dat_b_dst_data1)
    ,.sc2mac_dat_data2                (sc2mac_dat_b_dst_data2)
    ,.sc2mac_dat_data3                (sc2mac_dat_b_dst_data3)
    ,.sc2mac_dat_data4                (sc2mac_dat_b_dst_data4)
    ,.sc2mac_dat_data5                (sc2mac_dat_b_dst_data5)
    ,.sc2mac_dat_data6                (sc2mac_dat_b_dst_data6)
    ,.sc2mac_dat_data7                (sc2mac_dat_b_dst_data7)
    ,.sc2mac_dat_data8                (sc2mac_dat_b_dst_data8)
    ,.sc2mac_dat_data9                (sc2mac_dat_b_dst_data9)
    ,.sc2mac_dat_data10               (sc2mac_dat_b_dst_data10)
    ,.sc2mac_dat_data11               (sc2mac_dat_b_dst_data11)
    ,.sc2mac_dat_data12               (sc2mac_dat_b_dst_data12)
    ,.sc2mac_dat_data13               (sc2mac_dat_b_dst_data13)
    ,.sc2mac_dat_data14               (sc2mac_dat_b_dst_data14)
    ,.sc2mac_dat_data15               (sc2mac_dat_b_dst_data15)
    ,.sc2mac_dat_data16               (sc2mac_dat_b_dst_data16)
    ,.sc2mac_dat_data17               (sc2mac_dat_b_dst_data17)
    ,.sc2mac_dat_data18               (sc2mac_dat_b_dst_data18)
    ,.sc2mac_dat_data19               (sc2mac_dat_b_dst_data19)
    ,.sc2mac_dat_data20               (sc2mac_dat_b_dst_data20)
    ,.sc2mac_dat_data21               (sc2mac_dat_b_dst_data21)
    ,.sc2mac_dat_data22               (sc2mac_dat_b_dst_data22)
    ,.sc2mac_dat_data23               (sc2mac_dat_b_dst_data23)
    ,.sc2mac_dat_data24               (sc2mac_dat_b_dst_data24)
    ,.sc2mac_dat_data25               (sc2mac_dat_b_dst_data25)
    ,.sc2mac_dat_data26               (sc2mac_dat_b_dst_data26)
    ,.sc2mac_dat_data27               (sc2mac_dat_b_dst_data27)
    ,.sc2mac_dat_data28               (sc2mac_dat_b_dst_data28)
    ,.sc2mac_dat_data29               (sc2mac_dat_b_dst_data29)
    ,.sc2mac_dat_data30               (sc2mac_dat_b_dst_data30)
    ,.sc2mac_dat_data31               (sc2mac_dat_b_dst_data31)
    ,.sc2mac_dat_data32               (sc2mac_dat_b_dst_data32)
    ,.sc2mac_dat_data33               (sc2mac_dat_b_dst_data33)
    ,.sc2mac_dat_data34               (sc2mac_dat_b_dst_data34)
    ,.sc2mac_dat_data35               (sc2mac_dat_b_dst_data35)
    ,.sc2mac_dat_data36               (sc2mac_dat_b_dst_data36)
    ,.sc2mac_dat_data37               (sc2mac_dat_b_dst_data37)
    ,.sc2mac_dat_data38               (sc2mac_dat_b_dst_data38)
    ,.sc2mac_dat_data39               (sc2mac_dat_b_dst_data39)
    ,.sc2mac_dat_data40               (sc2mac_dat_b_dst_data40)
    ,.sc2mac_dat_data41               (sc2mac_dat_b_dst_data41)
    ,.sc2mac_dat_data42               (sc2mac_dat_b_dst_data42)
    ,.sc2mac_dat_data43               (sc2mac_dat_b_dst_data43)
    ,.sc2mac_dat_data44               (sc2mac_dat_b_dst_data44)
    ,.sc2mac_dat_data45               (sc2mac_dat_b_dst_data45)
    ,.sc2mac_dat_data46               (sc2mac_dat_b_dst_data46)
    ,.sc2mac_dat_data47               (sc2mac_dat_b_dst_data47)
    ,.sc2mac_dat_data48               (sc2mac_dat_b_dst_data48)
    ,.sc2mac_dat_data49               (sc2mac_dat_b_dst_data49)
    ,.sc2mac_dat_data50               (sc2mac_dat_b_dst_data50)
    ,.sc2mac_dat_data51               (sc2mac_dat_b_dst_data51)
    ,.sc2mac_dat_data52               (sc2mac_dat_b_dst_data52)
    ,.sc2mac_dat_data53               (sc2mac_dat_b_dst_data53)
    ,.sc2mac_dat_data54               (sc2mac_dat_b_dst_data54)
    ,.sc2mac_dat_data55               (sc2mac_dat_b_dst_data55)
    ,.sc2mac_dat_data56               (sc2mac_dat_b_dst_data56)
    ,.sc2mac_dat_data57               (sc2mac_dat_b_dst_data57)
    ,.sc2mac_dat_data58               (sc2mac_dat_b_dst_data58)
    ,.sc2mac_dat_data59               (sc2mac_dat_b_dst_data59)
    ,.sc2mac_dat_data60               (sc2mac_dat_b_dst_data60)
    ,.sc2mac_dat_data61               (sc2mac_dat_b_dst_data61)
    ,.sc2mac_dat_data62               (sc2mac_dat_b_dst_data62)
    ,.sc2mac_dat_data63               (sc2mac_dat_b_dst_data63)
    ,.sc2mac_dat_data64               (sc2mac_dat_b_dst_data64)
    ,.sc2mac_dat_data65               (sc2mac_dat_b_dst_data65)
    ,.sc2mac_dat_data66               (sc2mac_dat_b_dst_data66)
    ,.sc2mac_dat_data67               (sc2mac_dat_b_dst_data67)
    ,.sc2mac_dat_data68               (sc2mac_dat_b_dst_data68)
    ,.sc2mac_dat_data69               (sc2mac_dat_b_dst_data69)
    ,.sc2mac_dat_data70               (sc2mac_dat_b_dst_data70)
    ,.sc2mac_dat_data71               (sc2mac_dat_b_dst_data71)
    ,.sc2mac_dat_data72               (sc2mac_dat_b_dst_data72)
    ,.sc2mac_dat_data73               (sc2mac_dat_b_dst_data73)
    ,.sc2mac_dat_data74               (sc2mac_dat_b_dst_data74)
    ,.sc2mac_dat_data75               (sc2mac_dat_b_dst_data75)
    ,.sc2mac_dat_data76               (sc2mac_dat_b_dst_data76)
    ,.sc2mac_dat_data77               (sc2mac_dat_b_dst_data77)
    ,.sc2mac_dat_data78               (sc2mac_dat_b_dst_data78)
    ,.sc2mac_dat_data79               (sc2mac_dat_b_dst_data79)
    ,.sc2mac_dat_data80               (sc2mac_dat_b_dst_data80)
    ,.sc2mac_dat_data81               (sc2mac_dat_b_dst_data81)
    ,.sc2mac_dat_data82               (sc2mac_dat_b_dst_data82)
    ,.sc2mac_dat_data83               (sc2mac_dat_b_dst_data83)
    ,.sc2mac_dat_data84               (sc2mac_dat_b_dst_data84)
    ,.sc2mac_dat_data85               (sc2mac_dat_b_dst_data85)
    ,.sc2mac_dat_data86               (sc2mac_dat_b_dst_data86)
    ,.sc2mac_dat_data87               (sc2mac_dat_b_dst_data87)
    ,.sc2mac_dat_data88               (sc2mac_dat_b_dst_data88)
    ,.sc2mac_dat_data89               (sc2mac_dat_b_dst_data89)
    ,.sc2mac_dat_data90               (sc2mac_dat_b_dst_data90)
    ,.sc2mac_dat_data91               (sc2mac_dat_b_dst_data91)
    ,.sc2mac_dat_data92               (sc2mac_dat_b_dst_data92)
    ,.sc2mac_dat_data93               (sc2mac_dat_b_dst_data93)
    ,.sc2mac_dat_data94               (sc2mac_dat_b_dst_data94)
    ,.sc2mac_dat_data95               (sc2mac_dat_b_dst_data95)
    ,.sc2mac_dat_data96               (sc2mac_dat_b_dst_data96)
    ,.sc2mac_dat_data97               (sc2mac_dat_b_dst_data97)
    ,.sc2mac_dat_data98               (sc2mac_dat_b_dst_data98)
    ,.sc2mac_dat_data99               (sc2mac_dat_b_dst_data99)
    ,.sc2mac_dat_data100              (sc2mac_dat_b_dst_data100)
    ,.sc2mac_dat_data101              (sc2mac_dat_b_dst_data101)
    ,.sc2mac_dat_data102              (sc2mac_dat_b_dst_data102)
    ,.sc2mac_dat_data103              (sc2mac_dat_b_dst_data103)
    ,.sc2mac_dat_data104              (sc2mac_dat_b_dst_data104)
    ,.sc2mac_dat_data105              (sc2mac_dat_b_dst_data105)
    ,.sc2mac_dat_data106              (sc2mac_dat_b_dst_data106)
    ,.sc2mac_dat_data107              (sc2mac_dat_b_dst_data107)
    ,.sc2mac_dat_data108              (sc2mac_dat_b_dst_data108)
    ,.sc2mac_dat_data109              (sc2mac_dat_b_dst_data109)
    ,.sc2mac_dat_data110              (sc2mac_dat_b_dst_data110)
    ,.sc2mac_dat_data111              (sc2mac_dat_b_dst_data111)
    ,.sc2mac_dat_data112              (sc2mac_dat_b_dst_data112)
    ,.sc2mac_dat_data113              (sc2mac_dat_b_dst_data113)
    ,.sc2mac_dat_data114              (sc2mac_dat_b_dst_data114)
    ,.sc2mac_dat_data115              (sc2mac_dat_b_dst_data115)
    ,.sc2mac_dat_data116              (sc2mac_dat_b_dst_data116)
    ,.sc2mac_dat_data117              (sc2mac_dat_b_dst_data117)
    ,.sc2mac_dat_data118              (sc2mac_dat_b_dst_data118)
    ,.sc2mac_dat_data119              (sc2mac_dat_b_dst_data119)
    ,.sc2mac_dat_data120              (sc2mac_dat_b_dst_data120)
    ,.sc2mac_dat_data121              (sc2mac_dat_b_dst_data121)
    ,.sc2mac_dat_data122              (sc2mac_dat_b_dst_data122)
    ,.sc2mac_dat_data123              (sc2mac_dat_b_dst_data123)
    ,.sc2mac_dat_data124              (sc2mac_dat_b_dst_data124)
    ,.sc2mac_dat_data125              (sc2mac_dat_b_dst_data125)
    ,.sc2mac_dat_data126              (sc2mac_dat_b_dst_data126)
    ,.sc2mac_dat_data127              (sc2mac_dat_b_dst_data127)
    ,.sc2mac_dat_pd                   (sc2mac_dat_b_dst_pd)
    ,.sc2mac_wt_pvld                  (sc2mac_wt_b_dst_pvld)
    ,.sc2mac_wt_mask                  (sc2mac_wt_b_dst_mask)
    ,.sc2mac_wt_data0                 (sc2mac_wt_b_dst_data0)
    ,.sc2mac_wt_data1                 (sc2mac_wt_b_dst_data1)
    ,.sc2mac_wt_data2                 (sc2mac_wt_b_dst_data2)
    ,.sc2mac_wt_data3                 (sc2mac_wt_b_dst_data3)
    ,.sc2mac_wt_data4                 (sc2mac_wt_b_dst_data4)
    ,.sc2mac_wt_data5                 (sc2mac_wt_b_dst_data5)
    ,.sc2mac_wt_data6                 (sc2mac_wt_b_dst_data6)
    ,.sc2mac_wt_data7                 (sc2mac_wt_b_dst_data7)
    ,.sc2mac_wt_data8                 (sc2mac_wt_b_dst_data8)
    ,.sc2mac_wt_data9                 (sc2mac_wt_b_dst_data9)
    ,.sc2mac_wt_data10                (sc2mac_wt_b_dst_data10)
    ,.sc2mac_wt_data11                (sc2mac_wt_b_dst_data11)
    ,.sc2mac_wt_data12                (sc2mac_wt_b_dst_data12)
    ,.sc2mac_wt_data13                (sc2mac_wt_b_dst_data13)
    ,.sc2mac_wt_data14                (sc2mac_wt_b_dst_data14)
    ,.sc2mac_wt_data15                (sc2mac_wt_b_dst_data15)
    ,.sc2mac_wt_data16                (sc2mac_wt_b_dst_data16)
    ,.sc2mac_wt_data17                (sc2mac_wt_b_dst_data17)
    ,.sc2mac_wt_data18                (sc2mac_wt_b_dst_data18)
    ,.sc2mac_wt_data19                (sc2mac_wt_b_dst_data19)
    ,.sc2mac_wt_data20                (sc2mac_wt_b_dst_data20)
    ,.sc2mac_wt_data21                (sc2mac_wt_b_dst_data21)
    ,.sc2mac_wt_data22                (sc2mac_wt_b_dst_data22)
    ,.sc2mac_wt_data23                (sc2mac_wt_b_dst_data23)
    ,.sc2mac_wt_data24                (sc2mac_wt_b_dst_data24)
    ,.sc2mac_wt_data25                (sc2mac_wt_b_dst_data25)
    ,.sc2mac_wt_data26                (sc2mac_wt_b_dst_data26)
    ,.sc2mac_wt_data27                (sc2mac_wt_b_dst_data27)
    ,.sc2mac_wt_data28                (sc2mac_wt_b_dst_data28)
    ,.sc2mac_wt_data29                (sc2mac_wt_b_dst_data29)
    ,.sc2mac_wt_data30                (sc2mac_wt_b_dst_data30)
    ,.sc2mac_wt_data31                (sc2mac_wt_b_dst_data31)
    ,.sc2mac_wt_data32                (sc2mac_wt_b_dst_data32)
    ,.sc2mac_wt_data33                (sc2mac_wt_b_dst_data33)
    ,.sc2mac_wt_data34                (sc2mac_wt_b_dst_data34)
    ,.sc2mac_wt_data35                (sc2mac_wt_b_dst_data35)
    ,.sc2mac_wt_data36                (sc2mac_wt_b_dst_data36)
    ,.sc2mac_wt_data37                (sc2mac_wt_b_dst_data37)
    ,.sc2mac_wt_data38                (sc2mac_wt_b_dst_data38)
    ,.sc2mac_wt_data39                (sc2mac_wt_b_dst_data39)
    ,.sc2mac_wt_data40                (sc2mac_wt_b_dst_data40)
    ,.sc2mac_wt_data41                (sc2mac_wt_b_dst_data41)
    ,.sc2mac_wt_data42                (sc2mac_wt_b_dst_data42)
    ,.sc2mac_wt_data43                (sc2mac_wt_b_dst_data43)
    ,.sc2mac_wt_data44                (sc2mac_wt_b_dst_data44)
    ,.sc2mac_wt_data45                (sc2mac_wt_b_dst_data45)
    ,.sc2mac_wt_data46                (sc2mac_wt_b_dst_data46)
    ,.sc2mac_wt_data47                (sc2mac_wt_b_dst_data47)
    ,.sc2mac_wt_data48                (sc2mac_wt_b_dst_data48)
    ,.sc2mac_wt_data49                (sc2mac_wt_b_dst_data49)
    ,.sc2mac_wt_data50                (sc2mac_wt_b_dst_data50)
    ,.sc2mac_wt_data51                (sc2mac_wt_b_dst_data51)
    ,.sc2mac_wt_data52                (sc2mac_wt_b_dst_data52)
    ,.sc2mac_wt_data53                (sc2mac_wt_b_dst_data53)
    ,.sc2mac_wt_data54                (sc2mac_wt_b_dst_data54)
    ,.sc2mac_wt_data55                (sc2mac_wt_b_dst_data55)
    ,.sc2mac_wt_data56                (sc2mac_wt_b_dst_data56)
    ,.sc2mac_wt_data57                (sc2mac_wt_b_dst_data57)
    ,.sc2mac_wt_data58                (sc2mac_wt_b_dst_data58)
    ,.sc2mac_wt_data59                (sc2mac_wt_b_dst_data59)
    ,.sc2mac_wt_data60                (sc2mac_wt_b_dst_data60)
    ,.sc2mac_wt_data61                (sc2mac_wt_b_dst_data61)
    ,.sc2mac_wt_data62                (sc2mac_wt_b_dst_data62)
    ,.sc2mac_wt_data63                (sc2mac_wt_b_dst_data63)
    ,.sc2mac_wt_data64                (sc2mac_wt_b_dst_data64)
    ,.sc2mac_wt_data65                (sc2mac_wt_b_dst_data65)
    ,.sc2mac_wt_data66                (sc2mac_wt_b_dst_data66)
    ,.sc2mac_wt_data67                (sc2mac_wt_b_dst_data67)
    ,.sc2mac_wt_data68                (sc2mac_wt_b_dst_data68)
    ,.sc2mac_wt_data69                (sc2mac_wt_b_dst_data69)
    ,.sc2mac_wt_data70                (sc2mac_wt_b_dst_data70)
    ,.sc2mac_wt_data71                (sc2mac_wt_b_dst_data71)
    ,.sc2mac_wt_data72                (sc2mac_wt_b_dst_data72)
    ,.sc2mac_wt_data73                (sc2mac_wt_b_dst_data73)
    ,.sc2mac_wt_data74                (sc2mac_wt_b_dst_data74)
    ,.sc2mac_wt_data75                (sc2mac_wt_b_dst_data75)
    ,.sc2mac_wt_data76                (sc2mac_wt_b_dst_data76)
    ,.sc2mac_wt_data77                (sc2mac_wt_b_dst_data77)
    ,.sc2mac_wt_data78                (sc2mac_wt_b_dst_data78)
    ,.sc2mac_wt_data79                (sc2mac_wt_b_dst_data79)
    ,.sc2mac_wt_data80                (sc2mac_wt_b_dst_data80)
    ,.sc2mac_wt_data81                (sc2mac_wt_b_dst_data81)
    ,.sc2mac_wt_data82                (sc2mac_wt_b_dst_data82)
    ,.sc2mac_wt_data83                (sc2mac_wt_b_dst_data83)
    ,.sc2mac_wt_data84                (sc2mac_wt_b_dst_data84)
    ,.sc2mac_wt_data85                (sc2mac_wt_b_dst_data85)
    ,.sc2mac_wt_data86                (sc2mac_wt_b_dst_data86)
    ,.sc2mac_wt_data87                (sc2mac_wt_b_dst_data87)
    ,.sc2mac_wt_data88                (sc2mac_wt_b_dst_data88)
    ,.sc2mac_wt_data89                (sc2mac_wt_b_dst_data89)
    ,.sc2mac_wt_data90                (sc2mac_wt_b_dst_data90)
    ,.sc2mac_wt_data91                (sc2mac_wt_b_dst_data91)
    ,.sc2mac_wt_data92                (sc2mac_wt_b_dst_data92)
    ,.sc2mac_wt_data93                (sc2mac_wt_b_dst_data93)
    ,.sc2mac_wt_data94                (sc2mac_wt_b_dst_data94)
    ,.sc2mac_wt_data95                (sc2mac_wt_b_dst_data95)
    ,.sc2mac_wt_data96                (sc2mac_wt_b_dst_data96)
    ,.sc2mac_wt_data97                (sc2mac_wt_b_dst_data97)
    ,.sc2mac_wt_data98                (sc2mac_wt_b_dst_data98)
    ,.sc2mac_wt_data99                (sc2mac_wt_b_dst_data99)
    ,.sc2mac_wt_data100               (sc2mac_wt_b_dst_data100)
    ,.sc2mac_wt_data101               (sc2mac_wt_b_dst_data101)
    ,.sc2mac_wt_data102               (sc2mac_wt_b_dst_data102)
    ,.sc2mac_wt_data103               (sc2mac_wt_b_dst_data103)
    ,.sc2mac_wt_data104               (sc2mac_wt_b_dst_data104)
    ,.sc2mac_wt_data105               (sc2mac_wt_b_dst_data105)
    ,.sc2mac_wt_data106               (sc2mac_wt_b_dst_data106)
    ,.sc2mac_wt_data107               (sc2mac_wt_b_dst_data107)
    ,.sc2mac_wt_data108               (sc2mac_wt_b_dst_data108)
    ,.sc2mac_wt_data109               (sc2mac_wt_b_dst_data109)
    ,.sc2mac_wt_data110               (sc2mac_wt_b_dst_data110)
    ,.sc2mac_wt_data111               (sc2mac_wt_b_dst_data111)
    ,.sc2mac_wt_data112               (sc2mac_wt_b_dst_data112)
    ,.sc2mac_wt_data113               (sc2mac_wt_b_dst_data113)
    ,.sc2mac_wt_data114               (sc2mac_wt_b_dst_data114)
    ,.sc2mac_wt_data115               (sc2mac_wt_b_dst_data115)
    ,.sc2mac_wt_data116               (sc2mac_wt_b_dst_data116)
    ,.sc2mac_wt_data117               (sc2mac_wt_b_dst_data117)
    ,.sc2mac_wt_data118               (sc2mac_wt_b_dst_data118)
    ,.sc2mac_wt_data119               (sc2mac_wt_b_dst_data119)
    ,.sc2mac_wt_data120               (sc2mac_wt_b_dst_data120)
    ,.sc2mac_wt_data121               (sc2mac_wt_b_dst_data121)
    ,.sc2mac_wt_data122               (sc2mac_wt_b_dst_data122)
    ,.sc2mac_wt_data123               (sc2mac_wt_b_dst_data123)
    ,.sc2mac_wt_data124               (sc2mac_wt_b_dst_data124)
    ,.sc2mac_wt_data125               (sc2mac_wt_b_dst_data125)
    ,.sc2mac_wt_data126               (sc2mac_wt_b_dst_data126)
    ,.sc2mac_wt_data127               (sc2mac_wt_b_dst_data127)
    ,.sc2mac_wt_sel                   (sc2mac_wt_b_dst_sel)
    ,.dla_clk_ovr_on_sync             (1'b0)
    ,.global_clk_ovr_on_sync          (1'b0)
    ,.tmc2slcg_disable_clock_gating   (1'b1)
  );

  // ---------------- RT：cmac->cacc 打拍（a 例在 partition_p、b 例在 a） ---
  NV_NVDLA_RT_cmac_a2cacc u_NV_NVDLA_RT_cmac_a2cacc (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.mac2accu_src_pvld               (mac_a2accu_src_pvld)
    ,.mac2accu_src_mask               (mac_a2accu_src_mask)
    ,.mac2accu_src_mode               (mac_a2accu_src_mode)
    ,.mac2accu_src_data0              (mac_a2accu_src_data0)
    ,.mac2accu_src_data1              (mac_a2accu_src_data1)
    ,.mac2accu_src_data2              (mac_a2accu_src_data2)
    ,.mac2accu_src_data3              (mac_a2accu_src_data3)
    ,.mac2accu_src_data4              (mac_a2accu_src_data4)
    ,.mac2accu_src_data5              (mac_a2accu_src_data5)
    ,.mac2accu_src_data6              (mac_a2accu_src_data6)
    ,.mac2accu_src_data7              (mac_a2accu_src_data7)
    ,.mac2accu_src_pd                 (mac_a2accu_src_pd)
    ,.mac2accu_dst_pvld               (mac_a2accu_dst_pvld)
    ,.mac2accu_dst_mask               (mac_a2accu_dst_mask)
    ,.mac2accu_dst_mode               (mac_a2accu_dst_mode)
    ,.mac2accu_dst_data0              (mac_a2accu_dst_data0)
    ,.mac2accu_dst_data1              (mac_a2accu_dst_data1)
    ,.mac2accu_dst_data2              (mac_a2accu_dst_data2)
    ,.mac2accu_dst_data3              (mac_a2accu_dst_data3)
    ,.mac2accu_dst_data4              (mac_a2accu_dst_data4)
    ,.mac2accu_dst_data5              (mac_a2accu_dst_data5)
    ,.mac2accu_dst_data6              (mac_a2accu_dst_data6)
    ,.mac2accu_dst_data7              (mac_a2accu_dst_data7)
    ,.mac2accu_dst_pd                 (mac_a2accu_dst_pd)
  );

  NV_NVDLA_RT_cmac_b2cacc u_NV_NVDLA_RT_cmac_b2cacc (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.mac2accu_src_pvld               (mac_b2accu_src_pvld)
    ,.mac2accu_src_mask               (mac_b2accu_src_mask)
    ,.mac2accu_src_mode               (mac_b2accu_src_mode)
    ,.mac2accu_src_data0              (mac_b2accu_src_data0)
    ,.mac2accu_src_data1              (mac_b2accu_src_data1)
    ,.mac2accu_src_data2              (mac_b2accu_src_data2)
    ,.mac2accu_src_data3              (mac_b2accu_src_data3)
    ,.mac2accu_src_data4              (mac_b2accu_src_data4)
    ,.mac2accu_src_data5              (mac_b2accu_src_data5)
    ,.mac2accu_src_data6              (mac_b2accu_src_data6)
    ,.mac2accu_src_data7              (mac_b2accu_src_data7)
    ,.mac2accu_src_pd                 (mac_b2accu_src_pd)
    ,.mac2accu_dst_pvld               (mac_b2accu_dst_pvld)
    ,.mac2accu_dst_mask               (mac_b2accu_dst_mask)
    ,.mac2accu_dst_mode               (mac_b2accu_dst_mode)
    ,.mac2accu_dst_data0              (mac_b2accu_dst_data0)
    ,.mac2accu_dst_data1              (mac_b2accu_dst_data1)
    ,.mac2accu_dst_data2              (mac_b2accu_dst_data2)
    ,.mac2accu_dst_data3              (mac_b2accu_dst_data3)
    ,.mac2accu_dst_data4              (mac_b2accu_dst_data4)
    ,.mac2accu_dst_data5              (mac_b2accu_dst_data5)
    ,.mac2accu_dst_data6              (mac_b2accu_dst_data6)
    ,.mac2accu_dst_data7              (mac_b2accu_dst_data7)
    ,.mac2accu_dst_pd                 (mac_b2accu_dst_pd)
  );

  // ---------------- DUT：cacc（partition_a 内例） -------------------------
  NV_NVDLA_cacc u_NV_NVDLA_cacc (
     .nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.pwrbus_ram_pd                   (32'b0)
    ,.csb2cacc_req_pvld               (csb2cacc_req_pvld)
    ,.csb2cacc_req_prdy               (csb2cacc_req_prdy)
    ,.csb2cacc_req_pd                 (csb2cacc_req_pd)
    ,.cacc2csb_resp_valid             (cacc2csb_resp_valid)
    ,.cacc2csb_resp_pd                (cacc2csb_resp_pd)
    ,.mac_a2accu_pvld                 (mac_a2accu_dst_pvld)
    ,.mac_a2accu_mask                 (mac_a2accu_dst_mask)
    ,.mac_a2accu_mode                 (mac_a2accu_dst_mode)
    ,.mac_a2accu_data0                (mac_a2accu_dst_data0)
    ,.mac_a2accu_data1                (mac_a2accu_dst_data1)
    ,.mac_a2accu_data2                (mac_a2accu_dst_data2)
    ,.mac_a2accu_data3                (mac_a2accu_dst_data3)
    ,.mac_a2accu_data4                (mac_a2accu_dst_data4)
    ,.mac_a2accu_data5                (mac_a2accu_dst_data5)
    ,.mac_a2accu_data6                (mac_a2accu_dst_data6)
    ,.mac_a2accu_data7                (mac_a2accu_dst_data7)
    ,.mac_a2accu_pd                   (mac_a2accu_dst_pd)
    ,.mac_b2accu_pvld                 (mac_b2accu_dst_pvld)
    ,.mac_b2accu_mask                 (mac_b2accu_dst_mask)
    ,.mac_b2accu_mode                 (mac_b2accu_dst_mode)
    ,.mac_b2accu_data0                (mac_b2accu_dst_data0)
    ,.mac_b2accu_data1                (mac_b2accu_dst_data1)
    ,.mac_b2accu_data2                (mac_b2accu_dst_data2)
    ,.mac_b2accu_data3                (mac_b2accu_dst_data3)
    ,.mac_b2accu_data4                (mac_b2accu_dst_data4)
    ,.mac_b2accu_data5                (mac_b2accu_dst_data5)
    ,.mac_b2accu_data6                (mac_b2accu_dst_data6)
    ,.mac_b2accu_data7                (mac_b2accu_dst_data7)
    ,.mac_b2accu_pd                   (mac_b2accu_dst_pd)
    ,.cacc2sdp_valid                  (cacc2sdp_valid)
    ,.cacc2sdp_ready                  (cacc2sdp_ready)
    ,.cacc2sdp_pd                     (cacc2sdp_pd)
    ,.accu2sc_credit_vld              (accu2sc_credit_vld)
    ,.accu2sc_credit_size             (accu2sc_credit_size)
    ,.cacc2glb_done_intr_pd           (cacc2glb_done_intr_pd)
    ,.dla_clk_ovr_on_sync             (1'b0)
    ,.global_clk_ovr_on_sync          (1'b0)
    ,.tmc2slcg_disable_clock_gating   (1'b1)
  );

  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    uvm_config_db#(virtual cbuf_resp_if#(12))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_dat_vif", u_cbuf_dat_if);
    uvm_config_db#(virtual cbuf_resp_if#(12))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_wt_vif", u_cbuf_wt_if);
    uvm_config_db#(virtual cbuf_resp_if#(8))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_wmb_vif", u_cbuf_wmb_if);

    uvm_config_db#(virtual csc_cdma_if)::set(
      null, "uvm_test_top.env.cdma_stub*", "csc_cdma_vif", u_cs_if);

    uvm_config_db#(virtual sdp_if)::set(
      null, "uvm_test_top.env.sdp_sink*", "sdp_vif", u_sdp_if);

    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr0_agt*", "intr_vif", u_intr0_if);
    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr1_agt*", "intr_vif", u_intr1_if);

`ifdef WAVES_FSDB
    if ($test$plusargs("fsdb")) begin
      string fsdb_name = "waves.fsdb";
      void'($value$plusargs("fsdbfile=%s", fsdb_name));
      $fsdbDumpfile(fsdb_name);
      $fsdbDumpvars(0, tb_top);
    end
`endif
    run_test();
  end

endmodule : tb_top
