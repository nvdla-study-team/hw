// -----------------------------------------------------------------------------
// tb_top : NV_NVDLA_cdp UT 顶层（手写；端口清单逐条核对自
//          outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_cdp.v:9-49，39 端口全接）
//   - 单时钟 nvdla_core_clk（默认 7ns，+core_period_ns= 覆盖）；复位低 ~100ns
//   - CSB：单 csb master 面 + 2 目标译码（块号 addr[15:10]：CDP_RDMA=0xe /
//     CDP=0xf 分发 req_pvld，prdy 按块选择回送——两路 RTL 实为常 1
//     （NV_NVDLA_CDP_reg.v:833 / CDP_RDMA_reg.v:569），选择器保持结构正确性；
//     2 路 resp OR-mux + onehot0 检查，resp_pd[33]=type 拆读/写完成，
//     打包/拆分见 docs/spec/common/csb-link.md 6.1/6.2）
//   - DMA：cdp 是 1 读 + 1 写 + rd pop 的完整 dma 客户端；MCIF 宿一路挂
//     dma_slave_agent（dma_if#(79,514,515) 读+写+pop 全接）
//   - CVIF 宿 tie-off（输入 0 / ready 0）+ 哨兵：复位释放后任何 cdp2cvif 请求
//     直接打 "ERROR :" 行（make check 第 3 条抓）。注意 ram_type 复位值=0（CV），
//     数据通路测试必须显式编程 src/dst_ram_type=1 选 MC
//   - 中断 cdp2glb_done_intr_pd[1:0] 按位各挂一个 intr_agent
//   - tie-off：pwrbus_ram_pd=0、clk_ovr=0、tmc2slcg_disable_clock_gating=1（关门控）
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import cdp_ut_pkg::*;

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

  // ---------------- 互连 wire（名字照 DUT 端口） ----------------
  // CSB 双 slave
  wire          csb2cdp_req_pvld;
  wire          csb2cdp_req_prdy;
  wire [62:0]   csb2cdp_req_pd;
  wire          cdp2csb_resp_valid;
  wire [33:0]   cdp2csb_resp_pd;
  wire          csb2cdp_rdma_req_pvld;
  wire          csb2cdp_rdma_req_prdy;
  wire [62:0]   csb2cdp_rdma_req_pd;
  wire          cdp_rdma2csb_resp_valid;
  wire [33:0]   cdp_rdma2csb_resp_pd;

  // MCIF 宿：读 + 写 + credit pop
  wire          cdp2mcif_rd_req_valid, cdp2mcif_rd_req_ready;
  wire [78:0]   cdp2mcif_rd_req_pd;
  wire          mcif2cdp_rd_rsp_valid, mcif2cdp_rd_rsp_ready;
  wire [513:0]  mcif2cdp_rd_rsp_pd;
  wire          cdp2mcif_rd_cdt_lat_fifo_pop;
  wire          cdp2mcif_wr_req_valid, cdp2mcif_wr_req_ready;
  wire [514:0]  cdp2mcif_wr_req_pd;
  wire          mcif2cdp_wr_rsp_complete;

  // CVIF 宿：本 UT 不用，输出观测 + 输入 tie-off
  wire          cdp2cvif_rd_req_valid;
  wire [78:0]   cdp2cvif_rd_req_pd;
  wire          cdp2cvif_rd_cdt_lat_fifo_pop;
  wire          cdp2cvif_wr_req_valid;
  wire [514:0]  cdp2cvif_wr_req_pd;

  // 中断
  wire [1:0]    cdp2glb_done_intr_pd;

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  dma_if #(79, 514, 515) u_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单 master 面 -> 2 目标译码 ----------------
  // 块号 blk = byte_addr[17:12] = word_addr[15:10]（同 ut_types.svh csb_target_of）
  // CDP_RDMA=0xe(0xe000) CDP=0xf(0xf000)
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  wire [5:0]  csb_blk    = u_csb_if.addr[15:10];
  wire [62:0] csb_req_pd = {7'h0, u_csb_if.nposted, u_csb_if.write,
                            u_csb_if.wdat, 6'h0, u_csb_if.addr};

  assign csb2cdp_rdma_req_pvld = u_csb_if.valid && (csb_blk == 6'd14);
  assign csb2cdp_req_pvld      = u_csb_if.valid && (csb_blk == 6'd15);
  assign csb2cdp_rdma_req_pd   = csb_req_pd;
  assign csb2cdp_req_pd        = csb_req_pd;

  // prdy 按目标选择回送（两路 RTL 实为常 1；选择器保持结构正确性）
  assign u_csb_if.ready = (csb_blk == 6'd14) ? csb2cdp_rdma_req_prdy :
                          (csb_blk == 6'd15) ? csb2cdp_req_prdy      : 1'b1;

  // 2 路 resp OR-mux：driver 单笔阻塞（等响应才发下一笔）保证同刻至多 1 路 valid，
  // onehot0 检查兜底；resp_pd[33]=type：0=读数据 1=写完成（csb-link.md 6.2）
  wire [1:0] csb_resp_vld_vec = {cdp2csb_resp_valid, cdp_rdma2csb_resp_valid};
  wire [33:0] csb_resp_pd_mux =
      ({34{cdp_rdma2csb_resp_valid}} & cdp_rdma2csb_resp_pd) |
      ({34{cdp2csb_resp_valid}}      & cdp2csb_resp_pd);
  wire csb_resp_any = |csb_resp_vld_vec;

  assign u_csb_if.rvalid      = csb_resp_any & ~csb_resp_pd_mux[33];
  assign u_csb_if.rdata       = csb_resp_pd_mux[31:0];
  assign u_csb_if.wr_complete = csb_resp_any &  csb_resp_pd_mux[33];

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 && !$onehot0(csb_resp_vld_vec))
      `uvm_error("tb_top",
                 $sformatf("CSB resp collision: {cdp,cdp_rdma}=%b",
                           csb_resp_vld_vec))

  // ---------------- MCIF 宿 <-> dma_if（读 + 写 + pop 全接） ----------------
  assign u_mc_if.rd_req_pvld         = cdp2mcif_rd_req_valid;
  assign u_mc_if.rd_req_pd           = cdp2mcif_rd_req_pd;
  assign cdp2mcif_rd_req_ready       = u_mc_if.rd_req_prdy;
  assign mcif2cdp_rd_rsp_valid       = u_mc_if.rd_rsp_pvld;
  assign mcif2cdp_rd_rsp_pd          = u_mc_if.rd_rsp_pd;
  assign u_mc_if.rd_rsp_prdy         = mcif2cdp_rd_rsp_ready;
  assign u_mc_if.wr_req_pvld         = cdp2mcif_wr_req_valid;
  assign u_mc_if.wr_req_pd           = cdp2mcif_wr_req_pd;
  assign cdp2mcif_wr_req_ready       = u_mc_if.wr_req_prdy;
  assign mcif2cdp_wr_rsp_complete    = u_mc_if.wr_rsp_complete;
  assign u_mc_if.rd_cdt_lat_fifo_pop = cdp2mcif_rd_cdt_lat_fifo_pop;

  // ---------------- CVIF 宿 tie-off + 哨兵 ----------------
  // 本 UT 只走 MC 路（数据通路测试须显式编程 src/dst_ram_type=1，复位值 0=CV）；
  // CVIF 输入全 0、ready 0，复位释放后出现任何 CVIF 请求即打 ERROR 行
  wire         cvif2cdp_rd_rsp_valid    = 1'b0;
  wire [513:0] cvif2cdp_rd_rsp_pd       = '0;
  wire         cvif2cdp_wr_rsp_complete = 1'b0;
  wire         cdp2cvif_rd_req_ready    = 1'b0;
  wire         cdp2cvif_wr_req_ready    = 1'b0;

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 &&
        (cdp2cvif_rd_req_valid === 1'b1 || cdp2cvif_wr_req_valid === 1'b1))
      $display("ERROR : unexpected CVIF request (rd=%b wr=%b) — ram_type should select MC",
               cdp2cvif_rd_req_valid, cdp2cvif_wr_req_valid);

  // ---------------- 中断按位挂接 ----------------
  assign u_intr0_if.intr = cdp2glb_done_intr_pd[0];
  assign u_intr1_if.intr = cdp2glb_done_intr_pd[1];

  // ---------------- DUT（39 端口，序照 NV_NVDLA_cdp.v:9-49） ----------------
  NV_NVDLA_cdp u_NV_NVDLA_cdp (
     .dla_clk_ovr_on_sync            (1'b0)
    ,.global_clk_ovr_on_sync         (1'b0)
    ,.tmc2slcg_disable_clock_gating  (1'b1)
    ,.nvdla_core_clk                 (nvdla_core_clk)
    ,.nvdla_core_rstn                (nvdla_core_rstn)
    ,.cdp2csb_resp_valid             (cdp2csb_resp_valid)
    ,.cdp2csb_resp_pd                (cdp2csb_resp_pd[33:0])
    ,.cdp2cvif_rd_cdt_lat_fifo_pop   (cdp2cvif_rd_cdt_lat_fifo_pop)
    ,.cdp2cvif_rd_req_valid          (cdp2cvif_rd_req_valid)
    ,.cdp2cvif_rd_req_ready          (cdp2cvif_rd_req_ready)
    ,.cdp2cvif_rd_req_pd             (cdp2cvif_rd_req_pd[78:0])
    ,.cdp2cvif_wr_req_valid          (cdp2cvif_wr_req_valid)
    ,.cdp2cvif_wr_req_ready          (cdp2cvif_wr_req_ready)
    ,.cdp2cvif_wr_req_pd             (cdp2cvif_wr_req_pd[514:0])
    ,.cdp2glb_done_intr_pd           (cdp2glb_done_intr_pd[1:0])
    ,.cdp2mcif_rd_cdt_lat_fifo_pop   (cdp2mcif_rd_cdt_lat_fifo_pop)
    ,.cdp2mcif_rd_req_valid          (cdp2mcif_rd_req_valid)
    ,.cdp2mcif_rd_req_ready          (cdp2mcif_rd_req_ready)
    ,.cdp2mcif_rd_req_pd             (cdp2mcif_rd_req_pd[78:0])
    ,.cdp2mcif_wr_req_valid          (cdp2mcif_wr_req_valid)
    ,.cdp2mcif_wr_req_ready          (cdp2mcif_wr_req_ready)
    ,.cdp2mcif_wr_req_pd             (cdp2mcif_wr_req_pd[514:0])
    ,.cdp_rdma2csb_resp_valid        (cdp_rdma2csb_resp_valid)
    ,.cdp_rdma2csb_resp_pd           (cdp_rdma2csb_resp_pd[33:0])
    ,.csb2cdp_rdma_req_pvld          (csb2cdp_rdma_req_pvld)
    ,.csb2cdp_rdma_req_prdy          (csb2cdp_rdma_req_prdy)
    ,.csb2cdp_rdma_req_pd            (csb2cdp_rdma_req_pd[62:0])
    ,.csb2cdp_req_pvld               (csb2cdp_req_pvld)
    ,.csb2cdp_req_prdy               (csb2cdp_req_prdy)
    ,.csb2cdp_req_pd                 (csb2cdp_req_pd[62:0])
    ,.cvif2cdp_rd_rsp_valid          (cvif2cdp_rd_rsp_valid)
    ,.cvif2cdp_rd_rsp_ready          (cvif2cdp_rd_rsp_ready)
    ,.cvif2cdp_rd_rsp_pd             (cvif2cdp_rd_rsp_pd[513:0])
    ,.cvif2cdp_wr_rsp_complete       (cvif2cdp_wr_rsp_complete)
    ,.mcif2cdp_rd_rsp_valid          (mcif2cdp_rd_rsp_valid)
    ,.mcif2cdp_rd_rsp_ready          (mcif2cdp_rd_rsp_ready)
    ,.mcif2cdp_rd_rsp_pd             (mcif2cdp_rd_rsp_pd[513:0])
    ,.mcif2cdp_wr_rsp_complete       (mcif2cdp_wr_rsp_complete)
    ,.pwrbus_ram_pd                  (32'b0)
  );

  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.mc_agt*", "dma_vif", u_mc_if);

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
