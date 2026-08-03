// -----------------------------------------------------------------------------
// tb_top : NV_NVDLA_sdp UT 顶层（手写；端口清单逐条核对自
//          outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_sdp.v:101-187）
//   - 单时钟 nvdla_core_clk（默认 7ns，+core_period_ns= 覆盖）；复位低 ~100ns
//   - CSB：单 csb master 面 + 2 目标译码（blk=addr[15:10]：SDP_RDMA=0xa、SDP=0xb
//     分发 req_pvld，prdy 按 blk 选择回送，2 路 resp OR-mux + onehot0 检查——
//     driver 单笔阻塞保证无冲突；形态收窄自 csc_cmac_cacc/tb/tb_top.sv 四目标版）
//   - DMA：4 个 dma_if#(79,514,515) 全挂 MCIF——u_mc_if（main：mrdma 读 + wdma 写
//     + pop 全接）、u_b/n/e_mc_if（只读 + 各自 pop；DUT 无写输入侧，接口内写通道
//     绑 0，responder 收不到写）
//   - CVIF 8 组端口 tie-off：DUT 输入侧 rsp valid/pd/complete 与 req ready 全 0；
//     哨兵 always 块监视 5 路 *2cvif req valid，出复位后拉高即打 "ERROR :" 行
//     （make check 第 3 条判据直接抓）
//   - 直连：cacc2sdp 挂 sdp_if（tb 驱 valid/pd 进 DUT、DUT ready 回 if；env 的
//     sdp_source_stub 冒烟不发数即 valid=0）；sdp2pdp 挂 sdp2pdp_if（sink 角色，
//     sdp2pdp_sink_stub 默认恒 ready）
//   - 中断 sdp2glb_done_intr_pd[1:0] 按位挂 2 个 intr_if
//   - tie-off：pwrbus_ram_pd=0、dla/global_clk_ovr_on_sync=0、
//     tmc2slcg_disable_clock_gating=1（关门控）
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import sdp_ut_pkg::*;

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

  // ---------------- 互连 wire（照 NV_NVDLA_sdp.v 端口表） ----------------
  // cacc2sdp 直连入口
  wire          cacc2sdp_valid;
  wire          cacc2sdp_ready;
  wire [513:0]  cacc2sdp_pd;
  // CSB ×2
  wire          csb2sdp_rdma_req_pvld;
  wire          csb2sdp_rdma_req_prdy;
  wire [62:0]   csb2sdp_rdma_req_pd;
  wire          sdp_rdma2csb_resp_valid;
  wire [33:0]   sdp_rdma2csb_resp_pd;
  wire          csb2sdp_req_pvld;
  wire          csb2sdp_req_prdy;
  wire [62:0]   csb2sdp_req_pd;
  wire          sdp2csb_resp_valid;
  wire [33:0]   sdp2csb_resp_pd;
  // MCIF main（mrdma 读 + wdma 写）
  wire          sdp2mcif_rd_req_valid, sdp2mcif_rd_req_ready;
  wire [78:0]   sdp2mcif_rd_req_pd;
  wire          mcif2sdp_rd_rsp_valid, mcif2sdp_rd_rsp_ready;
  wire [513:0]  mcif2sdp_rd_rsp_pd;
  wire          sdp2mcif_rd_cdt_lat_fifo_pop;
  wire          sdp2mcif_wr_req_valid, sdp2mcif_wr_req_ready;
  wire [514:0]  sdp2mcif_wr_req_pd;
  wire          mcif2sdp_wr_rsp_complete;
  // MCIF b / n / e（只读）
  wire          sdp_b2mcif_rd_req_valid, sdp_b2mcif_rd_req_ready;
  wire [78:0]   sdp_b2mcif_rd_req_pd;
  wire          mcif2sdp_b_rd_rsp_valid, mcif2sdp_b_rd_rsp_ready;
  wire [513:0]  mcif2sdp_b_rd_rsp_pd;
  wire          sdp_b2mcif_rd_cdt_lat_fifo_pop;
  wire          sdp_n2mcif_rd_req_valid, sdp_n2mcif_rd_req_ready;
  wire [78:0]   sdp_n2mcif_rd_req_pd;
  wire          mcif2sdp_n_rd_rsp_valid, mcif2sdp_n_rd_rsp_ready;
  wire [513:0]  mcif2sdp_n_rd_rsp_pd;
  wire          sdp_n2mcif_rd_cdt_lat_fifo_pop;
  wire          sdp_e2mcif_rd_req_valid, sdp_e2mcif_rd_req_ready;
  wire [78:0]   sdp_e2mcif_rd_req_pd;
  wire          mcif2sdp_e_rd_rsp_valid, mcif2sdp_e_rd_rsp_ready;
  wire [513:0]  mcif2sdp_e_rd_rsp_pd;
  wire          sdp_e2mcif_rd_cdt_lat_fifo_pop;
  // CVIF 8 组（tie-off；DUT 输出侧留 wire 供哨兵观测）
  wire          sdp2cvif_rd_req_valid;
  wire [78:0]   sdp2cvif_rd_req_pd;
  wire          cvif2sdp_rd_rsp_ready;   // DUT 输出，悬空观测
  wire          sdp2cvif_rd_cdt_lat_fifo_pop;
  wire          sdp2cvif_wr_req_valid;
  wire [514:0]  sdp2cvif_wr_req_pd;
  wire          sdp_b2cvif_rd_req_valid;
  wire [78:0]   sdp_b2cvif_rd_req_pd;
  wire          cvif2sdp_b_rd_rsp_ready;
  wire          sdp_b2cvif_rd_cdt_lat_fifo_pop;
  wire          sdp_n2cvif_rd_req_valid;
  wire [78:0]   sdp_n2cvif_rd_req_pd;
  wire          cvif2sdp_n_rd_rsp_ready;
  wire          sdp_n2cvif_rd_cdt_lat_fifo_pop;
  wire          sdp_e2cvif_rd_req_valid;
  wire [78:0]   sdp_e2cvif_rd_req_pd;
  wire          cvif2sdp_e_rd_rsp_ready;
  wire          sdp_e2cvif_rd_cdt_lat_fifo_pop;
  // 出口 / 中断
  wire          sdp2pdp_valid;
  wire          sdp2pdp_ready;
  wire [255:0]  sdp2pdp_pd;
  wire [1:0]    sdp2glb_done_intr_pd;

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  dma_if #(79, 514, 515) u_mc_if   (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_b_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_n_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_e_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  sdp_if     u_cacc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  sdp2pdp_if u_pdp_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单 master 面 -> 2 目标译码 ----------------
  // 块号 blk = byte_addr[17:12] = word_addr[15:10]（同 ut_types.svh csb_target_of）
  // SDP_RDMA=10(0xa000) SDP=11(0xb000)
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  wire [5:0]  csb_blk    = u_csb_if.addr[15:10];
  wire [62:0] csb_req_pd = {7'h0, u_csb_if.nposted, u_csb_if.write,
                            u_csb_if.wdat, 6'h0, u_csb_if.addr};

  assign csb2sdp_rdma_req_pvld = u_csb_if.valid && (csb_blk == 6'd10);
  assign csb2sdp_req_pvld      = u_csb_if.valid && (csb_blk == 6'd11);
  assign csb2sdp_rdma_req_pd   = csb_req_pd;
  assign csb2sdp_req_pd        = csb_req_pd;

  // prdy 按目标选择回送（两路 RTL 实为常 1；选择器保持结构正确性）
  assign u_csb_if.ready = (csb_blk == 6'd10) ? csb2sdp_rdma_req_prdy :
                          (csb_blk == 6'd11) ? csb2sdp_req_prdy      : 1'b1;

  // 2 路 resp OR-mux：driver 单笔阻塞（等响应才发下一笔）保证同刻至多 1 路 valid，
  // onehot0 检查兜底；resp_pd[33]=type：0=读数据 1=写完成（csb-link.md 6.2）
  wire [1:0] csb_resp_vld_vec = {sdp2csb_resp_valid, sdp_rdma2csb_resp_valid};
  wire [33:0] csb_resp_pd_mux =
      ({34{sdp_rdma2csb_resp_valid}} & sdp_rdma2csb_resp_pd) |
      ({34{sdp2csb_resp_valid}}      & sdp2csb_resp_pd);
  wire csb_resp_any = |csb_resp_vld_vec;

  assign u_csb_if.rvalid      = csb_resp_any & ~csb_resp_pd_mux[33];
  assign u_csb_if.rdata       = csb_resp_pd_mux[31:0];
  assign u_csb_if.wr_complete = csb_resp_any &  csb_resp_pd_mux[33];

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 && !$onehot0(csb_resp_vld_vec))
      `uvm_error("tb_top",
                 $sformatf("CSB resp collision: {sdp,sdp_rdma}=%b", csb_resp_vld_vec))

  // ---------------- 4 路 MCIF DMA 客户端 <-> dma_if ----------------
  // main：mrdma 读 + wdma 写共用一个客户端（sdp2mcif 前缀同时带读+写通道）
  assign u_mc_if.rd_req_pvld      = sdp2mcif_rd_req_valid;
  assign u_mc_if.rd_req_pd        = sdp2mcif_rd_req_pd;
  assign sdp2mcif_rd_req_ready    = u_mc_if.rd_req_prdy;
  assign mcif2sdp_rd_rsp_valid    = u_mc_if.rd_rsp_pvld;
  assign mcif2sdp_rd_rsp_pd       = u_mc_if.rd_rsp_pd;
  assign u_mc_if.rd_rsp_prdy      = mcif2sdp_rd_rsp_ready;
  assign u_mc_if.wr_req_pvld      = sdp2mcif_wr_req_valid;
  assign u_mc_if.wr_req_pd        = sdp2mcif_wr_req_pd;
  assign sdp2mcif_wr_req_ready    = u_mc_if.wr_req_prdy;
  assign mcif2sdp_wr_rsp_complete = u_mc_if.wr_rsp_complete;
  assign u_mc_if.rd_cdt_lat_fifo_pop = sdp2mcif_rd_cdt_lat_fifo_pop;

  // b / n / e：只读客户端（写通道在接口内绑 0，responder 收不到写）
  assign u_b_mc_if.rd_req_pvld   = sdp_b2mcif_rd_req_valid;
  assign u_b_mc_if.rd_req_pd     = sdp_b2mcif_rd_req_pd;
  assign sdp_b2mcif_rd_req_ready = u_b_mc_if.rd_req_prdy;
  assign mcif2sdp_b_rd_rsp_valid = u_b_mc_if.rd_rsp_pvld;
  assign mcif2sdp_b_rd_rsp_pd    = u_b_mc_if.rd_rsp_pd;
  assign u_b_mc_if.rd_rsp_prdy   = mcif2sdp_b_rd_rsp_ready;
  assign u_b_mc_if.wr_req_pvld   = 1'b0;
  assign u_b_mc_if.wr_req_pd     = '0;
  assign u_b_mc_if.rd_cdt_lat_fifo_pop = sdp_b2mcif_rd_cdt_lat_fifo_pop;

  assign u_n_mc_if.rd_req_pvld   = sdp_n2mcif_rd_req_valid;
  assign u_n_mc_if.rd_req_pd     = sdp_n2mcif_rd_req_pd;
  assign sdp_n2mcif_rd_req_ready = u_n_mc_if.rd_req_prdy;
  assign mcif2sdp_n_rd_rsp_valid = u_n_mc_if.rd_rsp_pvld;
  assign mcif2sdp_n_rd_rsp_pd    = u_n_mc_if.rd_rsp_pd;
  assign u_n_mc_if.rd_rsp_prdy   = mcif2sdp_n_rd_rsp_ready;
  assign u_n_mc_if.wr_req_pvld   = 1'b0;
  assign u_n_mc_if.wr_req_pd     = '0;
  assign u_n_mc_if.rd_cdt_lat_fifo_pop = sdp_n2mcif_rd_cdt_lat_fifo_pop;

  assign u_e_mc_if.rd_req_pvld   = sdp_e2mcif_rd_req_valid;
  assign u_e_mc_if.rd_req_pd     = sdp_e2mcif_rd_req_pd;
  assign sdp_e2mcif_rd_req_ready = u_e_mc_if.rd_req_prdy;
  assign mcif2sdp_e_rd_rsp_valid = u_e_mc_if.rd_rsp_pvld;
  assign mcif2sdp_e_rd_rsp_pd    = u_e_mc_if.rd_rsp_pd;
  assign u_e_mc_if.rd_rsp_prdy   = mcif2sdp_e_rd_rsp_ready;
  assign u_e_mc_if.wr_req_pvld   = 1'b0;
  assign u_e_mc_if.wr_req_pd     = '0;
  assign u_e_mc_if.rd_cdt_lat_fifo_pop = sdp_e2mcif_rd_cdt_lat_fifo_pop;

  // ---------------- CVIF tie-off + 哨兵 ----------------
  // 输入侧全 0：rsp 不给、req ready 不给（数据通路测试须显式编程
  // src/dst_ram_type=1 选 MC，复位值 0 选 CV 会撞死在这里——方案书 §4.6）
  wire cvif2sdp_rd_rsp_valid      = 1'b0;
  wire [513:0] cvif2sdp_rd_rsp_pd = '0;
  wire cvif2sdp_b_rd_rsp_valid      = 1'b0;
  wire [513:0] cvif2sdp_b_rd_rsp_pd = '0;
  wire cvif2sdp_n_rd_rsp_valid      = 1'b0;
  wire [513:0] cvif2sdp_n_rd_rsp_pd = '0;
  wire cvif2sdp_e_rd_rsp_valid      = 1'b0;
  wire [513:0] cvif2sdp_e_rd_rsp_pd = '0;
  wire cvif2sdp_wr_rsp_complete     = 1'b0;
  wire sdp2cvif_rd_req_ready   = 1'b0;
  wire sdp2cvif_wr_req_ready   = 1'b0;
  wire sdp_b2cvif_rd_req_ready = 1'b0;
  wire sdp_n2cvif_rd_req_ready = 1'b0;
  wire sdp_e2cvif_rd_req_ready = 1'b0;

  // 哨兵：出复位后任一 CVIF 请求 valid 拉高即打 "ERROR :"（make check 抓取）
  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 &&
        (sdp2cvif_rd_req_valid   === 1'b1 || sdp2cvif_wr_req_valid   === 1'b1 ||
         sdp_b2cvif_rd_req_valid === 1'b1 || sdp_n2cvif_rd_req_valid === 1'b1 ||
         sdp_e2cvif_rd_req_valid === 1'b1))
      $display("ERROR : unexpected CVIF request (rd=%b wr=%b b=%b n=%b e=%b) at %t",
               sdp2cvif_rd_req_valid, sdp2cvif_wr_req_valid,
               sdp_b2cvif_rd_req_valid, sdp_n2cvif_rd_req_valid,
               sdp_e2cvif_rd_req_valid, $time);

  // ---------------- cacc2sdp（tb 扮演 cacc 驱动侧） ----------------
  assign cacc2sdp_valid  = u_cacc_if.valid;
  assign cacc2sdp_pd     = u_cacc_if.pd;
  assign u_cacc_if.ready = cacc2sdp_ready;

  // ---------------- sdp2pdp（tb 扮演 pdp 接收侧） ----------------
  assign u_pdp_if.valid = sdp2pdp_valid;
  assign u_pdp_if.pd    = sdp2pdp_pd;
  assign sdp2pdp_ready  = u_pdp_if.ready;

  // ---------------- 中断按位挂接 ----------------
  assign u_intr0_if.intr = sdp2glb_done_intr_pd[0];
  assign u_intr1_if.intr = sdp2glb_done_intr_pd[1];

  // ---------------- DUT ----------------
  NV_NVDLA_sdp u_NV_NVDLA_sdp (
     .nvdla_core_clk                 (nvdla_core_clk)
    ,.nvdla_core_rstn                (nvdla_core_rstn)
    ,.cacc2sdp_valid                 (cacc2sdp_valid)
    ,.cacc2sdp_ready                 (cacc2sdp_ready)
    ,.cacc2sdp_pd                    (cacc2sdp_pd[513:0])
    ,.csb2sdp_rdma_req_pvld          (csb2sdp_rdma_req_pvld)
    ,.csb2sdp_rdma_req_prdy          (csb2sdp_rdma_req_prdy)
    ,.csb2sdp_rdma_req_pd            (csb2sdp_rdma_req_pd[62:0])
    ,.csb2sdp_req_pvld               (csb2sdp_req_pvld)
    ,.csb2sdp_req_prdy               (csb2sdp_req_prdy)
    ,.csb2sdp_req_pd                 (csb2sdp_req_pd[62:0])
    ,.cvif2sdp_b_rd_rsp_valid        (cvif2sdp_b_rd_rsp_valid)
    ,.cvif2sdp_b_rd_rsp_ready        (cvif2sdp_b_rd_rsp_ready)
    ,.cvif2sdp_b_rd_rsp_pd           (cvif2sdp_b_rd_rsp_pd[513:0])
    ,.cvif2sdp_e_rd_rsp_valid        (cvif2sdp_e_rd_rsp_valid)
    ,.cvif2sdp_e_rd_rsp_ready        (cvif2sdp_e_rd_rsp_ready)
    ,.cvif2sdp_e_rd_rsp_pd           (cvif2sdp_e_rd_rsp_pd[513:0])
    ,.cvif2sdp_n_rd_rsp_valid        (cvif2sdp_n_rd_rsp_valid)
    ,.cvif2sdp_n_rd_rsp_ready        (cvif2sdp_n_rd_rsp_ready)
    ,.cvif2sdp_n_rd_rsp_pd           (cvif2sdp_n_rd_rsp_pd[513:0])
    ,.cvif2sdp_rd_rsp_valid          (cvif2sdp_rd_rsp_valid)
    ,.cvif2sdp_rd_rsp_ready          (cvif2sdp_rd_rsp_ready)
    ,.cvif2sdp_rd_rsp_pd             (cvif2sdp_rd_rsp_pd[513:0])
    ,.cvif2sdp_wr_rsp_complete       (cvif2sdp_wr_rsp_complete)
    ,.mcif2sdp_b_rd_rsp_valid        (mcif2sdp_b_rd_rsp_valid)
    ,.mcif2sdp_b_rd_rsp_ready        (mcif2sdp_b_rd_rsp_ready)
    ,.mcif2sdp_b_rd_rsp_pd           (mcif2sdp_b_rd_rsp_pd[513:0])
    ,.mcif2sdp_e_rd_rsp_valid        (mcif2sdp_e_rd_rsp_valid)
    ,.mcif2sdp_e_rd_rsp_ready        (mcif2sdp_e_rd_rsp_ready)
    ,.mcif2sdp_e_rd_rsp_pd           (mcif2sdp_e_rd_rsp_pd[513:0])
    ,.mcif2sdp_n_rd_rsp_valid        (mcif2sdp_n_rd_rsp_valid)
    ,.mcif2sdp_n_rd_rsp_ready        (mcif2sdp_n_rd_rsp_ready)
    ,.mcif2sdp_n_rd_rsp_pd           (mcif2sdp_n_rd_rsp_pd[513:0])
    ,.mcif2sdp_rd_rsp_valid          (mcif2sdp_rd_rsp_valid)
    ,.mcif2sdp_rd_rsp_ready          (mcif2sdp_rd_rsp_ready)
    ,.mcif2sdp_rd_rsp_pd             (mcif2sdp_rd_rsp_pd[513:0])
    ,.mcif2sdp_wr_rsp_complete       (mcif2sdp_wr_rsp_complete)
    ,.pwrbus_ram_pd                  (32'b0)
    ,.sdp2csb_resp_valid             (sdp2csb_resp_valid)
    ,.sdp2csb_resp_pd                (sdp2csb_resp_pd[33:0])
    ,.sdp2cvif_rd_cdt_lat_fifo_pop   (sdp2cvif_rd_cdt_lat_fifo_pop)
    ,.sdp2cvif_rd_req_valid          (sdp2cvif_rd_req_valid)
    ,.sdp2cvif_rd_req_ready          (sdp2cvif_rd_req_ready)
    ,.sdp2cvif_rd_req_pd             (sdp2cvif_rd_req_pd[78:0])
    ,.sdp2cvif_wr_req_valid          (sdp2cvif_wr_req_valid)
    ,.sdp2cvif_wr_req_ready          (sdp2cvif_wr_req_ready)
    ,.sdp2cvif_wr_req_pd             (sdp2cvif_wr_req_pd[514:0])
    ,.sdp2glb_done_intr_pd           (sdp2glb_done_intr_pd[1:0])
    ,.sdp2mcif_rd_cdt_lat_fifo_pop   (sdp2mcif_rd_cdt_lat_fifo_pop)
    ,.sdp2mcif_rd_req_valid          (sdp2mcif_rd_req_valid)
    ,.sdp2mcif_rd_req_ready          (sdp2mcif_rd_req_ready)
    ,.sdp2mcif_rd_req_pd             (sdp2mcif_rd_req_pd[78:0])
    ,.sdp2mcif_wr_req_valid          (sdp2mcif_wr_req_valid)
    ,.sdp2mcif_wr_req_ready          (sdp2mcif_wr_req_ready)
    ,.sdp2mcif_wr_req_pd             (sdp2mcif_wr_req_pd[514:0])
    ,.sdp2pdp_valid                  (sdp2pdp_valid)
    ,.sdp2pdp_ready                  (sdp2pdp_ready)
    ,.sdp2pdp_pd                     (sdp2pdp_pd[255:0])
    ,.sdp_b2cvif_rd_cdt_lat_fifo_pop (sdp_b2cvif_rd_cdt_lat_fifo_pop)
    ,.sdp_b2cvif_rd_req_valid        (sdp_b2cvif_rd_req_valid)
    ,.sdp_b2cvif_rd_req_ready        (sdp_b2cvif_rd_req_ready)
    ,.sdp_b2cvif_rd_req_pd           (sdp_b2cvif_rd_req_pd[78:0])
    ,.sdp_b2mcif_rd_cdt_lat_fifo_pop (sdp_b2mcif_rd_cdt_lat_fifo_pop)
    ,.sdp_b2mcif_rd_req_valid        (sdp_b2mcif_rd_req_valid)
    ,.sdp_b2mcif_rd_req_ready        (sdp_b2mcif_rd_req_ready)
    ,.sdp_b2mcif_rd_req_pd           (sdp_b2mcif_rd_req_pd[78:0])
    ,.sdp_e2cvif_rd_cdt_lat_fifo_pop (sdp_e2cvif_rd_cdt_lat_fifo_pop)
    ,.sdp_e2cvif_rd_req_valid        (sdp_e2cvif_rd_req_valid)
    ,.sdp_e2cvif_rd_req_ready        (sdp_e2cvif_rd_req_ready)
    ,.sdp_e2cvif_rd_req_pd           (sdp_e2cvif_rd_req_pd[78:0])
    ,.sdp_e2mcif_rd_cdt_lat_fifo_pop (sdp_e2mcif_rd_cdt_lat_fifo_pop)
    ,.sdp_e2mcif_rd_req_valid        (sdp_e2mcif_rd_req_valid)
    ,.sdp_e2mcif_rd_req_ready        (sdp_e2mcif_rd_req_ready)
    ,.sdp_e2mcif_rd_req_pd           (sdp_e2mcif_rd_req_pd[78:0])
    ,.sdp_n2cvif_rd_cdt_lat_fifo_pop (sdp_n2cvif_rd_cdt_lat_fifo_pop)
    ,.sdp_n2cvif_rd_req_valid        (sdp_n2cvif_rd_req_valid)
    ,.sdp_n2cvif_rd_req_ready        (sdp_n2cvif_rd_req_ready)
    ,.sdp_n2cvif_rd_req_pd           (sdp_n2cvif_rd_req_pd[78:0])
    ,.sdp_n2mcif_rd_cdt_lat_fifo_pop (sdp_n2mcif_rd_cdt_lat_fifo_pop)
    ,.sdp_n2mcif_rd_req_valid        (sdp_n2mcif_rd_req_valid)
    ,.sdp_n2mcif_rd_req_ready        (sdp_n2mcif_rd_req_ready)
    ,.sdp_n2mcif_rd_req_pd           (sdp_n2mcif_rd_req_pd[78:0])
    ,.sdp_rdma2csb_resp_valid        (sdp_rdma2csb_resp_valid)
    ,.sdp_rdma2csb_resp_pd           (sdp_rdma2csb_resp_pd[33:0])
    ,.dla_clk_ovr_on_sync            (1'b0)
    ,.global_clk_ovr_on_sync         (1'b0)
    ,.tmc2slcg_disable_clock_gating  (1'b1)
  );

  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    // 同键 "dma_vif" 按作用域分发（样板：cdma_cbuf/tb/tb_top.sv:314-321）
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.mc_agt*", "dma_vif", u_mc_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.b_agt*", "dma_vif", u_b_mc_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.n_agt*", "dma_vif", u_n_mc_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.e_agt*", "dma_vif", u_e_mc_if);

    uvm_config_db#(virtual sdp_if)::set(
      null, "uvm_test_top.env.cacc_src*", "sdp_vif", u_cacc_if);
    uvm_config_db#(virtual sdp2pdp_if)::set(
      null, "uvm_test_top.env.pdp_sink*", "sdp2pdp_vif", u_pdp_if);

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
