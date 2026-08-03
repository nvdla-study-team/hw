// -----------------------------------------------------------------------------
// tb_top : NV_NVDLA_pdp UT 顶层（手写；端口清单逐条核对自
//          outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_pdp.v:53-97，共 45 个端口）
//   - 单时钟 nvdla_core_clk（默认 7ns，+core_period_ns= 覆盖）；复位低 ~100ns
//   - CSB：单 csb master 面 + 2 目标译码（blk=addr[15:10]：PDP_RDMA=0xc 走
//     csb2pdp_rdma_*、PDP=0xd 走 csb2pdp_*；prdy 按 blk 选择回送，两路 resp
//     OR-mux + $onehot0 检查——driver 单笔阻塞保证无冲突；收窄自 ccc tb 的
//     4 目标形态）
//   - DMA：pdp2mcif 读+写+pop 全接 1 个 dma_if#(79,514,515)（挂 dma_slave_agent，
//     env.mc_agt）；CVIF 一组 tie-off + 哨兵（出请求即打 "ERROR :" 行，
//     make check 抓 ^ERROR :）
//   - 直连入口 sdp2pdp 挂 sdp2pdp_if（源角色：if.valid/pd 驱 DUT 输入、DUT ready
//     回 if；env.sdp_src 例化 sdp2pdp_source_stub，T0 冒烟不发数即 valid=0）
//   - 中断 pdp2glb_done_intr_pd[1:0] 逐位挂 intr_if x2
//   - tie-off：pwrbus_ram_pd=0、dla/global_clk_ovr_on_sync=0、
//     tmc2slcg_disable_clock_gating=1（关门控）
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import pdp_ut_pkg::*;

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

  // ---------------- 互连 wire（名字同 DUT 端口） ----------------
  // CSB x2
  wire          csb2pdp_rdma_req_pvld;
  wire          csb2pdp_rdma_req_prdy;
  wire [62:0]   csb2pdp_rdma_req_pd;
  wire          pdp_rdma2csb_resp_valid;
  wire [33:0]   pdp_rdma2csb_resp_pd;
  wire          csb2pdp_req_pvld;
  wire          csb2pdp_req_prdy;
  wire [62:0]   csb2pdp_req_pd;
  wire          pdp2csb_resp_valid;
  wire [33:0]   pdp2csb_resp_pd;
  // MCIF 读 + 写 + credit pop
  wire          pdp2mcif_rd_req_valid, pdp2mcif_rd_req_ready;
  wire [78:0]   pdp2mcif_rd_req_pd;
  wire          mcif2pdp_rd_rsp_valid, mcif2pdp_rd_rsp_ready;
  wire [513:0]  mcif2pdp_rd_rsp_pd;
  wire          pdp2mcif_rd_cdt_lat_fifo_pop;
  wire          pdp2mcif_wr_req_valid, pdp2mcif_wr_req_ready;
  wire [514:0]  pdp2mcif_wr_req_pd;
  wire          mcif2pdp_wr_rsp_complete;
  // CVIF（tie-off + 观测哨兵）
  wire          pdp2cvif_rd_req_valid;
  wire [78:0]   pdp2cvif_rd_req_pd;
  wire          pdp2cvif_rd_cdt_lat_fifo_pop;
  wire          pdp2cvif_wr_req_valid;
  wire [514:0]  pdp2cvif_wr_req_pd;
  // 直连入口 + 中断
  wire          sdp2pdp_valid, sdp2pdp_ready;
  wire [255:0]  sdp2pdp_pd;
  wire [1:0]    pdp2glb_done_intr_pd;

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  dma_if #(79, 514, 515) u_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  sdp2pdp_if u_sdp2pdp_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单 master 面 -> 2 目标译码 ----------------
  // 块号 blk = byte_addr[17:12] = word_addr[15:10]（同 ut_types.svh csb_target_of）
  // PDP_RDMA=12(0xc000) PDP=13(0xd000)
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  wire [5:0]  csb_blk    = u_csb_if.addr[15:10];
  wire [62:0] csb_req_pd = {7'h0, u_csb_if.nposted, u_csb_if.write,
                            u_csb_if.wdat, 6'h0, u_csb_if.addr};

  assign csb2pdp_rdma_req_pvld = u_csb_if.valid && (csb_blk == 6'd12);
  assign csb2pdp_req_pvld      = u_csb_if.valid && (csb_blk == 6'd13);
  assign csb2pdp_rdma_req_pd   = csb_req_pd;
  assign csb2pdp_req_pd        = csb_req_pd;

  // prdy 按目标选择回送（两路 RTL 实为常 1：NV_NVDLA_PDP_RDMA_reg.v:625 /
  // NV_NVDLA_PDP_reg.v:839；选择器保持结构正确性）
  assign u_csb_if.ready = (csb_blk == 6'd12) ? csb2pdp_rdma_req_prdy :
                          (csb_blk == 6'd13) ? csb2pdp_req_prdy      : 1'b1;

  // 2 路 resp OR-mux：driver 单笔阻塞（等响应才发下一笔）保证同刻至多 1 路 valid，
  // onehot0 检查兜底；resp_pd[33]=type：0=读数据 1=写完成（csb-link.md 6.2）
  wire [1:0] csb_resp_vld_vec = {pdp2csb_resp_valid, pdp_rdma2csb_resp_valid};
  wire [33:0] csb_resp_pd_mux =
      ({34{pdp_rdma2csb_resp_valid}} & pdp_rdma2csb_resp_pd) |
      ({34{pdp2csb_resp_valid}}      & pdp2csb_resp_pd);
  wire csb_resp_any = |csb_resp_vld_vec;

  assign u_csb_if.rvalid      = csb_resp_any & ~csb_resp_pd_mux[33];
  assign u_csb_if.rdata       = csb_resp_pd_mux[31:0];
  assign u_csb_if.wr_complete = csb_resp_any &  csb_resp_pd_mux[33];

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 && !$onehot0(csb_resp_vld_vec))
      `uvm_error("tb_top",
                 $sformatf("CSB resp collision: {pdp,pdp_rdma}=%b",
                           csb_resp_vld_vec))

  // ---------------- MCIF：读+写+pop 全接 dma_if ----------------
  assign u_mc_if.rd_req_pvld     = pdp2mcif_rd_req_valid;
  assign u_mc_if.rd_req_pd       = pdp2mcif_rd_req_pd;
  assign pdp2mcif_rd_req_ready   = u_mc_if.rd_req_prdy;
  assign mcif2pdp_rd_rsp_valid   = u_mc_if.rd_rsp_pvld;
  assign mcif2pdp_rd_rsp_pd      = u_mc_if.rd_rsp_pd;
  assign u_mc_if.rd_rsp_prdy     = mcif2pdp_rd_rsp_ready;
  assign u_mc_if.wr_req_pvld     = pdp2mcif_wr_req_valid;
  assign u_mc_if.wr_req_pd       = pdp2mcif_wr_req_pd;
  assign pdp2mcif_wr_req_ready   = u_mc_if.wr_req_prdy;
  assign mcif2pdp_wr_rsp_complete = u_mc_if.wr_rsp_complete;
  assign u_mc_if.rd_cdt_lat_fifo_pop = pdp2mcif_rd_cdt_lat_fifo_pop;

  // ---------------- CVIF：一组 tie-off + 请求哨兵 ----------------
  // 冒烟/后续 MC 通路测试均不该走 CVIF（ram_type 复位值=0 即 CV，数据通路测试
  // 必须显式编程 src/dst_ram_type=1 选 MC）；出请求即打 ERROR 行由 make check 抓
  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn && (pdp2cvif_rd_req_valid || pdp2cvif_wr_req_valid))
      $display("ERROR : unexpected CVIF request (rd=%b wr=%b) at %t",
               pdp2cvif_rd_req_valid, pdp2cvif_wr_req_valid, $time);

  // ---------------- sdp2pdp 直连入口（源侧 stub 驱动） ----------------
  assign sdp2pdp_valid       = u_sdp2pdp_if.valid;
  assign sdp2pdp_pd          = u_sdp2pdp_if.pd;
  assign u_sdp2pdp_if.ready  = sdp2pdp_ready;

  // ---------------- 中断按位挂接 ----------------
  assign u_intr0_if.intr = pdp2glb_done_intr_pd[0];
  assign u_intr1_if.intr = pdp2glb_done_intr_pd[1];

  // ---------------- DUT：pdp（端口 1:1 同名连线，CVIF 输入 tie 0） ----------
  NV_NVDLA_pdp u_NV_NVDLA_pdp (
     .dla_clk_ovr_on_sync             (1'b0)
    ,.global_clk_ovr_on_sync          (1'b0)
    ,.tmc2slcg_disable_clock_gating   (1'b1)
    ,.nvdla_core_clk                  (nvdla_core_clk)
    ,.nvdla_core_rstn                 (nvdla_core_rstn)
    ,.csb2pdp_rdma_req_pvld           (csb2pdp_rdma_req_pvld)
    ,.csb2pdp_rdma_req_prdy           (csb2pdp_rdma_req_prdy)
    ,.csb2pdp_rdma_req_pd             (csb2pdp_rdma_req_pd[62:0])
    ,.csb2pdp_req_pvld                (csb2pdp_req_pvld)
    ,.csb2pdp_req_prdy                (csb2pdp_req_prdy)
    ,.csb2pdp_req_pd                  (csb2pdp_req_pd[62:0])
    ,.cvif2pdp_rd_rsp_valid           (1'b0)
    ,.cvif2pdp_rd_rsp_ready           ()
    ,.cvif2pdp_rd_rsp_pd              (514'b0)
    ,.cvif2pdp_wr_rsp_complete        (1'b0)
    ,.mcif2pdp_rd_rsp_valid           (mcif2pdp_rd_rsp_valid)
    ,.mcif2pdp_rd_rsp_ready           (mcif2pdp_rd_rsp_ready)
    ,.mcif2pdp_rd_rsp_pd              (mcif2pdp_rd_rsp_pd[513:0])
    ,.mcif2pdp_wr_rsp_complete        (mcif2pdp_wr_rsp_complete)
    ,.pdp2csb_resp_valid              (pdp2csb_resp_valid)
    ,.pdp2csb_resp_pd                 (pdp2csb_resp_pd[33:0])
    ,.pdp2cvif_rd_cdt_lat_fifo_pop    (pdp2cvif_rd_cdt_lat_fifo_pop)
    ,.pdp2cvif_rd_req_valid           (pdp2cvif_rd_req_valid)
    ,.pdp2cvif_rd_req_ready           (1'b0)
    ,.pdp2cvif_rd_req_pd              (pdp2cvif_rd_req_pd[78:0])
    ,.pdp2cvif_wr_req_valid           (pdp2cvif_wr_req_valid)
    ,.pdp2cvif_wr_req_ready           (1'b0)
    ,.pdp2cvif_wr_req_pd              (pdp2cvif_wr_req_pd[514:0])
    ,.pdp2glb_done_intr_pd            (pdp2glb_done_intr_pd[1:0])
    ,.pdp2mcif_rd_cdt_lat_fifo_pop    (pdp2mcif_rd_cdt_lat_fifo_pop)
    ,.pdp2mcif_rd_req_valid           (pdp2mcif_rd_req_valid)
    ,.pdp2mcif_rd_req_ready           (pdp2mcif_rd_req_ready)
    ,.pdp2mcif_rd_req_pd              (pdp2mcif_rd_req_pd[78:0])
    ,.pdp2mcif_wr_req_valid           (pdp2mcif_wr_req_valid)
    ,.pdp2mcif_wr_req_ready           (pdp2mcif_wr_req_ready)
    ,.pdp2mcif_wr_req_pd              (pdp2mcif_wr_req_pd[514:0])
    ,.pdp_rdma2csb_resp_valid         (pdp_rdma2csb_resp_valid)
    ,.pdp_rdma2csb_resp_pd            (pdp_rdma2csb_resp_pd[33:0])
    ,.pwrbus_ram_pd                   (32'b0)
    ,.sdp2pdp_valid                   (sdp2pdp_valid)
    ,.sdp2pdp_ready                   (sdp2pdp_ready)
    ,.sdp2pdp_pd                      (sdp2pdp_pd[255:0])
  );

  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.mc_agt*", "dma_vif", u_mc_if);

    uvm_config_db#(virtual sdp2pdp_if)::set(
      null, "uvm_test_top.env.sdp_src*", "sdp2pdp_vif", u_sdp2pdp_if);

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
