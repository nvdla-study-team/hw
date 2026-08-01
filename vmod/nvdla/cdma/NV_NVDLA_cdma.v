// ================================================================
// NVDLA Open Source Project
// 
// Copyright(c) 2016 - 2017 NVIDIA Corporation.  Licensed under the
// NVDLA Open Hardware License; Check "LICENSE" which comes with 
// this distribution for more information.
// ================================================================

// File Name: NV_NVDLA_cdma.v

// ----------------------------------------------------------------
// 【机制总览】CDMA：卷积输入取数引擎（外存 → cbuf 的唯一写入方）
//
// 一、四条子通路，同一时刻只有一条数据通路活跃（按层配置互斥）
//   - DC (u_dc)  ：直接卷积 feature 数据取数
//   - IMG(u_img) ：图像输入（pitch-linear 像素格式）取数，另带 mean 减除数据
//   - WG (u_wg)  ：Winograd 卷积数据取数（含 PRA 预变换所需的边界处理）
//   - WT (u_wt)  ：权重取数（与上面三条"数据"通路并行工作，独立出 cbuf 写口）
//   DC/WG/IMG 三选一由 reg2dp_conv_mode/datain_format 决定；三者共享
//   u_shared_buffer（2 端口 SRAM 汇聚站）做行缓冲/重排。
//
// 二、数据流（dat 侧）：dc|wg|img → u_dma_mux（对 MCIF/CVIF 合一出口）
//   取回的数据 → 各自重排 → *2cvt_dat_wr_* → u_cvt（精度转换/均值减除/
//   pad 填充，int8/int16/fp16 → cbuf 存储格式）→ cdma2buf_dat_wr_*（1024bit，
//   2×512bit 半字 hsel）写入 cbuf。wt 侧独立：u_wt 直接出
//   cdma2buf_wt_wr_*（512bit）不过 cvt/dma_mux。
//   注意：对 MCIF/CVIF 只有两对读口——dat 口（三客户端经 dma_mux 合一）
//   和 wt 口（u_wt 独占），故 CDMA 顶层共 4 组 rd_req/rd_rsp 接口。
//
// 三、记账与握手（u_status + 与 CSC 的 update 环）
//   dc/wg/img 写入若干 entry 后向 u_status 报增量（*2status_dat_updt），
//   u_status 维护 cbuf 数据区占用（valid_slices/free_entries/wr_idx 回供
//   DMA 判断可写空间）；CSC 消费后经 sc2cdma_*_updt 归还释放量。
//   一层完成：dat 与 wt 两侧都 done 后 u_status 发 status2dma_fsm_switch
//   统一切层，并出 done 中断（cdma_dat2glb/cdma_wt2glb_done_intr_pd）。
//
// 四、时钟门控分组（SLCG 每域一只，共 8 组 slcg_op_en[7:0]）
//   wt/dc/wg/img/mux/cvt/hls(cvt 内 HLS 细胞)/buffer 各自独立门控；
//   dc、wg、img 互相之间还有交叉门控信号（slcg_*_gate_*：活跃通路把
//   另两条闲置通路的时钟关掉，文件尾断言保证三者互斥）。regfile 与
//   status 始终用未门控的 nvdla_core_clk（CSB 访问和记账不能停）。
// ----------------------------------------------------------------
module NV_NVDLA_cdma (
   cdma_dat2cvif_rd_req_ready    //|< i
  ,cdma_dat2mcif_rd_req_ready    //|< i
  ,cdma_wt2cvif_rd_req_ready     //|< i
  ,cdma_wt2mcif_rd_req_ready     //|< i
  ,csb2cdma_req_pd               //|< i
  ,csb2cdma_req_pvld             //|< i
  ,cvif2cdma_dat_rd_rsp_pd       //|< i
  ,cvif2cdma_dat_rd_rsp_valid    //|< i
  ,cvif2cdma_wt_rd_rsp_pd        //|< i
  ,cvif2cdma_wt_rd_rsp_valid     //|< i
  ,dla_clk_ovr_on_sync           //|< i
  ,global_clk_ovr_on_sync        //|< i
  ,mcif2cdma_dat_rd_rsp_pd       //|< i
  ,mcif2cdma_dat_rd_rsp_valid    //|< i
  ,mcif2cdma_wt_rd_rsp_pd        //|< i
  ,mcif2cdma_wt_rd_rsp_valid     //|< i
  ,nvdla_core_clk                //|< i
  ,nvdla_core_rstn               //|< i
  ,pwrbus_ram_pd                 //|< i
  ,sc2cdma_dat_entries           //|< i
  ,sc2cdma_dat_pending_req       //|< i
  ,sc2cdma_dat_slices            //|< i
  ,sc2cdma_dat_updt              //|< i
  ,sc2cdma_wmb_entries           //|< i
  ,sc2cdma_wt_entries            //|< i
  ,sc2cdma_wt_kernels            //|< i
  ,sc2cdma_wt_pending_req        //|< i
  ,sc2cdma_wt_updt               //|< i
  ,tmc2slcg_disable_clock_gating //|< i
  ,cdma2buf_dat_wr_addr          //|> o
  ,cdma2buf_dat_wr_data          //|> o
  ,cdma2buf_dat_wr_en            //|> o
  ,cdma2buf_dat_wr_hsel          //|> o
  ,cdma2buf_wt_wr_addr           //|> o
  ,cdma2buf_wt_wr_data           //|> o
  ,cdma2buf_wt_wr_en             //|> o
  ,cdma2buf_wt_wr_hsel           //|> o
  ,cdma2csb_resp_pd              //|> o
  ,cdma2csb_resp_valid           //|> o
  ,cdma2sc_dat_entries           //|> o
  ,cdma2sc_dat_pending_ack       //|> o
  ,cdma2sc_dat_slices            //|> o
  ,cdma2sc_dat_updt              //|> o
  ,cdma2sc_wmb_entries           //|> o
  ,cdma2sc_wt_entries            //|> o
  ,cdma2sc_wt_kernels            //|> o
  ,cdma2sc_wt_pending_ack        //|> o
  ,cdma2sc_wt_updt               //|> o
  ,cdma_dat2cvif_rd_req_pd       //|> o
  ,cdma_dat2cvif_rd_req_valid    //|> o
  ,cdma_dat2glb_done_intr_pd     //|> o
  ,cdma_dat2mcif_rd_req_pd       //|> o
  ,cdma_dat2mcif_rd_req_valid    //|> o
  ,cdma_wt2cvif_rd_req_pd        //|> o
  ,cdma_wt2cvif_rd_req_valid     //|> o
  ,cdma_wt2glb_done_intr_pd      //|> o
  ,cdma_wt2mcif_rd_req_pd        //|> o
  ,cdma_wt2mcif_rd_req_valid     //|> o
  ,csb2cdma_req_prdy             //|> o
  ,cvif2cdma_dat_rd_rsp_ready    //|> o
  ,cvif2cdma_wt_rd_rsp_ready     //|> o
  ,mcif2cdma_dat_rd_rsp_ready    //|> o
  ,mcif2cdma_wt_rd_rsp_ready     //|> o
  );


//
// NV_NVDLA_cdma_ports.v
//
input  nvdla_core_clk;   /* cdma2buf_dat_wr, cdma2buf_wt_wr, cdma2csb_resp, cdma2sc_dat_pending, cdma2sc_wt_pending, cdma_dat2cvif_rd_req, cdma_dat2glb_done_intr, cdma_dat2mcif_rd_req, cdma_wt2cvif_rd_req, cdma_wt2glb_done_intr, cdma_wt2mcif_rd_req, csb2cdma_req, cvif2cdma_dat_rd_rsp, cvif2cdma_wt_rd_rsp, dat_up_cdma2sc, dat_up_sc2cdma, mcif2cdma_dat_rd_rsp, mcif2cdma_wt_rd_rsp, sc2cdma_dat_pending, sc2cdma_wt_pending, wt_up_cdma2sc, wt_up_sc2cdma */
input  nvdla_core_rstn;  /* cdma2buf_dat_wr, cdma2buf_wt_wr, cdma2csb_resp, cdma2sc_dat_pending, cdma2sc_wt_pending, cdma_dat2cvif_rd_req, cdma_dat2glb_done_intr, cdma_dat2mcif_rd_req, cdma_wt2cvif_rd_req, cdma_wt2glb_done_intr, cdma_wt2mcif_rd_req, csb2cdma_req, cvif2cdma_dat_rd_rsp, cvif2cdma_wt_rd_rsp, dat_up_cdma2sc, dat_up_sc2cdma, mcif2cdma_dat_rd_rsp, mcif2cdma_wt_rd_rsp, sc2cdma_dat_pending, sc2cdma_wt_pending, wt_up_cdma2sc, wt_up_sc2cdma */

output          cdma2buf_dat_wr_en;    /* data valid */
output   [11:0] cdma2buf_dat_wr_addr;
output    [1:0] cdma2buf_dat_wr_hsel;
output [1023:0] cdma2buf_dat_wr_data;

output         cdma2buf_wt_wr_en;    /* data valid */
output  [11:0] cdma2buf_wt_wr_addr;
output         cdma2buf_wt_wr_hsel;
output [511:0] cdma2buf_wt_wr_data;

output        cdma2csb_resp_valid;  /* data valid */
output [33:0] cdma2csb_resp_pd;     /* pkt_id_width=1 pkt_widths=33,33  */

output  cdma2sc_dat_pending_ack;

output  cdma2sc_wt_pending_ack;

output        cdma_dat2cvif_rd_req_valid;  /* data valid */
input         cdma_dat2cvif_rd_req_ready;  /* data return handshake */
output [78:0] cdma_dat2cvif_rd_req_pd;

output [1:0] cdma_dat2glb_done_intr_pd;

output        cdma_dat2mcif_rd_req_valid;  /* data valid */
input         cdma_dat2mcif_rd_req_ready;  /* data return handshake */
output [78:0] cdma_dat2mcif_rd_req_pd;

output        cdma_wt2cvif_rd_req_valid;  /* data valid */
input         cdma_wt2cvif_rd_req_ready;  /* data return handshake */
output [78:0] cdma_wt2cvif_rd_req_pd;

output [1:0] cdma_wt2glb_done_intr_pd;

output        cdma_wt2mcif_rd_req_valid;  /* data valid */
input         cdma_wt2mcif_rd_req_ready;  /* data return handshake */
output [78:0] cdma_wt2mcif_rd_req_pd;

input         csb2cdma_req_pvld;  /* data valid */
output        csb2cdma_req_prdy;  /* data return handshake */
input  [62:0] csb2cdma_req_pd;

input          cvif2cdma_dat_rd_rsp_valid;  /* data valid */
output         cvif2cdma_dat_rd_rsp_ready;  /* data return handshake */
input  [513:0] cvif2cdma_dat_rd_rsp_pd;

input          cvif2cdma_wt_rd_rsp_valid;  /* data valid */
output         cvif2cdma_wt_rd_rsp_ready;  /* data return handshake */
input  [513:0] cvif2cdma_wt_rd_rsp_pd;

output        cdma2sc_dat_updt;     /* data valid */
output [11:0] cdma2sc_dat_entries;
output [11:0] cdma2sc_dat_slices;

input        sc2cdma_dat_updt;     /* data valid */
input [11:0] sc2cdma_dat_entries;
input [11:0] sc2cdma_dat_slices;

input          mcif2cdma_dat_rd_rsp_valid;  /* data valid */
output         mcif2cdma_dat_rd_rsp_ready;  /* data return handshake */
input  [513:0] mcif2cdma_dat_rd_rsp_pd;

input          mcif2cdma_wt_rd_rsp_valid;  /* data valid */
output         mcif2cdma_wt_rd_rsp_ready;  /* data return handshake */
input  [513:0] mcif2cdma_wt_rd_rsp_pd;

input [31:0] pwrbus_ram_pd;

input  sc2cdma_dat_pending_req;

input  sc2cdma_wt_pending_req;

output        cdma2sc_wt_updt;      /* data valid */
output [13:0] cdma2sc_wt_kernels;
output [11:0] cdma2sc_wt_entries;
output  [8:0] cdma2sc_wmb_entries;

input        sc2cdma_wt_updt;      /* data valid */
input [13:0] sc2cdma_wt_kernels;
input [11:0] sc2cdma_wt_entries;
input  [8:0] sc2cdma_wmb_entries;

input   dla_clk_ovr_on_sync;
input   global_clk_ovr_on_sync;
input   tmc2slcg_disable_clock_gating;

wire  [513:0] cvif2dc_dat_rd_rsp_pd;
wire          cvif2dc_dat_rd_rsp_ready;
wire          cvif2dc_dat_rd_rsp_valid;
wire  [513:0] cvif2img_dat_rd_rsp_pd;
wire          cvif2img_dat_rd_rsp_ready;
wire          cvif2img_dat_rd_rsp_valid;
wire  [513:0] cvif2wg_dat_rd_rsp_pd;
wire          cvif2wg_dat_rd_rsp_ready;
wire          cvif2wg_dat_rd_rsp_valid;
wire   [11:0] dc2cvt_dat_wr_addr;
wire  [511:0] dc2cvt_dat_wr_data;
wire          dc2cvt_dat_wr_en;
wire          dc2cvt_dat_wr_hsel;
wire   [11:0] dc2cvt_dat_wr_info_pd;
wire    [7:0] dc2sbuf_p0_rd_addr;
wire  [255:0] dc2sbuf_p0_rd_data;
wire          dc2sbuf_p0_rd_en;
wire    [7:0] dc2sbuf_p0_wr_addr;
wire  [255:0] dc2sbuf_p0_wr_data;
wire          dc2sbuf_p0_wr_en;
wire    [7:0] dc2sbuf_p1_rd_addr;
wire  [255:0] dc2sbuf_p1_rd_data;
wire          dc2sbuf_p1_rd_en;
wire    [7:0] dc2sbuf_p1_wr_addr;
wire  [255:0] dc2sbuf_p1_wr_data;
wire          dc2sbuf_p1_wr_en;
wire   [11:0] dc2status_dat_entries;
wire   [11:0] dc2status_dat_slices;
wire          dc2status_dat_updt;
wire    [1:0] dc2status_state;
wire   [78:0] dc_dat2cvif_rd_req_pd;
wire          dc_dat2cvif_rd_req_ready;
wire          dc_dat2cvif_rd_req_valid;
wire   [78:0] dc_dat2mcif_rd_req_pd;
wire          dc_dat2mcif_rd_req_ready;
wire          dc_dat2mcif_rd_req_valid;
wire          dp2reg_consumer;
wire          dp2reg_dat_flush_done;
wire   [31:0] dp2reg_dc_rd_latency;
wire   [31:0] dp2reg_dc_rd_stall;
wire          dp2reg_done;
wire   [31:0] dp2reg_img_rd_latency;
wire   [31:0] dp2reg_img_rd_stall;
wire   [31:0] dp2reg_inf_data_num;
wire   [31:0] dp2reg_inf_weight_num;
wire   [31:0] dp2reg_nan_data_num;
wire   [31:0] dp2reg_nan_weight_num;
wire   [31:0] dp2reg_wg_rd_latency;
wire   [31:0] dp2reg_wg_rd_stall;
wire          dp2reg_wt_flush_done;
wire   [31:0] dp2reg_wt_rd_latency;
wire   [31:0] dp2reg_wt_rd_stall;
wire   [11:0] img2cvt_dat_wr_addr;
wire [1023:0] img2cvt_dat_wr_data;
wire          img2cvt_dat_wr_en;
wire          img2cvt_dat_wr_hsel;
wire   [11:0] img2cvt_dat_wr_info_pd;
wire  [127:0] img2cvt_dat_wr_pad_mask;
wire [1023:0] img2cvt_mn_wr_data;
wire    [7:0] img2sbuf_p0_rd_addr;
wire  [255:0] img2sbuf_p0_rd_data;
wire          img2sbuf_p0_rd_en;
wire    [7:0] img2sbuf_p0_wr_addr;
wire  [255:0] img2sbuf_p0_wr_data;
wire          img2sbuf_p0_wr_en;
wire    [7:0] img2sbuf_p1_rd_addr;
wire  [255:0] img2sbuf_p1_rd_data;
wire          img2sbuf_p1_rd_en;
wire    [7:0] img2sbuf_p1_wr_addr;
wire  [255:0] img2sbuf_p1_wr_data;
wire          img2sbuf_p1_wr_en;
wire   [11:0] img2status_dat_entries;
wire   [11:0] img2status_dat_slices;
wire          img2status_dat_updt;
wire    [1:0] img2status_state;
wire   [78:0] img_dat2cvif_rd_req_pd;
wire          img_dat2cvif_rd_req_ready;
wire          img_dat2cvif_rd_req_valid;
wire   [78:0] img_dat2mcif_rd_req_pd;
wire          img_dat2mcif_rd_req_ready;
wire          img_dat2mcif_rd_req_valid;
wire  [513:0] mcif2dc_dat_rd_rsp_pd;
wire          mcif2dc_dat_rd_rsp_ready;
wire          mcif2dc_dat_rd_rsp_valid;
wire  [513:0] mcif2img_dat_rd_rsp_pd;
wire          mcif2img_dat_rd_rsp_ready;
wire          mcif2img_dat_rd_rsp_valid;
wire  [513:0] mcif2wg_dat_rd_rsp_pd;
wire          mcif2wg_dat_rd_rsp_ready;
wire          mcif2wg_dat_rd_rsp_valid;
wire          nvdla_hls_gated_clk_cvt;
wire          nvdla_op_gated_clk_buffer;
wire          nvdla_op_gated_clk_cvt;
wire          nvdla_op_gated_clk_dc;
wire          nvdla_op_gated_clk_img;
wire          nvdla_op_gated_clk_mux;
wire          nvdla_op_gated_clk_wg;
wire          nvdla_op_gated_clk_wt;
wire    [3:0] reg2dp_arb_weight;
wire    [3:0] reg2dp_arb_wmb;
wire   [26:0] reg2dp_batch_stride;
wire    [4:0] reg2dp_batches;
wire   [17:0] reg2dp_byte_per_kernel;
wire    [0:0] reg2dp_conv_mode;
wire    [2:0] reg2dp_conv_x_stride;
wire    [2:0] reg2dp_conv_y_stride;
wire    [0:0] reg2dp_cvt_en;
wire   [15:0] reg2dp_cvt_offset;
wire   [15:0] reg2dp_cvt_scale;
wire    [5:0] reg2dp_cvt_truncate;
wire   [31:0] reg2dp_cya;
wire    [3:0] reg2dp_data_bank;
wire    [0:0] reg2dp_data_reuse;
wire   [31:0] reg2dp_datain_addr_high_0;
wire   [31:0] reg2dp_datain_addr_high_1;
wire   [26:0] reg2dp_datain_addr_low_0;
wire   [26:0] reg2dp_datain_addr_low_1;
wire   [12:0] reg2dp_datain_channel;
wire    [0:0] reg2dp_datain_format;
wire   [12:0] reg2dp_datain_height;
wire   [12:0] reg2dp_datain_height_ext;
wire    [0:0] reg2dp_datain_ram_type;
wire   [12:0] reg2dp_datain_width;
wire   [12:0] reg2dp_datain_width_ext;
wire    [0:0] reg2dp_dma_en;
wire   [11:0] reg2dp_entries;
wire   [11:0] reg2dp_grains;
wire    [1:0] reg2dp_in_precision;
wire    [0:0] reg2dp_line_packed;
wire   [26:0] reg2dp_line_stride;
wire   [15:0] reg2dp_mean_ax;
wire   [15:0] reg2dp_mean_bv;
wire    [0:0] reg2dp_mean_format;
wire   [15:0] reg2dp_mean_gu;
wire   [15:0] reg2dp_mean_ry;
wire    [0:0] reg2dp_nan_to_zero;
wire    [0:0] reg2dp_op_en;
wire    [5:0] reg2dp_pad_bottom;
wire    [4:0] reg2dp_pad_left;
wire    [5:0] reg2dp_pad_right;
wire    [4:0] reg2dp_pad_top;
wire   [15:0] reg2dp_pad_value;
wire    [5:0] reg2dp_pixel_format;
wire    [0:0] reg2dp_pixel_mapping;
wire    [0:0] reg2dp_pixel_sign_override;
wire    [4:0] reg2dp_pixel_x_offset;
wire    [2:0] reg2dp_pixel_y_offset;
wire    [1:0] reg2dp_proc_precision;
wire    [2:0] reg2dp_rsv_height;
wire    [9:0] reg2dp_rsv_per_line;
wire    [9:0] reg2dp_rsv_per_uv_line;
wire    [4:0] reg2dp_rsv_y_index;
wire    [0:0] reg2dp_skip_data_rls;
wire    [0:0] reg2dp_skip_weight_rls;
wire    [0:0] reg2dp_surf_packed;
wire   [26:0] reg2dp_surf_stride;
wire   [26:0] reg2dp_uv_line_stride;
wire   [31:0] reg2dp_weight_addr_high;
wire   [26:0] reg2dp_weight_addr_low;
wire    [3:0] reg2dp_weight_bank;
wire   [24:0] reg2dp_weight_bytes;
wire    [0:0] reg2dp_weight_format;
wire   [12:0] reg2dp_weight_kernel;
wire    [0:0] reg2dp_weight_ram_type;
wire    [0:0] reg2dp_weight_reuse;
wire   [31:0] reg2dp_wgs_addr_high;
wire   [26:0] reg2dp_wgs_addr_low;
wire   [31:0] reg2dp_wmb_addr_high;
wire   [26:0] reg2dp_wmb_addr_low;
wire   [20:0] reg2dp_wmb_bytes;
wire          slcg_dc_gate_img;
wire          slcg_dc_gate_wg;
wire          slcg_hls_en;
wire          slcg_img_gate_dc;
wire          slcg_img_gate_wg;
wire    [7:0] slcg_op_en;
wire          slcg_wg_gate_dc;
wire          slcg_wg_gate_img;
wire   [11:0] status2dma_free_entries;
wire          status2dma_fsm_switch;
wire   [11:0] status2dma_valid_slices;
wire   [11:0] status2dma_wr_idx;
wire   [11:0] wg2cvt_dat_wr_addr;
wire  [511:0] wg2cvt_dat_wr_data;
wire          wg2cvt_dat_wr_en;
wire          wg2cvt_dat_wr_hsel;
wire   [11:0] wg2cvt_dat_wr_info_pd;
wire    [7:0] wg2sbuf_p0_rd_addr;
wire  [255:0] wg2sbuf_p0_rd_data;
wire          wg2sbuf_p0_rd_en;
wire    [7:0] wg2sbuf_p0_wr_addr;
wire  [255:0] wg2sbuf_p0_wr_data;
wire          wg2sbuf_p0_wr_en;
wire    [7:0] wg2sbuf_p1_rd_addr;
wire  [255:0] wg2sbuf_p1_rd_data;
wire          wg2sbuf_p1_rd_en;
wire    [7:0] wg2sbuf_p1_wr_addr;
wire  [255:0] wg2sbuf_p1_wr_data;
wire          wg2sbuf_p1_wr_en;
wire   [11:0] wg2status_dat_entries;
wire   [11:0] wg2status_dat_slices;
wire          wg2status_dat_updt;
wire    [1:0] wg2status_state;
wire   [78:0] wg_dat2cvif_rd_req_pd;
wire          wg_dat2cvif_rd_req_ready;
wire          wg_dat2cvif_rd_req_valid;
wire   [78:0] wg_dat2mcif_rd_req_pd;
wire          wg_dat2mcif_rd_req_ready;
wire          wg_dat2mcif_rd_req_valid;
wire    [1:0] wt2status_state;

//==========================================================
// Regfile
//==========================================================
// CSB 寄存器组：ping-pong 双组配置（producer/consumer），reg2dp_* 广播到
// 各子模块，dp2reg_* 收回状态/性能计数；dp2reg_done 驱动 consumer 组翻转
NV_NVDLA_CDMA_regfile u_regfile (
   .nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.csb2cdma_req_pd               (csb2cdma_req_pd[62:0])           //|< i
  ,.csb2cdma_req_pvld             (csb2cdma_req_pvld)               //|< i
  ,.dp2reg_dat_flush_done         (dp2reg_dat_flush_done)           //|< w
  ,.dp2reg_dc_rd_latency          (dp2reg_dc_rd_latency[31:0])      //|< w
  ,.dp2reg_dc_rd_stall            (dp2reg_dc_rd_stall[31:0])        //|< w
  ,.dp2reg_done                   (dp2reg_done)                     //|< w
  ,.dp2reg_img_rd_latency         (dp2reg_img_rd_latency[31:0])     //|< w
  ,.dp2reg_img_rd_stall           (dp2reg_img_rd_stall[31:0])       //|< w
  ,.dp2reg_inf_data_num           (dp2reg_inf_data_num[31:0])       //|< w
  ,.dp2reg_inf_weight_num         (dp2reg_inf_weight_num[31:0])     //|< w
  ,.dp2reg_nan_data_num           (dp2reg_nan_data_num[31:0])       //|< w
  ,.dp2reg_nan_weight_num         (dp2reg_nan_weight_num[31:0])     //|< w
  ,.dp2reg_wg_rd_latency          (dp2reg_wg_rd_latency[31:0])      //|< w
  ,.dp2reg_wg_rd_stall            (dp2reg_wg_rd_stall[31:0])        //|< w
  ,.dp2reg_wt_flush_done          (dp2reg_wt_flush_done)            //|< w
  ,.dp2reg_wt_rd_latency          (dp2reg_wt_rd_latency[31:0])      //|< w
  ,.dp2reg_wt_rd_stall            (dp2reg_wt_rd_stall[31:0])        //|< w
  ,.cdma2csb_resp_pd              (cdma2csb_resp_pd[33:0])          //|> o
  ,.cdma2csb_resp_valid           (cdma2csb_resp_valid)             //|> o
  ,.csb2cdma_req_prdy             (csb2cdma_req_prdy)               //|> o
  ,.dp2reg_consumer               (dp2reg_consumer)                 //|> w
  ,.reg2dp_arb_weight             (reg2dp_arb_weight[3:0])          //|> w
  ,.reg2dp_arb_wmb                (reg2dp_arb_wmb[3:0])             //|> w
  ,.reg2dp_batch_stride           (reg2dp_batch_stride[26:0])       //|> w
  ,.reg2dp_batches                (reg2dp_batches[4:0])             //|> w
  ,.reg2dp_byte_per_kernel        (reg2dp_byte_per_kernel[17:0])    //|> w
  ,.reg2dp_conv_mode              (reg2dp_conv_mode)                //|> w
  ,.reg2dp_conv_x_stride          (reg2dp_conv_x_stride[2:0])       //|> w
  ,.reg2dp_conv_y_stride          (reg2dp_conv_y_stride[2:0])       //|> w
  ,.reg2dp_cvt_en                 (reg2dp_cvt_en)                   //|> w
  ,.reg2dp_cvt_offset             (reg2dp_cvt_offset[15:0])         //|> w
  ,.reg2dp_cvt_scale              (reg2dp_cvt_scale[15:0])          //|> w
  ,.reg2dp_cvt_truncate           (reg2dp_cvt_truncate[5:0])        //|> w
  ,.reg2dp_cya                    (reg2dp_cya[31:0])                //|> w *
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|> w
  ,.reg2dp_data_reuse             (reg2dp_data_reuse)               //|> w
  ,.reg2dp_datain_addr_high_0     (reg2dp_datain_addr_high_0[31:0]) //|> w
  ,.reg2dp_datain_addr_high_1     (reg2dp_datain_addr_high_1[31:0]) //|> w
  ,.reg2dp_datain_addr_low_0      (reg2dp_datain_addr_low_0[26:0])  //|> w
  ,.reg2dp_datain_addr_low_1      (reg2dp_datain_addr_low_1[26:0])  //|> w
  ,.reg2dp_datain_channel         (reg2dp_datain_channel[12:0])     //|> w
  ,.reg2dp_datain_format          (reg2dp_datain_format)            //|> w
  ,.reg2dp_datain_height          (reg2dp_datain_height[12:0])      //|> w
  ,.reg2dp_datain_height_ext      (reg2dp_datain_height_ext[12:0])  //|> w
  ,.reg2dp_datain_ram_type        (reg2dp_datain_ram_type)          //|> w
  ,.reg2dp_datain_width           (reg2dp_datain_width[12:0])       //|> w
  ,.reg2dp_datain_width_ext       (reg2dp_datain_width_ext[12:0])   //|> w
  ,.reg2dp_dma_en                 (reg2dp_dma_en)                   //|> w
  ,.reg2dp_entries                (reg2dp_entries[11:0])            //|> w
  ,.reg2dp_grains                 (reg2dp_grains[11:0])             //|> w
  ,.reg2dp_in_precision           (reg2dp_in_precision[1:0])        //|> w
  ,.reg2dp_line_packed            (reg2dp_line_packed)              //|> w
  ,.reg2dp_line_stride            (reg2dp_line_stride[26:0])        //|> w
  ,.reg2dp_mean_ax                (reg2dp_mean_ax[15:0])            //|> w
  ,.reg2dp_mean_bv                (reg2dp_mean_bv[15:0])            //|> w
  ,.reg2dp_mean_format            (reg2dp_mean_format)              //|> w
  ,.reg2dp_mean_gu                (reg2dp_mean_gu[15:0])            //|> w
  ,.reg2dp_mean_ry                (reg2dp_mean_ry[15:0])            //|> w
  ,.reg2dp_nan_to_zero            (reg2dp_nan_to_zero)              //|> w
  ,.reg2dp_op_en                  (reg2dp_op_en)                    //|> w
  ,.reg2dp_pad_bottom             (reg2dp_pad_bottom[5:0])          //|> w
  ,.reg2dp_pad_left               (reg2dp_pad_left[4:0])            //|> w
  ,.reg2dp_pad_right              (reg2dp_pad_right[5:0])           //|> w
  ,.reg2dp_pad_top                (reg2dp_pad_top[4:0])             //|> w
  ,.reg2dp_pad_value              (reg2dp_pad_value[15:0])          //|> w
  ,.reg2dp_pixel_format           (reg2dp_pixel_format[5:0])        //|> w
  ,.reg2dp_pixel_mapping          (reg2dp_pixel_mapping)            //|> w
  ,.reg2dp_pixel_sign_override    (reg2dp_pixel_sign_override)      //|> w
  ,.reg2dp_pixel_x_offset         (reg2dp_pixel_x_offset[4:0])      //|> w
  ,.reg2dp_pixel_y_offset         (reg2dp_pixel_y_offset[2:0])      //|> w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|> w
  ,.reg2dp_rsv_height             (reg2dp_rsv_height[2:0])          //|> w
  ,.reg2dp_rsv_per_line           (reg2dp_rsv_per_line[9:0])        //|> w
  ,.reg2dp_rsv_per_uv_line        (reg2dp_rsv_per_uv_line[9:0])     //|> w
  ,.reg2dp_rsv_y_index            (reg2dp_rsv_y_index[4:0])         //|> w
  ,.reg2dp_skip_data_rls          (reg2dp_skip_data_rls)            //|> w
  ,.reg2dp_skip_weight_rls        (reg2dp_skip_weight_rls)          //|> w
  ,.reg2dp_surf_packed            (reg2dp_surf_packed)              //|> w
  ,.reg2dp_surf_stride            (reg2dp_surf_stride[26:0])        //|> w
  ,.reg2dp_uv_line_stride         (reg2dp_uv_line_stride[26:0])     //|> w
  ,.reg2dp_weight_addr_high       (reg2dp_weight_addr_high[31:0])   //|> w
  ,.reg2dp_weight_addr_low        (reg2dp_weight_addr_low[26:0])    //|> w
  ,.reg2dp_weight_bank            (reg2dp_weight_bank[3:0])         //|> w
  ,.reg2dp_weight_bytes           (reg2dp_weight_bytes[24:0])       //|> w
  ,.reg2dp_weight_format          (reg2dp_weight_format)            //|> w
  ,.reg2dp_weight_kernel          (reg2dp_weight_kernel[12:0])      //|> w
  ,.reg2dp_weight_ram_type        (reg2dp_weight_ram_type)          //|> w
  ,.reg2dp_weight_reuse           (reg2dp_weight_reuse)             //|> w
  ,.reg2dp_wgs_addr_high          (reg2dp_wgs_addr_high[31:0])      //|> w
  ,.reg2dp_wgs_addr_low           (reg2dp_wgs_addr_low[26:0])       //|> w
  ,.reg2dp_wmb_addr_high          (reg2dp_wmb_addr_high[31:0])      //|> w
  ,.reg2dp_wmb_addr_low           (reg2dp_wmb_addr_low[26:0])       //|> w
  ,.reg2dp_wmb_bytes              (reg2dp_wmb_bytes[20:0])          //|> w
  ,.slcg_op_en                    (slcg_op_en[7:0])                 //|> w
  );

//==========================================================
// Weight DMA
//==========================================================
// 权重通路：独占 wt2mcif/wt2cvif 读口与 cdma2buf_wt_wr 写口（512bit，
// 不经 cvt 转换）；压缩模式下额外取 WMB/WGS，向 CSC 报 kernels/
// wt_entries/wmb_entries 三种记账。与 dat 侧仅在 fsm_switch 处同步
NV_NVDLA_CDMA_wt u_wt (
   .nvdla_core_clk                (nvdla_op_gated_clk_wt)           //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.pwrbus_ram_pd                 (pwrbus_ram_pd[31:0])             //|< i
  ,.cdma_wt2mcif_rd_req_valid     (cdma_wt2mcif_rd_req_valid)       //|> o
  ,.cdma_wt2mcif_rd_req_ready     (cdma_wt2mcif_rd_req_ready)       //|< i
  ,.cdma_wt2mcif_rd_req_pd        (cdma_wt2mcif_rd_req_pd[78:0])    //|> o
  ,.cdma_wt2cvif_rd_req_valid     (cdma_wt2cvif_rd_req_valid)       //|> o
  ,.cdma_wt2cvif_rd_req_ready     (cdma_wt2cvif_rd_req_ready)       //|< i
  ,.cdma_wt2cvif_rd_req_pd        (cdma_wt2cvif_rd_req_pd[78:0])    //|> o
  ,.mcif2cdma_wt_rd_rsp_valid     (mcif2cdma_wt_rd_rsp_valid)       //|< i
  ,.mcif2cdma_wt_rd_rsp_ready     (mcif2cdma_wt_rd_rsp_ready)       //|> o
  ,.mcif2cdma_wt_rd_rsp_pd        (mcif2cdma_wt_rd_rsp_pd[513:0])   //|< i
  ,.cvif2cdma_wt_rd_rsp_valid     (cvif2cdma_wt_rd_rsp_valid)       //|< i
  ,.cvif2cdma_wt_rd_rsp_ready     (cvif2cdma_wt_rd_rsp_ready)       //|> o
  ,.cvif2cdma_wt_rd_rsp_pd        (cvif2cdma_wt_rd_rsp_pd[513:0])   //|< i
  ,.cdma2buf_wt_wr_en             (cdma2buf_wt_wr_en)               //|> o
  ,.cdma2buf_wt_wr_addr           (cdma2buf_wt_wr_addr[11:0])       //|> o
  ,.cdma2buf_wt_wr_hsel           (cdma2buf_wt_wr_hsel)             //|> o
  ,.cdma2buf_wt_wr_data           (cdma2buf_wt_wr_data[511:0])      //|> o
  ,.status2dma_fsm_switch         (status2dma_fsm_switch)           //|< w
  ,.wt2status_state               (wt2status_state[1:0])            //|> w
  ,.cdma2sc_wt_updt               (cdma2sc_wt_updt)                 //|> o
  ,.cdma2sc_wt_kernels            (cdma2sc_wt_kernels[13:0])        //|> o
  ,.cdma2sc_wt_entries            (cdma2sc_wt_entries[11:0])        //|> o
  ,.cdma2sc_wmb_entries           (cdma2sc_wmb_entries[8:0])        //|> o
  ,.sc2cdma_wt_updt               (sc2cdma_wt_updt)                 //|< i
  ,.sc2cdma_wt_kernels            (sc2cdma_wt_kernels[13:0])        //|< i
  ,.sc2cdma_wt_entries            (sc2cdma_wt_entries[11:0])        //|< i
  ,.sc2cdma_wmb_entries           (sc2cdma_wmb_entries[8:0])        //|< i
  ,.sc2cdma_wt_pending_req        (sc2cdma_wt_pending_req)          //|< i
  ,.cdma2sc_wt_pending_ack        (cdma2sc_wt_pending_ack)          //|> o
  ,.nvdla_core_ng_clk             (nvdla_core_clk)                  //|< i
  ,.reg2dp_arb_weight             (reg2dp_arb_weight[3:0])          //|< w
  ,.reg2dp_arb_wmb                (reg2dp_arb_wmb[3:0])             //|< w
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|< w
  ,.reg2dp_weight_reuse           (reg2dp_weight_reuse[0])          //|< w
  ,.reg2dp_skip_weight_rls        (reg2dp_skip_weight_rls[0])       //|< w
  ,.reg2dp_weight_format          (reg2dp_weight_format[0])         //|< w
  ,.reg2dp_byte_per_kernel        (reg2dp_byte_per_kernel[17:0])    //|< w
  ,.reg2dp_weight_kernel          (reg2dp_weight_kernel[12:0])      //|< w
  ,.reg2dp_weight_ram_type        (reg2dp_weight_ram_type[0])       //|< w
  ,.reg2dp_weight_addr_high       (reg2dp_weight_addr_high[31:0])   //|< w
  ,.reg2dp_weight_addr_low        (reg2dp_weight_addr_low[26:0])    //|< w
  ,.reg2dp_weight_bytes           (reg2dp_weight_bytes[24:0])       //|< w
  ,.reg2dp_wgs_addr_high          (reg2dp_wgs_addr_high[31:0])      //|< w
  ,.reg2dp_wgs_addr_low           (reg2dp_wgs_addr_low[26:0])       //|< w
  ,.reg2dp_wmb_addr_high          (reg2dp_wmb_addr_high[31:0])      //|< w
  ,.reg2dp_wmb_addr_low           (reg2dp_wmb_addr_low[26:0])       //|< w
  ,.reg2dp_wmb_bytes              (reg2dp_wmb_bytes[20:0])          //|< w
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|< w
  ,.reg2dp_weight_bank            (reg2dp_weight_bank[3:0])         //|< w
  ,.reg2dp_nan_to_zero            (reg2dp_nan_to_zero[0])           //|< w
  ,.reg2dp_dma_en                 (reg2dp_dma_en[0])                //|< w
  ,.dp2reg_nan_weight_num         (dp2reg_nan_weight_num[31:0])     //|> w
  ,.dp2reg_inf_weight_num         (dp2reg_inf_weight_num[31:0])     //|> w
  ,.dp2reg_wt_flush_done          (dp2reg_wt_flush_done)            //|> w
  ,.dp2reg_wt_rd_stall            (dp2reg_wt_rd_stall[31:0])        //|> w
  ,.dp2reg_wt_rd_latency          (dp2reg_wt_rd_latency[31:0])      //|> w
  );

//-------------- SLCG for weight DMA --------------//
// SLCG 统一模式（下同）：3 个使能源相与后门控时钟——src_0 接本域
// slcg_op_en[n]（regfile 按层配置给出），src_1/2 接交叉门控（无则 tie 1）；
// tmc2slcg_disable_clock_gating/clk_ovr 可全局强制不门控
NV_NVDLA_CDMA_slcg u_slcg_wt (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[0])                   //|< w
  ,.slcg_en_src_1                 (1'b1)                            //|< ?
  ,.slcg_en_src_2                 (1'b1)                            //|< ?
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_wt)           //|> w
  );

//==========================================================
// Direct convolution DMA
//==========================================================
// DC 通路：feature 数据（W×H×C surface 格式）取数，经 shared_buffer 两个
// 端口做 slice 重排后送 cvt（512bit + hsel 半字使能）；依据 status 回供的
// free_entries/wr_idx 决定发多少读请求、写到 cbuf 哪个 entry
NV_NVDLA_CDMA_dc u_dc (
   .nvdla_core_clk                (nvdla_op_gated_clk_dc)           //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.pwrbus_ram_pd                 (pwrbus_ram_pd[31:0])             //|< i
  ,.dc_dat2mcif_rd_req_valid      (dc_dat2mcif_rd_req_valid)        //|> w
  ,.dc_dat2mcif_rd_req_ready      (dc_dat2mcif_rd_req_ready)        //|< w
  ,.dc_dat2mcif_rd_req_pd         (dc_dat2mcif_rd_req_pd[78:0])     //|> w
  ,.dc_dat2cvif_rd_req_valid      (dc_dat2cvif_rd_req_valid)        //|> w
  ,.dc_dat2cvif_rd_req_ready      (dc_dat2cvif_rd_req_ready)        //|< w
  ,.dc_dat2cvif_rd_req_pd         (dc_dat2cvif_rd_req_pd[78:0])     //|> w
  ,.mcif2dc_dat_rd_rsp_valid      (mcif2dc_dat_rd_rsp_valid)        //|< w
  ,.mcif2dc_dat_rd_rsp_ready      (mcif2dc_dat_rd_rsp_ready)        //|> w
  ,.mcif2dc_dat_rd_rsp_pd         (mcif2dc_dat_rd_rsp_pd[513:0])    //|< w
  ,.cvif2dc_dat_rd_rsp_valid      (cvif2dc_dat_rd_rsp_valid)        //|< w
  ,.cvif2dc_dat_rd_rsp_ready      (cvif2dc_dat_rd_rsp_ready)        //|> w
  ,.cvif2dc_dat_rd_rsp_pd         (cvif2dc_dat_rd_rsp_pd[513:0])    //|< w
  ,.dc2cvt_dat_wr_en              (dc2cvt_dat_wr_en)                //|> w
  ,.dc2cvt_dat_wr_addr            (dc2cvt_dat_wr_addr[11:0])        //|> w
  ,.dc2cvt_dat_wr_hsel            (dc2cvt_dat_wr_hsel)              //|> w
  ,.dc2cvt_dat_wr_data            (dc2cvt_dat_wr_data[511:0])       //|> w
  ,.dc2cvt_dat_wr_info_pd         (dc2cvt_dat_wr_info_pd[11:0])     //|> w
  ,.status2dma_fsm_switch         (status2dma_fsm_switch)           //|< w
  ,.dc2status_state               (dc2status_state[1:0])            //|> w
  ,.dc2status_dat_updt            (dc2status_dat_updt)              //|> w
  ,.dc2status_dat_entries         (dc2status_dat_entries[11:0])     //|> w
  ,.dc2status_dat_slices          (dc2status_dat_slices[11:0])      //|> w
  ,.status2dma_valid_slices       (status2dma_valid_slices[11:0])   //|< w
  ,.status2dma_free_entries       (status2dma_free_entries[11:0])   //|< w
  ,.status2dma_wr_idx             (status2dma_wr_idx[11:0])         //|< w
  ,.dc2sbuf_p0_wr_en              (dc2sbuf_p0_wr_en)                //|> w
  ,.dc2sbuf_p0_wr_addr            (dc2sbuf_p0_wr_addr[7:0])         //|> w
  ,.dc2sbuf_p0_wr_data            (dc2sbuf_p0_wr_data[255:0])       //|> w
  ,.dc2sbuf_p1_wr_en              (dc2sbuf_p1_wr_en)                //|> w
  ,.dc2sbuf_p1_wr_addr            (dc2sbuf_p1_wr_addr[7:0])         //|> w
  ,.dc2sbuf_p1_wr_data            (dc2sbuf_p1_wr_data[255:0])       //|> w
  ,.dc2sbuf_p0_rd_en              (dc2sbuf_p0_rd_en)                //|> w
  ,.dc2sbuf_p0_rd_addr            (dc2sbuf_p0_rd_addr[7:0])         //|> w
  ,.dc2sbuf_p0_rd_data            (dc2sbuf_p0_rd_data[255:0])       //|< w
  ,.dc2sbuf_p1_rd_en              (dc2sbuf_p1_rd_en)                //|> w
  ,.dc2sbuf_p1_rd_addr            (dc2sbuf_p1_rd_addr[7:0])         //|> w
  ,.dc2sbuf_p1_rd_data            (dc2sbuf_p1_rd_data[255:0])       //|< w
  ,.sc2cdma_dat_pending_req       (sc2cdma_dat_pending_req)         //|< i
  ,.nvdla_core_ng_clk             (nvdla_core_clk)                  //|< i
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_conv_mode              (reg2dp_conv_mode[0])             //|< w
  ,.reg2dp_in_precision           (reg2dp_in_precision[1:0])        //|< w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|< w
  ,.reg2dp_data_reuse             (reg2dp_data_reuse[0])            //|< w
  ,.reg2dp_skip_data_rls          (reg2dp_skip_data_rls[0])         //|< w
  ,.reg2dp_datain_format          (reg2dp_datain_format[0])         //|< w
  ,.reg2dp_datain_width           (reg2dp_datain_width[12:0])       //|< w
  ,.reg2dp_datain_height          (reg2dp_datain_height[12:0])      //|< w
  ,.reg2dp_datain_channel         (reg2dp_datain_channel[12:0])     //|< w
  ,.reg2dp_datain_ram_type        (reg2dp_datain_ram_type[0])       //|< w
  ,.reg2dp_datain_addr_high_0     (reg2dp_datain_addr_high_0[31:0]) //|< w
  ,.reg2dp_datain_addr_low_0      (reg2dp_datain_addr_low_0[26:0])  //|< w
  ,.reg2dp_line_stride            (reg2dp_line_stride[26:0])        //|< w
  ,.reg2dp_surf_stride            (reg2dp_surf_stride[26:0])        //|< w
  ,.reg2dp_line_packed            (reg2dp_line_packed[0])           //|< w
  ,.reg2dp_surf_packed            (reg2dp_surf_packed[0])           //|< w
  ,.reg2dp_batches                (reg2dp_batches[4:0])             //|< w
  ,.reg2dp_batch_stride           (reg2dp_batch_stride[26:0])       //|< w
  ,.reg2dp_entries                (reg2dp_entries[11:0])            //|< w
  ,.reg2dp_grains                 (reg2dp_grains[11:0])             //|< w
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|< w
  ,.reg2dp_dma_en                 (reg2dp_dma_en[0])                //|< w
  ,.slcg_dc_gate_wg               (slcg_dc_gate_wg)                 //|> w
  ,.slcg_dc_gate_img              (slcg_dc_gate_img)                //|> w
  ,.dp2reg_dc_rd_stall            (dp2reg_dc_rd_stall[31:0])        //|> w
  ,.dp2reg_dc_rd_latency          (dp2reg_dc_rd_latency[31:0])      //|> w
  );

//-------------- SLCG for DC DMA --------------//
NV_NVDLA_CDMA_slcg u_slcg_dc (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[1])                   //|< w
  ,.slcg_en_src_1                 (slcg_wg_gate_dc)                 //|< w
  ,.slcg_en_src_2                 (slcg_img_gate_dc)                //|< w
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_dc)           //|> w
  );

//==========================================================
// Winograd convolution DMA
//==========================================================
// WG 通路：Winograd 模式取数，比 DC 多做 pad_left/right/top/bottom 边界
// 填充（pad_value）与 x/y stride 对齐，为 CMAC 的 PRA 预变换准备 4x4 tile
NV_NVDLA_CDMA_wg u_wg (
   .nvdla_core_clk                (nvdla_op_gated_clk_wg)           //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.pwrbus_ram_pd                 (pwrbus_ram_pd[31:0])             //|< i
  ,.wg_dat2mcif_rd_req_valid      (wg_dat2mcif_rd_req_valid)        //|> w
  ,.wg_dat2mcif_rd_req_ready      (wg_dat2mcif_rd_req_ready)        //|< w
  ,.wg_dat2mcif_rd_req_pd         (wg_dat2mcif_rd_req_pd[78:0])     //|> w
  ,.wg_dat2cvif_rd_req_valid      (wg_dat2cvif_rd_req_valid)        //|> w
  ,.wg_dat2cvif_rd_req_ready      (wg_dat2cvif_rd_req_ready)        //|< w
  ,.wg_dat2cvif_rd_req_pd         (wg_dat2cvif_rd_req_pd[78:0])     //|> w
  ,.mcif2wg_dat_rd_rsp_valid      (mcif2wg_dat_rd_rsp_valid)        //|< w
  ,.mcif2wg_dat_rd_rsp_ready      (mcif2wg_dat_rd_rsp_ready)        //|> w
  ,.mcif2wg_dat_rd_rsp_pd         (mcif2wg_dat_rd_rsp_pd[513:0])    //|< w
  ,.cvif2wg_dat_rd_rsp_valid      (cvif2wg_dat_rd_rsp_valid)        //|< w
  ,.cvif2wg_dat_rd_rsp_ready      (cvif2wg_dat_rd_rsp_ready)        //|> w
  ,.cvif2wg_dat_rd_rsp_pd         (cvif2wg_dat_rd_rsp_pd[513:0])    //|< w
  ,.wg2cvt_dat_wr_en              (wg2cvt_dat_wr_en)                //|> w
  ,.wg2cvt_dat_wr_addr            (wg2cvt_dat_wr_addr[11:0])        //|> w
  ,.wg2cvt_dat_wr_hsel            (wg2cvt_dat_wr_hsel)              //|> w
  ,.wg2cvt_dat_wr_data            (wg2cvt_dat_wr_data[511:0])       //|> w
  ,.wg2cvt_dat_wr_info_pd         (wg2cvt_dat_wr_info_pd[11:0])     //|> w
  ,.status2dma_fsm_switch         (status2dma_fsm_switch)           //|< w
  ,.wg2status_state               (wg2status_state[1:0])            //|> w
  ,.wg2status_dat_updt            (wg2status_dat_updt)              //|> w
  ,.wg2status_dat_entries         (wg2status_dat_entries[11:0])     //|> w
  ,.wg2status_dat_slices          (wg2status_dat_slices[11:0])      //|> w
  ,.status2dma_valid_slices       (status2dma_valid_slices[11:0])   //|< w
  ,.status2dma_free_entries       (status2dma_free_entries[11:0])   //|< w
  ,.status2dma_wr_idx             (status2dma_wr_idx[11:0])         //|< w
  ,.wg2sbuf_p0_wr_en              (wg2sbuf_p0_wr_en)                //|> w
  ,.wg2sbuf_p0_wr_addr            (wg2sbuf_p0_wr_addr[7:0])         //|> w
  ,.wg2sbuf_p0_wr_data            (wg2sbuf_p0_wr_data[255:0])       //|> w
  ,.wg2sbuf_p1_wr_en              (wg2sbuf_p1_wr_en)                //|> w
  ,.wg2sbuf_p1_wr_addr            (wg2sbuf_p1_wr_addr[7:0])         //|> w
  ,.wg2sbuf_p1_wr_data            (wg2sbuf_p1_wr_data[255:0])       //|> w
  ,.wg2sbuf_p0_rd_en              (wg2sbuf_p0_rd_en)                //|> w
  ,.wg2sbuf_p0_rd_addr            (wg2sbuf_p0_rd_addr[7:0])         //|> w
  ,.wg2sbuf_p0_rd_data            (wg2sbuf_p0_rd_data[255:0])       //|< w
  ,.wg2sbuf_p1_rd_en              (wg2sbuf_p1_rd_en)                //|> w
  ,.wg2sbuf_p1_rd_addr            (wg2sbuf_p1_rd_addr[7:0])         //|> w
  ,.wg2sbuf_p1_rd_data            (wg2sbuf_p1_rd_data[255:0])       //|< w
  ,.sc2cdma_dat_pending_req       (sc2cdma_dat_pending_req)         //|< i
  ,.nvdla_core_ng_clk             (nvdla_core_clk)                  //|< i
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_conv_mode              (reg2dp_conv_mode[0])             //|< w
  ,.reg2dp_in_precision           (reg2dp_in_precision[1:0])        //|< w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|< w
  ,.reg2dp_data_reuse             (reg2dp_data_reuse[0])            //|< w
  ,.reg2dp_skip_data_rls          (reg2dp_skip_data_rls[0])         //|< w
  ,.reg2dp_datain_format          (reg2dp_datain_format[0])         //|< w
  ,.reg2dp_datain_width           (reg2dp_datain_width[12:0])       //|< w
  ,.reg2dp_datain_height          (reg2dp_datain_height[12:0])      //|< w
  ,.reg2dp_datain_width_ext       (reg2dp_datain_width_ext[12:0])   //|< w
  ,.reg2dp_datain_height_ext      (reg2dp_datain_height_ext[12:0])  //|< w
  ,.reg2dp_datain_channel         (reg2dp_datain_channel[12:0])     //|< w
  ,.reg2dp_datain_ram_type        (reg2dp_datain_ram_type[0])       //|< w
  ,.reg2dp_datain_addr_high_0     (reg2dp_datain_addr_high_0[31:0]) //|< w
  ,.reg2dp_datain_addr_low_0      (reg2dp_datain_addr_low_0[26:0])  //|< w
  ,.reg2dp_line_stride            (reg2dp_line_stride[26:0])        //|< w
  ,.reg2dp_surf_stride            (reg2dp_surf_stride[26:0])        //|< w
  ,.reg2dp_entries                (reg2dp_entries[11:0])            //|< w
  ,.reg2dp_conv_x_stride          (reg2dp_conv_x_stride[2:0])       //|< w
  ,.reg2dp_conv_y_stride          (reg2dp_conv_y_stride[2:0])       //|< w
  ,.reg2dp_pad_left               (reg2dp_pad_left[4:0])            //|< w
  ,.reg2dp_pad_right              (reg2dp_pad_right[5:0])           //|< w
  ,.reg2dp_pad_top                (reg2dp_pad_top[4:0])             //|< w
  ,.reg2dp_pad_bottom             (reg2dp_pad_bottom[5:0])          //|< w
  ,.reg2dp_pad_value              (reg2dp_pad_value[15:0])          //|< w
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|< w
  ,.reg2dp_dma_en                 (reg2dp_dma_en[0])                //|< w
  ,.slcg_wg_gate_dc               (slcg_wg_gate_dc)                 //|> w
  ,.slcg_wg_gate_img              (slcg_wg_gate_img)                //|> w
  ,.dp2reg_wg_rd_stall            (dp2reg_wg_rd_stall[31:0])        //|> w
  ,.dp2reg_wg_rd_latency          (dp2reg_wg_rd_latency[31:0])      //|> w
  );

//-------------- SLCG for WG DMA --------------//
NV_NVDLA_CDMA_slcg u_slcg_wg (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[2])                   //|< w
  ,.slcg_en_src_1                 (slcg_dc_gate_wg)                 //|< w
  ,.slcg_en_src_2                 (slcg_img_gate_wg)                //|< w
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_wg)           //|> w
  );

//==========================================================
// Image convolution DMA
//==========================================================
// IMG 通路：第一层图像输入（RGB/YUV 多种 pixel_format），做像素重映射与
// 通道扩展；输出比 DC/WG 宽一倍（1024bit）且带 mean 数据总线与 pad_mask
// （逐像素标记 pad 位置，供 cvt 决定该字节用 pad_value 还是做均值减除）
NV_NVDLA_CDMA_img u_img (
   .nvdla_core_clk                (nvdla_op_gated_clk_img)          //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.pwrbus_ram_pd                 (pwrbus_ram_pd[31:0])             //|< i
  ,.img_dat2mcif_rd_req_valid     (img_dat2mcif_rd_req_valid)       //|> w
  ,.img_dat2mcif_rd_req_ready     (img_dat2mcif_rd_req_ready)       //|< w
  ,.img_dat2mcif_rd_req_pd        (img_dat2mcif_rd_req_pd[78:0])    //|> w
  ,.img_dat2cvif_rd_req_valid     (img_dat2cvif_rd_req_valid)       //|> w
  ,.img_dat2cvif_rd_req_ready     (img_dat2cvif_rd_req_ready)       //|< w
  ,.img_dat2cvif_rd_req_pd        (img_dat2cvif_rd_req_pd[78:0])    //|> w
  ,.mcif2img_dat_rd_rsp_valid     (mcif2img_dat_rd_rsp_valid)       //|< w
  ,.mcif2img_dat_rd_rsp_ready     (mcif2img_dat_rd_rsp_ready)       //|> w
  ,.mcif2img_dat_rd_rsp_pd        (mcif2img_dat_rd_rsp_pd[513:0])   //|< w
  ,.cvif2img_dat_rd_rsp_valid     (cvif2img_dat_rd_rsp_valid)       //|< w
  ,.cvif2img_dat_rd_rsp_ready     (cvif2img_dat_rd_rsp_ready)       //|> w
  ,.cvif2img_dat_rd_rsp_pd        (cvif2img_dat_rd_rsp_pd[513:0])   //|< w
  ,.img2cvt_dat_wr_en             (img2cvt_dat_wr_en)               //|> w
  ,.img2cvt_dat_wr_addr           (img2cvt_dat_wr_addr[11:0])       //|> w
  ,.img2cvt_dat_wr_hsel           (img2cvt_dat_wr_hsel)             //|> w
  ,.img2cvt_dat_wr_data           (img2cvt_dat_wr_data[1023:0])     //|> w
  ,.img2cvt_mn_wr_data            (img2cvt_mn_wr_data[1023:0])      //|> w
  ,.img2cvt_dat_wr_info_pd        (img2cvt_dat_wr_info_pd[11:0])    //|> w
  ,.status2dma_fsm_switch         (status2dma_fsm_switch)           //|< w
  ,.img2status_state              (img2status_state[1:0])           //|> w
  ,.img2status_dat_updt           (img2status_dat_updt)             //|> w
  ,.img2status_dat_entries        (img2status_dat_entries[11:0])    //|> w
  ,.img2status_dat_slices         (img2status_dat_slices[11:0])     //|> w
  ,.status2dma_valid_slices       (status2dma_valid_slices[11:0])   //|< w
  ,.status2dma_free_entries       (status2dma_free_entries[11:0])   //|< w
  ,.status2dma_wr_idx             (status2dma_wr_idx[11:0])         //|< w
  ,.img2sbuf_p0_wr_en             (img2sbuf_p0_wr_en)               //|> w
  ,.img2sbuf_p0_wr_addr           (img2sbuf_p0_wr_addr[7:0])        //|> w
  ,.img2sbuf_p0_wr_data           (img2sbuf_p0_wr_data[255:0])      //|> w
  ,.img2sbuf_p1_wr_en             (img2sbuf_p1_wr_en)               //|> w
  ,.img2sbuf_p1_wr_addr           (img2sbuf_p1_wr_addr[7:0])        //|> w
  ,.img2sbuf_p1_wr_data           (img2sbuf_p1_wr_data[255:0])      //|> w
  ,.img2sbuf_p0_rd_en             (img2sbuf_p0_rd_en)               //|> w
  ,.img2sbuf_p0_rd_addr           (img2sbuf_p0_rd_addr[7:0])        //|> w
  ,.img2sbuf_p0_rd_data           (img2sbuf_p0_rd_data[255:0])      //|< w
  ,.img2sbuf_p1_rd_en             (img2sbuf_p1_rd_en)               //|> w
  ,.img2sbuf_p1_rd_addr           (img2sbuf_p1_rd_addr[7:0])        //|> w
  ,.img2sbuf_p1_rd_data           (img2sbuf_p1_rd_data[255:0])      //|< w
  ,.sc2cdma_dat_pending_req       (sc2cdma_dat_pending_req)         //|< i
  ,.nvdla_core_ng_clk             (nvdla_core_clk)                  //|< i
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_conv_mode              (reg2dp_conv_mode[0])             //|< w
  ,.reg2dp_in_precision           (reg2dp_in_precision[1:0])        //|< w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|< w
  ,.reg2dp_data_reuse             (reg2dp_data_reuse[0])            //|< w
  ,.reg2dp_skip_data_rls          (reg2dp_skip_data_rls[0])         //|< w
  ,.reg2dp_datain_format          (reg2dp_datain_format[0])         //|< w
  ,.reg2dp_pixel_format           (reg2dp_pixel_format[5:0])        //|< w
  ,.reg2dp_pixel_mapping          (reg2dp_pixel_mapping[0])         //|< w
  ,.reg2dp_pixel_sign_override    (reg2dp_pixel_sign_override[0])   //|< w
  ,.reg2dp_datain_width           (reg2dp_datain_width[12:0])       //|< w
  ,.reg2dp_datain_height          (reg2dp_datain_height[12:0])      //|< w
  ,.reg2dp_datain_channel         (reg2dp_datain_channel[12:0])     //|< w
  ,.reg2dp_pixel_x_offset         (reg2dp_pixel_x_offset[4:0])      //|< w
  ,.reg2dp_pixel_y_offset         (reg2dp_pixel_y_offset[2:0])      //|< w
  ,.reg2dp_datain_ram_type        (reg2dp_datain_ram_type[0])       //|< w
  ,.reg2dp_datain_addr_high_0     (reg2dp_datain_addr_high_0[31:0]) //|< w
  ,.reg2dp_datain_addr_low_0      (reg2dp_datain_addr_low_0[26:0])  //|< w
  ,.reg2dp_datain_addr_high_1     (reg2dp_datain_addr_high_1[31:0]) //|< w
  ,.reg2dp_datain_addr_low_1      (reg2dp_datain_addr_low_1[26:0])  //|< w
  ,.reg2dp_line_stride            (reg2dp_line_stride[26:0])        //|< w
  ,.reg2dp_uv_line_stride         (reg2dp_uv_line_stride[26:0])     //|< w
  ,.reg2dp_mean_format            (reg2dp_mean_format[0])           //|< w
  ,.reg2dp_mean_ry                (reg2dp_mean_ry[15:0])            //|< w
  ,.reg2dp_mean_gu                (reg2dp_mean_gu[15:0])            //|< w
  ,.reg2dp_mean_bv                (reg2dp_mean_bv[15:0])            //|< w
  ,.reg2dp_mean_ax                (reg2dp_mean_ax[15:0])            //|< w
  ,.reg2dp_entries                (reg2dp_entries[11:0])            //|< w
  ,.reg2dp_pad_left               (reg2dp_pad_left[4:0])            //|< w
  ,.reg2dp_pad_right              (reg2dp_pad_right[5:0])           //|< w
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|< w
  ,.reg2dp_dma_en                 (reg2dp_dma_en[0])                //|< w
  ,.reg2dp_rsv_per_line           (reg2dp_rsv_per_line[9:0])        //|< w
  ,.reg2dp_rsv_per_uv_line        (reg2dp_rsv_per_uv_line[9:0])     //|< w
  ,.reg2dp_rsv_height             (reg2dp_rsv_height[2:0])          //|< w
  ,.reg2dp_rsv_y_index            (reg2dp_rsv_y_index[4:0])         //|< w
  ,.slcg_img_gate_dc              (slcg_img_gate_dc)                //|> w
  ,.slcg_img_gate_wg              (slcg_img_gate_wg)                //|> w
  ,.dp2reg_img_rd_stall           (dp2reg_img_rd_stall[31:0])       //|> w
  ,.dp2reg_img_rd_latency         (dp2reg_img_rd_latency[31:0])     //|> w
  ,.img2cvt_dat_wr_pad_mask       (img2cvt_dat_wr_pad_mask[127:0])  //|> w
  );

//-------------- SLCG for IMG DMA --------------//
NV_NVDLA_CDMA_slcg u_slcg_img (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[3])                   //|< w
  ,.slcg_en_src_1                 (slcg_dc_gate_img)                //|< w
  ,.slcg_en_src_2                 (slcg_wg_gate_img)                //|< w
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_img)          //|> w
  );

//==========================================================
// DMA mux
//==========================================================
// dat 侧三客户端（dc/wg/img）合一：无仲裁器，req 方向按位或直接汇合
// （依赖三通路层内互斥，断言兜底），rsp 方向按寄存的客户端标志分流回
// 发起方（详见该文件注释）。mux 的意义在于顶层只占一对 dat 读口
NV_NVDLA_CDMA_dma_mux u_dma_mux (
   .nvdla_core_clk                (nvdla_op_gated_clk_mux)          //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.dc_dat2mcif_rd_req_valid      (dc_dat2mcif_rd_req_valid)        //|< w
  ,.dc_dat2mcif_rd_req_ready      (dc_dat2mcif_rd_req_ready)        //|> w
  ,.dc_dat2mcif_rd_req_pd         (dc_dat2mcif_rd_req_pd[78:0])     //|< w
  ,.dc_dat2cvif_rd_req_valid      (dc_dat2cvif_rd_req_valid)        //|< w
  ,.dc_dat2cvif_rd_req_ready      (dc_dat2cvif_rd_req_ready)        //|> w
  ,.dc_dat2cvif_rd_req_pd         (dc_dat2cvif_rd_req_pd[78:0])     //|< w
  ,.wg_dat2mcif_rd_req_valid      (wg_dat2mcif_rd_req_valid)        //|< w
  ,.wg_dat2mcif_rd_req_ready      (wg_dat2mcif_rd_req_ready)        //|> w
  ,.wg_dat2mcif_rd_req_pd         (wg_dat2mcif_rd_req_pd[78:0])     //|< w
  ,.wg_dat2cvif_rd_req_valid      (wg_dat2cvif_rd_req_valid)        //|< w
  ,.wg_dat2cvif_rd_req_ready      (wg_dat2cvif_rd_req_ready)        //|> w
  ,.wg_dat2cvif_rd_req_pd         (wg_dat2cvif_rd_req_pd[78:0])     //|< w
  ,.img_dat2mcif_rd_req_valid     (img_dat2mcif_rd_req_valid)       //|< w
  ,.img_dat2mcif_rd_req_ready     (img_dat2mcif_rd_req_ready)       //|> w
  ,.img_dat2mcif_rd_req_pd        (img_dat2mcif_rd_req_pd[78:0])    //|< w
  ,.img_dat2cvif_rd_req_valid     (img_dat2cvif_rd_req_valid)       //|< w
  ,.img_dat2cvif_rd_req_ready     (img_dat2cvif_rd_req_ready)       //|> w
  ,.img_dat2cvif_rd_req_pd        (img_dat2cvif_rd_req_pd[78:0])    //|< w
  ,.cdma_dat2mcif_rd_req_valid    (cdma_dat2mcif_rd_req_valid)      //|> o
  ,.cdma_dat2mcif_rd_req_ready    (cdma_dat2mcif_rd_req_ready)      //|< i
  ,.cdma_dat2mcif_rd_req_pd       (cdma_dat2mcif_rd_req_pd[78:0])   //|> o
  ,.cdma_dat2cvif_rd_req_valid    (cdma_dat2cvif_rd_req_valid)      //|> o
  ,.cdma_dat2cvif_rd_req_ready    (cdma_dat2cvif_rd_req_ready)      //|< i
  ,.cdma_dat2cvif_rd_req_pd       (cdma_dat2cvif_rd_req_pd[78:0])   //|> o
  ,.mcif2cdma_dat_rd_rsp_valid    (mcif2cdma_dat_rd_rsp_valid)      //|< i
  ,.mcif2cdma_dat_rd_rsp_ready    (mcif2cdma_dat_rd_rsp_ready)      //|> o
  ,.mcif2cdma_dat_rd_rsp_pd       (mcif2cdma_dat_rd_rsp_pd[513:0])  //|< i
  ,.cvif2cdma_dat_rd_rsp_valid    (cvif2cdma_dat_rd_rsp_valid)      //|< i
  ,.cvif2cdma_dat_rd_rsp_ready    (cvif2cdma_dat_rd_rsp_ready)      //|> o
  ,.cvif2cdma_dat_rd_rsp_pd       (cvif2cdma_dat_rd_rsp_pd[513:0])  //|< i
  ,.mcif2dc_dat_rd_rsp_valid      (mcif2dc_dat_rd_rsp_valid)        //|> w
  ,.mcif2dc_dat_rd_rsp_ready      (mcif2dc_dat_rd_rsp_ready)        //|< w
  ,.mcif2dc_dat_rd_rsp_pd         (mcif2dc_dat_rd_rsp_pd[513:0])    //|> w
  ,.cvif2dc_dat_rd_rsp_valid      (cvif2dc_dat_rd_rsp_valid)        //|> w
  ,.cvif2dc_dat_rd_rsp_ready      (cvif2dc_dat_rd_rsp_ready)        //|< w
  ,.cvif2dc_dat_rd_rsp_pd         (cvif2dc_dat_rd_rsp_pd[513:0])    //|> w
  ,.mcif2wg_dat_rd_rsp_valid      (mcif2wg_dat_rd_rsp_valid)        //|> w
  ,.mcif2wg_dat_rd_rsp_ready      (mcif2wg_dat_rd_rsp_ready)        //|< w
  ,.mcif2wg_dat_rd_rsp_pd         (mcif2wg_dat_rd_rsp_pd[513:0])    //|> w
  ,.cvif2wg_dat_rd_rsp_valid      (cvif2wg_dat_rd_rsp_valid)        //|> w
  ,.cvif2wg_dat_rd_rsp_ready      (cvif2wg_dat_rd_rsp_ready)        //|< w
  ,.cvif2wg_dat_rd_rsp_pd         (cvif2wg_dat_rd_rsp_pd[513:0])    //|> w
  ,.mcif2img_dat_rd_rsp_valid     (mcif2img_dat_rd_rsp_valid)       //|> w
  ,.mcif2img_dat_rd_rsp_ready     (mcif2img_dat_rd_rsp_ready)       //|< w
  ,.mcif2img_dat_rd_rsp_pd        (mcif2img_dat_rd_rsp_pd[513:0])   //|> w
  ,.cvif2img_dat_rd_rsp_valid     (cvif2img_dat_rd_rsp_valid)       //|> w
  ,.cvif2img_dat_rd_rsp_ready     (cvif2img_dat_rd_rsp_ready)       //|< w
  ,.cvif2img_dat_rd_rsp_pd        (cvif2img_dat_rd_rsp_pd[513:0])   //|> w
  );

//-------------- SLCG for MUX --------------//
NV_NVDLA_CDMA_slcg u_slcg_mux (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[4])                   //|< w
  ,.slcg_en_src_1                 (1'b1)                            //|< ?
  ,.slcg_en_src_2                 (1'b1)                            //|< ?
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_mux)          //|> w
  );

//==========================================================
// DMA data convertor
//==========================================================
// 精度/格式转换级：dc|wg|img 三路写流在此汇合（互斥，无仲裁），按
// cvt_en/scale/offset/truncate 做定点缩放截断，IMG 路再按 pad_mask 选择
// pad_value 或均值减除；输出统一 1024bit + 2bit hsel 写 cbuf 数据区
NV_NVDLA_CDMA_cvt u_cvt (
   .nvdla_core_clk                (nvdla_op_gated_clk_cvt)          //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.dc2cvt_dat_wr_en              (dc2cvt_dat_wr_en)                //|< w
  ,.dc2cvt_dat_wr_addr            (dc2cvt_dat_wr_addr[11:0])        //|< w
  ,.dc2cvt_dat_wr_hsel            (dc2cvt_dat_wr_hsel)              //|< w
  ,.dc2cvt_dat_wr_data            (dc2cvt_dat_wr_data[511:0])       //|< w
  ,.wg2cvt_dat_wr_en              (wg2cvt_dat_wr_en)                //|< w
  ,.wg2cvt_dat_wr_addr            (wg2cvt_dat_wr_addr[11:0])        //|< w
  ,.wg2cvt_dat_wr_hsel            (wg2cvt_dat_wr_hsel)              //|< w
  ,.wg2cvt_dat_wr_data            (wg2cvt_dat_wr_data[511:0])       //|< w
  ,.img2cvt_dat_wr_en             (img2cvt_dat_wr_en)               //|< w
  ,.img2cvt_dat_wr_addr           (img2cvt_dat_wr_addr[11:0])       //|< w
  ,.img2cvt_dat_wr_hsel           (img2cvt_dat_wr_hsel)             //|< w
  ,.img2cvt_dat_wr_data           (img2cvt_dat_wr_data[1023:0])     //|< w
  ,.img2cvt_mn_wr_data            (img2cvt_mn_wr_data[1023:0])      //|< w
  ,.dc2cvt_dat_wr_info_pd         (dc2cvt_dat_wr_info_pd[11:0])     //|< w
  ,.wg2cvt_dat_wr_info_pd         (wg2cvt_dat_wr_info_pd[11:0])     //|< w
  ,.img2cvt_dat_wr_info_pd        (img2cvt_dat_wr_info_pd[11:0])    //|< w
  ,.cdma2buf_dat_wr_en            (cdma2buf_dat_wr_en)              //|> o
  ,.cdma2buf_dat_wr_addr          (cdma2buf_dat_wr_addr[11:0])      //|> o
  ,.cdma2buf_dat_wr_hsel          (cdma2buf_dat_wr_hsel[1:0])       //|> o
  ,.cdma2buf_dat_wr_data          (cdma2buf_dat_wr_data[1023:0])    //|> o
  ,.nvdla_hls_clk                 (nvdla_hls_gated_clk_cvt)         //|< w
  ,.slcg_hls_en                   (slcg_hls_en)                     //|> w
  ,.nvdla_core_ng_clk             (nvdla_core_clk)                  //|< i
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_in_precision           (reg2dp_in_precision[1:0])        //|< w
  ,.reg2dp_proc_precision         (reg2dp_proc_precision[1:0])      //|< w
  ,.reg2dp_cvt_en                 (reg2dp_cvt_en[0])                //|< w
  ,.reg2dp_cvt_truncate           (reg2dp_cvt_truncate[5:0])        //|< w
  ,.reg2dp_cvt_offset             (reg2dp_cvt_offset[15:0])         //|< w
  ,.reg2dp_cvt_scale              (reg2dp_cvt_scale[15:0])          //|< w
  ,.reg2dp_nan_to_zero            (reg2dp_nan_to_zero[0])           //|< w
  ,.reg2dp_pad_value              (reg2dp_pad_value[15:0])          //|< w
  ,.dp2reg_done                   (dp2reg_done)                     //|< w
  ,.img2cvt_dat_wr_pad_mask       (img2cvt_dat_wr_pad_mask[127:0])  //|< w
  ,.dp2reg_nan_data_num           (dp2reg_nan_data_num[31:0])       //|> w
  ,.dp2reg_inf_data_num           (dp2reg_inf_data_num[31:0])       //|> w
  ,.dp2reg_dat_flush_done         (dp2reg_dat_flush_done)           //|> w
  );

//-------------- SLCG for CVT --------------//
NV_NVDLA_CDMA_slcg u_slcg_cvt (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[5])                   //|< w
  ,.slcg_en_src_1                 (1'b1)                            //|< ?
  ,.slcg_en_src_2                 (1'b1)                            //|< ?
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_cvt)          //|> w
  );

//-------------- SLCG for CVT HLS CELL --------------//
NV_NVDLA_CDMA_slcg u_slcg_hls (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[6])                   //|< w
  ,.slcg_en_src_1                 (slcg_hls_en)                     //|< w
  ,.slcg_en_src_2                 (1'b1)                            //|< ?
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_hls_gated_clk_cvt)         //|> w
  );

//==========================================================
// Shared buffer
//==========================================================
// 三通路共享的行缓冲 SRAM（p0/p1 两个 256bit 读写端口，256 深）：
// dc/wg/img 谁活跃谁用（三套端口在内部一对一复用到同一 RAM），
// 用于把乱序/窄的 DMA 回数据攒成整 slice 再送 cvt
NV_NVDLA_CDMA_shared_buffer u_shared_buffer (
   .nvdla_core_clk                (nvdla_op_gated_clk_buffer)       //|< w
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.pwrbus_ram_pd                 (pwrbus_ram_pd[31:0])             //|< i
  ,.dc2sbuf_p0_wr_en              (dc2sbuf_p0_wr_en)                //|< w
  ,.dc2sbuf_p0_wr_addr            (dc2sbuf_p0_wr_addr[7:0])         //|< w
  ,.dc2sbuf_p0_wr_data            (dc2sbuf_p0_wr_data[255:0])       //|< w
  ,.dc2sbuf_p1_wr_en              (dc2sbuf_p1_wr_en)                //|< w
  ,.dc2sbuf_p1_wr_addr            (dc2sbuf_p1_wr_addr[7:0])         //|< w
  ,.dc2sbuf_p1_wr_data            (dc2sbuf_p1_wr_data[255:0])       //|< w
  ,.wg2sbuf_p0_wr_en              (wg2sbuf_p0_wr_en)                //|< w
  ,.wg2sbuf_p0_wr_addr            (wg2sbuf_p0_wr_addr[7:0])         //|< w
  ,.wg2sbuf_p0_wr_data            (wg2sbuf_p0_wr_data[255:0])       //|< w
  ,.wg2sbuf_p1_wr_en              (wg2sbuf_p1_wr_en)                //|< w
  ,.wg2sbuf_p1_wr_addr            (wg2sbuf_p1_wr_addr[7:0])         //|< w
  ,.wg2sbuf_p1_wr_data            (wg2sbuf_p1_wr_data[255:0])       //|< w
  ,.img2sbuf_p0_wr_en             (img2sbuf_p0_wr_en)               //|< w
  ,.img2sbuf_p0_wr_addr           (img2sbuf_p0_wr_addr[7:0])        //|< w
  ,.img2sbuf_p0_wr_data           (img2sbuf_p0_wr_data[255:0])      //|< w
  ,.img2sbuf_p1_wr_en             (img2sbuf_p1_wr_en)               //|< w
  ,.img2sbuf_p1_wr_addr           (img2sbuf_p1_wr_addr[7:0])        //|< w
  ,.img2sbuf_p1_wr_data           (img2sbuf_p1_wr_data[255:0])      //|< w
  ,.dc2sbuf_p0_rd_en              (dc2sbuf_p0_rd_en)                //|< w
  ,.dc2sbuf_p0_rd_addr            (dc2sbuf_p0_rd_addr[7:0])         //|< w
  ,.dc2sbuf_p0_rd_data            (dc2sbuf_p0_rd_data[255:0])       //|> w
  ,.dc2sbuf_p1_rd_en              (dc2sbuf_p1_rd_en)                //|< w
  ,.dc2sbuf_p1_rd_addr            (dc2sbuf_p1_rd_addr[7:0])         //|< w
  ,.dc2sbuf_p1_rd_data            (dc2sbuf_p1_rd_data[255:0])       //|> w
  ,.wg2sbuf_p0_rd_en              (wg2sbuf_p0_rd_en)                //|< w
  ,.wg2sbuf_p0_rd_addr            (wg2sbuf_p0_rd_addr[7:0])         //|< w
  ,.wg2sbuf_p0_rd_data            (wg2sbuf_p0_rd_data[255:0])       //|> w
  ,.wg2sbuf_p1_rd_en              (wg2sbuf_p1_rd_en)                //|< w
  ,.wg2sbuf_p1_rd_addr            (wg2sbuf_p1_rd_addr[7:0])         //|< w
  ,.wg2sbuf_p1_rd_data            (wg2sbuf_p1_rd_data[255:0])       //|> w
  ,.img2sbuf_p0_rd_en             (img2sbuf_p0_rd_en)               //|< w
  ,.img2sbuf_p0_rd_addr           (img2sbuf_p0_rd_addr[7:0])        //|< w
  ,.img2sbuf_p0_rd_data           (img2sbuf_p0_rd_data[255:0])      //|> w
  ,.img2sbuf_p1_rd_en             (img2sbuf_p1_rd_en)               //|< w
  ,.img2sbuf_p1_rd_addr           (img2sbuf_p1_rd_addr[7:0])        //|< w
  ,.img2sbuf_p1_rd_data           (img2sbuf_p1_rd_data[255:0])      //|> w
  );

//-------------- SLCG for shared buffer --------------//
NV_NVDLA_CDMA_slcg u_slcg_buffer (
   .dla_clk_ovr_on_sync           (dla_clk_ovr_on_sync)             //|< i
  ,.global_clk_ovr_on_sync        (global_clk_ovr_on_sync)          //|< i
  ,.nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.slcg_en_src_0                 (slcg_op_en[7])                   //|< w
  ,.slcg_en_src_1                 (1'b1)                            //|< ?
  ,.slcg_en_src_2                 (1'b1)                            //|< ?
  ,.tmc2slcg_disable_clock_gating (tmc2slcg_disable_clock_gating)   //|< i
  ,.nvdla_core_gated_clk          (nvdla_op_gated_clk_buffer)       //|> w
  );

//==========================================================
// CDMA status controller
//==========================================================
// 记账与切层中枢：汇聚 dc/wg/img 的写入增量与 CSC 的释放量维护数据区
// 占用（free_entries/valid_slices/wr_idx 回供各 DMA）；等 dat+wt 双侧
// done 才发 fsm_switch/dp2reg_done/done 中断；并处理 CSC 发起的
// pending req/ack 层间握手（详见该文件注释）
NV_NVDLA_CDMA_status u_status (
   .nvdla_core_clk                (nvdla_core_clk)                  //|< i
  ,.nvdla_core_rstn               (nvdla_core_rstn)                 //|< i
  ,.dc2status_dat_updt            (dc2status_dat_updt)              //|< w
  ,.dc2status_dat_entries         (dc2status_dat_entries[11:0])     //|< w
  ,.dc2status_dat_slices          (dc2status_dat_slices[11:0])      //|< w
  ,.wg2status_dat_updt            (wg2status_dat_updt)              //|< w
  ,.wg2status_dat_entries         (wg2status_dat_entries[11:0])     //|< w
  ,.wg2status_dat_slices          (wg2status_dat_slices[11:0])      //|< w
  ,.img2status_dat_updt           (img2status_dat_updt)             //|< w
  ,.img2status_dat_entries        (img2status_dat_entries[11:0])    //|< w
  ,.img2status_dat_slices         (img2status_dat_slices[11:0])     //|< w
  ,.sc2cdma_dat_updt              (sc2cdma_dat_updt)                //|< i
  ,.sc2cdma_dat_entries           (sc2cdma_dat_entries[11:0])       //|< i
  ,.sc2cdma_dat_slices            (sc2cdma_dat_slices[11:0])        //|< i
  ,.cdma2sc_dat_updt              (cdma2sc_dat_updt)                //|> o
  ,.cdma2sc_dat_entries           (cdma2sc_dat_entries[11:0])       //|> o
  ,.cdma2sc_dat_slices            (cdma2sc_dat_slices[11:0])        //|> o
  ,.status2dma_valid_slices       (status2dma_valid_slices[11:0])   //|> w
  ,.status2dma_free_entries       (status2dma_free_entries[11:0])   //|> w
  ,.status2dma_wr_idx             (status2dma_wr_idx[11:0])         //|> w
  ,.dc2status_state               (dc2status_state[1:0])            //|< w
  ,.wg2status_state               (wg2status_state[1:0])            //|< w
  ,.img2status_state              (img2status_state[1:0])           //|< w
  ,.wt2status_state               (wt2status_state[1:0])            //|< w
  ,.dp2reg_done                   (dp2reg_done)                     //|> w
  ,.status2dma_fsm_switch         (status2dma_fsm_switch)           //|> w
  ,.cdma_wt2glb_done_intr_pd      (cdma_wt2glb_done_intr_pd[1:0])   //|> o
  ,.cdma_dat2glb_done_intr_pd     (cdma_dat2glb_done_intr_pd[1:0])  //|> o
  ,.sc2cdma_dat_pending_req       (sc2cdma_dat_pending_req)         //|< i
  ,.cdma2sc_dat_pending_ack       (cdma2sc_dat_pending_ack)         //|> o
  ,.reg2dp_op_en                  (reg2dp_op_en[0])                 //|< w
  ,.reg2dp_data_bank              (reg2dp_data_bank[3:0])           //|< w
  ,.dp2reg_consumer               (dp2reg_consumer)                 //|< w
  );

////    &Connect    nvdla_core_clk          nvdla_op_gated_clk_status;
////    &Connect    nvdla_core_ng_clk       nvdla_core_clk;
////
//////-------------- SLCG for CVT --------------//
////&Instance NV_NVDLA_CDMA_slcg u_slcg_status;
////    &Connect    slcg_en_src_0           slcg_op_en[8];
////    &Connect    slcg_en_src_1           1'b1;
////    &Connect    slcg_en_src_2           1'b1;
////    &Connect    nvdla_core_gated_clk    nvdla_op_gated_clk_status;

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
  nv_assert_zero_one_hot #(0,3,0,"Error! DC, WG and IMG slcg gate signal conflict!")      zzz_assert_zero_one_hot_1x (nvdla_core_clk, `ASSERT_RESET, ({~slcg_dc_gate_wg, ~slcg_wg_gate_img, ~slcg_img_gate_dc})); // spyglass disable W504 SelfDeterminedExpr-ML 
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
  nv_assert_never #(0,0,"Error! Two DC slcg signal mismatch!")      zzz_assert_never_2x (nvdla_core_clk, `ASSERT_RESET, (slcg_dc_gate_wg ^ slcg_dc_gate_img)); // spyglass disable W504 SelfDeterminedExpr-ML 
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
  nv_assert_never #(0,0,"Error! Two WG slcg signal mismatch!")      zzz_assert_never_3x (nvdla_core_clk, `ASSERT_RESET, (slcg_wg_gate_dc ^ slcg_wg_gate_img)); // spyglass disable W504 SelfDeterminedExpr-ML 
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
  nv_assert_never #(0,0,"Error! Two IMG slcg signal mismatch!")      zzz_assert_never_4x (nvdla_core_clk, `ASSERT_RESET, (slcg_img_gate_dc ^ slcg_img_gate_wg)); // spyglass disable W504 SelfDeterminedExpr-ML 
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

// ////////////////////////////////////////////////////////////////////////
// //  OBS connection                                                    //
// ////////////////////////////////////////////////////////////////////////
// assign obs_bus_cdma_slcg_op_en       = slcg_op_en;
// assign obs_bus_cdma_slcg_dc_gate_wg  = slcg_dc_gate_wg;
// assign obs_bus_cdma_slcg_dc_gate_img = slcg_dc_gate_img;
// assign obs_bus_cdma_slcg_wg_gate_dc  = slcg_wg_gate_dc;
// assign obs_bus_cdma_slcg_wg_gate_img = slcg_wg_gate_img;
// assign obs_bus_cdma_slcg_img_gate_dc = slcg_img_gate_dc;
// assign obs_bus_cdma_slcg_img_gate_wg = slcg_img_gate_wg;

////////////////////////////////////////////////////////////////////////
//  dangle not connected signals                                      //
////////////////////////////////////////////////////////////////////////
///////////////////// dangles from NV_NVDLA_CDMA_regfile /////////////////////

endmodule // NV_NVDLA_cdma


