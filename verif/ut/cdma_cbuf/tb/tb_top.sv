// -----------------------------------------------------------------------------
// tb_top : NV_NVDLA_cdma + NV_NVDLA_cbuf UT 顶层
//   - 单时钟 nvdla_core_clk（默认 7ns，+core_period_ns= 覆盖）；复位低 ~100ns
//   - cdma<->cbuf 互连照抄 vmod/nvdla/top/NV_NVDLA_partition_c.v（cdma2buf_* 直连，
//     同时引到 cbuf_wr_if 监测）
//   - CSB：csb master agent（falcon 单口协议）经 tb 组合逻辑适配直连 csb2cdma
//     req/resp（req_pd 63 位打包/resp_pd[33] type 拆分见 docs/spec/common/csb-link.md
//     6.1/6.2 节；csb2cdma_req_prdy 恒 1，NV_NVDLA_CDMA_regfile.v:1058）
//   - 4 路 DMA 读客户端挂 dma_slave_agent；cdma 是纯读客户端：无写通道、无
//     rd_cdt_lat_fifo_pop 输出，wr_req_pvld/pop 在 tb 绑 0
//   - sc2buf 三读口挂 cbuf_rd_agent（dat/wt ADDR_W=12、wmb=8）；cdma_sc_if 挂 stub
//   - 中断 4 位（dat[1:0]/wt[1:0]）各挂一个 intr_agent
//   - tie-off：pwrbus_ram_pd=0、clk_ovr=0、tmc2slcg_disable_clock_gating=1（关门控）
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import cdma_cbuf_ut_pkg::*;

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

  // ---------------- 互连 wire（名字照抄 partition_c） ----------------
  wire          cdma2buf_dat_wr_en;
  wire [11:0]   cdma2buf_dat_wr_addr;
  wire [1:0]    cdma2buf_dat_wr_hsel;
  wire [1023:0] cdma2buf_dat_wr_data;
  wire          cdma2buf_wt_wr_en;
  wire [11:0]   cdma2buf_wt_wr_addr;
  wire          cdma2buf_wt_wr_hsel;   // 注意：1 位（NV_NVDLA_cdma.v:85）
  wire [511:0]  cdma2buf_wt_wr_data;

  wire          csb2cdma_req_pvld;
  wire          csb2cdma_req_prdy;
  wire [62:0]   csb2cdma_req_pd;
  wire          cdma2csb_resp_valid;
  wire [33:0]   cdma2csb_resp_pd;

  wire          cdma_dat2mcif_rd_req_valid, cdma_dat2mcif_rd_req_ready;
  wire [78:0]   cdma_dat2mcif_rd_req_pd;
  wire          mcif2cdma_dat_rd_rsp_valid, mcif2cdma_dat_rd_rsp_ready;
  wire [513:0]  mcif2cdma_dat_rd_rsp_pd;
  wire          cdma_dat2cvif_rd_req_valid, cdma_dat2cvif_rd_req_ready;
  wire [78:0]   cdma_dat2cvif_rd_req_pd;
  wire          cvif2cdma_dat_rd_rsp_valid, cvif2cdma_dat_rd_rsp_ready;
  wire [513:0]  cvif2cdma_dat_rd_rsp_pd;
  wire          cdma_wt2mcif_rd_req_valid, cdma_wt2mcif_rd_req_ready;
  wire [78:0]   cdma_wt2mcif_rd_req_pd;
  wire          mcif2cdma_wt_rd_rsp_valid, mcif2cdma_wt_rd_rsp_ready;
  wire [513:0]  mcif2cdma_wt_rd_rsp_pd;
  wire          cdma_wt2cvif_rd_req_valid, cdma_wt2cvif_rd_req_ready;
  wire [78:0]   cdma_wt2cvif_rd_req_pd;
  wire          cvif2cdma_wt_rd_rsp_valid, cvif2cdma_wt_rd_rsp_ready;
  wire [513:0]  cvif2cdma_wt_rd_rsp_pd;

  wire          sc2buf_dat_rd_en;
  wire [11:0]   sc2buf_dat_rd_addr;
  wire          sc2buf_dat_rd_valid;
  wire [1023:0] sc2buf_dat_rd_data;
  wire          sc2buf_wt_rd_en;
  wire [11:0]   sc2buf_wt_rd_addr;
  wire          sc2buf_wt_rd_valid;
  wire [1023:0] sc2buf_wt_rd_data;
  wire          sc2buf_wmb_rd_en;
  wire [7:0]    sc2buf_wmb_rd_addr;
  wire          sc2buf_wmb_rd_valid;
  wire [1023:0] sc2buf_wmb_rd_data;

  wire          cdma2sc_dat_updt;
  wire [11:0]   cdma2sc_dat_entries;
  wire [11:0]   cdma2sc_dat_slices;
  wire          cdma2sc_wt_updt;
  wire [13:0]   cdma2sc_wt_kernels;
  wire [11:0]   cdma2sc_wt_entries;
  wire [8:0]    cdma2sc_wmb_entries;
  wire          cdma2sc_dat_pending_ack;
  wire          cdma2sc_wt_pending_ack;

  wire [1:0]    cdma_dat2glb_done_intr_pd;
  wire [1:0]    cdma_wt2glb_done_intr_pd;

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  dma_if #(79, 514, 515) u_dat_mc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_dat_cv_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_wt_mc_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  dma_if #(79, 514, 515) u_wt_cv_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  cbuf_wr_if #(.DATA_W(1024), .HSEL_W(2)) u_dat_wr_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_wr_if #(.DATA_W(512),  .HSEL_W(1)) u_wt_wr_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  cbuf_rd_if #(.ADDR_W(12)) u_dat_rd_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_rd_if #(.ADDR_W(12)) u_wt_rd_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_rd_if #(.ADDR_W(8))  u_wmb_rd_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  cdma_sc_if u_sc_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr_dat0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr_dat1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr_wt0_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr_wt1_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单口 <-> csb2cdma 扇出协议适配 ----------------
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  assign csb2cdma_req_pvld = u_csb_if.valid;
  assign csb2cdma_req_pd   = {7'h0, u_csb_if.nposted, u_csb_if.write,
                              u_csb_if.wdat, 6'h0, u_csb_if.addr};
  assign u_csb_if.ready    = csb2cdma_req_prdy;
  // resp_pd[33]=type：0=读数据、1=写完成（csb-link.md 6.2；error 位[32]无出口，丢弃）
  assign u_csb_if.rvalid      = cdma2csb_resp_valid & ~cdma2csb_resp_pd[33];
  assign u_csb_if.rdata       = cdma2csb_resp_pd[31:0];
  assign u_csb_if.wr_complete = cdma2csb_resp_valid &  cdma2csb_resp_pd[33];

  // ---------------- 4 路 DMA 读客户端 <-> dma_if ----------------
  // cdma 是纯读客户端：写通道与 pop 不存在，接口内绑 0
  assign u_dat_mc_if.rd_req_pvld  = cdma_dat2mcif_rd_req_valid;
  assign u_dat_mc_if.rd_req_pd    = cdma_dat2mcif_rd_req_pd;
  assign cdma_dat2mcif_rd_req_ready = u_dat_mc_if.rd_req_prdy;
  assign mcif2cdma_dat_rd_rsp_valid = u_dat_mc_if.rd_rsp_pvld;
  assign mcif2cdma_dat_rd_rsp_pd    = u_dat_mc_if.rd_rsp_pd;
  assign u_dat_mc_if.rd_rsp_prdy  = mcif2cdma_dat_rd_rsp_ready;
  assign u_dat_mc_if.wr_req_pvld  = 1'b0;
  assign u_dat_mc_if.wr_req_pd    = '0;
  assign u_dat_mc_if.rd_cdt_lat_fifo_pop = 1'b0;

  assign u_dat_cv_if.rd_req_pvld  = cdma_dat2cvif_rd_req_valid;
  assign u_dat_cv_if.rd_req_pd    = cdma_dat2cvif_rd_req_pd;
  assign cdma_dat2cvif_rd_req_ready = u_dat_cv_if.rd_req_prdy;
  assign cvif2cdma_dat_rd_rsp_valid = u_dat_cv_if.rd_rsp_pvld;
  assign cvif2cdma_dat_rd_rsp_pd    = u_dat_cv_if.rd_rsp_pd;
  assign u_dat_cv_if.rd_rsp_prdy  = cvif2cdma_dat_rd_rsp_ready;
  assign u_dat_cv_if.wr_req_pvld  = 1'b0;
  assign u_dat_cv_if.wr_req_pd    = '0;
  assign u_dat_cv_if.rd_cdt_lat_fifo_pop = 1'b0;

  assign u_wt_mc_if.rd_req_pvld   = cdma_wt2mcif_rd_req_valid;
  assign u_wt_mc_if.rd_req_pd     = cdma_wt2mcif_rd_req_pd;
  assign cdma_wt2mcif_rd_req_ready  = u_wt_mc_if.rd_req_prdy;
  assign mcif2cdma_wt_rd_rsp_valid  = u_wt_mc_if.rd_rsp_pvld;
  assign mcif2cdma_wt_rd_rsp_pd     = u_wt_mc_if.rd_rsp_pd;
  assign u_wt_mc_if.rd_rsp_prdy   = mcif2cdma_wt_rd_rsp_ready;
  assign u_wt_mc_if.wr_req_pvld   = 1'b0;
  assign u_wt_mc_if.wr_req_pd     = '0;
  assign u_wt_mc_if.rd_cdt_lat_fifo_pop = 1'b0;

  assign u_wt_cv_if.rd_req_pvld   = cdma_wt2cvif_rd_req_valid;
  assign u_wt_cv_if.rd_req_pd     = cdma_wt2cvif_rd_req_pd;
  assign cdma_wt2cvif_rd_req_ready  = u_wt_cv_if.rd_req_prdy;
  assign cvif2cdma_wt_rd_rsp_valid  = u_wt_cv_if.rd_rsp_pvld;
  assign cvif2cdma_wt_rd_rsp_pd     = u_wt_cv_if.rd_rsp_pd;
  assign u_wt_cv_if.rd_rsp_prdy   = cvif2cdma_wt_rd_rsp_ready;
  assign u_wt_cv_if.wr_req_pvld   = 1'b0;
  assign u_wt_cv_if.wr_req_pd     = '0;
  assign u_wt_cv_if.rd_cdt_lat_fifo_pop = 1'b0;

  // ---------------- cbuf 写口监测（cdma2buf_* 直连并同时引到 wr_if） ----------------
  assign u_dat_wr_if.wr_en   = cdma2buf_dat_wr_en;
  assign u_dat_wr_if.wr_addr = cdma2buf_dat_wr_addr;
  assign u_dat_wr_if.wr_hsel = cdma2buf_dat_wr_hsel;
  assign u_dat_wr_if.wr_data = cdma2buf_dat_wr_data;
  assign u_wt_wr_if.wr_en    = cdma2buf_wt_wr_en;
  assign u_wt_wr_if.wr_addr  = cdma2buf_wt_wr_addr;
  assign u_wt_wr_if.wr_hsel  = cdma2buf_wt_wr_hsel;
  assign u_wt_wr_if.wr_data  = cdma2buf_wt_wr_data;

  // ---------------- sc2buf 三读口（cbuf_rd_agent 驱 en/addr，回采 valid/data） ------
  // 注意：wt 与 wmb 不得同拍读 bank15（cbuf 断言 :6268），由 sequence 保证
  assign sc2buf_dat_rd_en    = u_dat_rd_if.rd_en;
  assign sc2buf_dat_rd_addr  = u_dat_rd_if.rd_addr;
  assign u_dat_rd_if.rd_valid = sc2buf_dat_rd_valid;
  assign u_dat_rd_if.rd_data  = sc2buf_dat_rd_data;
  assign sc2buf_wt_rd_en     = u_wt_rd_if.rd_en;
  assign sc2buf_wt_rd_addr   = u_wt_rd_if.rd_addr;
  assign u_wt_rd_if.rd_valid  = sc2buf_wt_rd_valid;
  assign u_wt_rd_if.rd_data   = sc2buf_wt_rd_data;
  assign sc2buf_wmb_rd_en    = u_wmb_rd_if.rd_en;
  assign sc2buf_wmb_rd_addr  = u_wmb_rd_if.rd_addr;
  assign u_wmb_rd_if.rd_valid = sc2buf_wmb_rd_valid;
  assign u_wmb_rd_if.rd_data  = sc2buf_wmb_rd_data;

  // ---------------- cdma_sc 状态-信用面 ----------------
  assign u_sc_if.cdma2sc_dat_updt        = cdma2sc_dat_updt;
  assign u_sc_if.cdma2sc_dat_entries     = cdma2sc_dat_entries;
  assign u_sc_if.cdma2sc_dat_slices      = cdma2sc_dat_slices;
  assign u_sc_if.cdma2sc_wt_updt         = cdma2sc_wt_updt;
  assign u_sc_if.cdma2sc_wt_kernels      = cdma2sc_wt_kernels;
  assign u_sc_if.cdma2sc_wt_entries      = cdma2sc_wt_entries;
  assign u_sc_if.cdma2sc_wmb_entries     = cdma2sc_wmb_entries;
  assign u_sc_if.cdma2sc_dat_pending_ack = cdma2sc_dat_pending_ack;
  assign u_sc_if.cdma2sc_wt_pending_ack  = cdma2sc_wt_pending_ack;

  // ---------------- 中断按位挂接 ----------------
  assign u_intr_dat0_if.intr = cdma_dat2glb_done_intr_pd[0];
  assign u_intr_dat1_if.intr = cdma_dat2glb_done_intr_pd[1];
  assign u_intr_wt0_if.intr  = cdma_wt2glb_done_intr_pd[0];
  assign u_intr_wt1_if.intr  = cdma_wt2glb_done_intr_pd[1];

  // ---------------- DUT：cdma（端口序照抄 partition_c:1600-1665） ----------------
  NV_NVDLA_cdma u_NV_NVDLA_cdma (
     .nvdla_core_clk                (nvdla_core_clk)
    ,.nvdla_core_rstn               (nvdla_core_rstn)
    ,.cdma2buf_dat_wr_en            (cdma2buf_dat_wr_en)
    ,.cdma2buf_dat_wr_addr          (cdma2buf_dat_wr_addr[11:0])
    ,.cdma2buf_dat_wr_hsel          (cdma2buf_dat_wr_hsel[1:0])
    ,.cdma2buf_dat_wr_data          (cdma2buf_dat_wr_data[1023:0])
    ,.cdma2buf_wt_wr_en             (cdma2buf_wt_wr_en)
    ,.cdma2buf_wt_wr_addr           (cdma2buf_wt_wr_addr[11:0])
    ,.cdma2buf_wt_wr_hsel           (cdma2buf_wt_wr_hsel)
    ,.cdma2buf_wt_wr_data           (cdma2buf_wt_wr_data[511:0])
    ,.cdma2csb_resp_valid           (cdma2csb_resp_valid)
    ,.cdma2csb_resp_pd              (cdma2csb_resp_pd[33:0])
    ,.cdma2sc_dat_pending_ack       (cdma2sc_dat_pending_ack)
    ,.cdma2sc_wt_pending_ack        (cdma2sc_wt_pending_ack)
    ,.cdma_dat2cvif_rd_req_valid    (cdma_dat2cvif_rd_req_valid)
    ,.cdma_dat2cvif_rd_req_ready    (cdma_dat2cvif_rd_req_ready)
    ,.cdma_dat2cvif_rd_req_pd       (cdma_dat2cvif_rd_req_pd[78:0])
    ,.cdma_dat2glb_done_intr_pd     (cdma_dat2glb_done_intr_pd[1:0])
    ,.cdma_dat2mcif_rd_req_valid    (cdma_dat2mcif_rd_req_valid)
    ,.cdma_dat2mcif_rd_req_ready    (cdma_dat2mcif_rd_req_ready)
    ,.cdma_dat2mcif_rd_req_pd       (cdma_dat2mcif_rd_req_pd[78:0])
    ,.cdma_wt2cvif_rd_req_valid     (cdma_wt2cvif_rd_req_valid)
    ,.cdma_wt2cvif_rd_req_ready     (cdma_wt2cvif_rd_req_ready)
    ,.cdma_wt2cvif_rd_req_pd        (cdma_wt2cvif_rd_req_pd[78:0])
    ,.cdma_wt2glb_done_intr_pd      (cdma_wt2glb_done_intr_pd[1:0])
    ,.cdma_wt2mcif_rd_req_valid     (cdma_wt2mcif_rd_req_valid)
    ,.cdma_wt2mcif_rd_req_ready     (cdma_wt2mcif_rd_req_ready)
    ,.cdma_wt2mcif_rd_req_pd        (cdma_wt2mcif_rd_req_pd[78:0])
    ,.csb2cdma_req_pvld             (csb2cdma_req_pvld)
    ,.csb2cdma_req_prdy             (csb2cdma_req_prdy)
    ,.csb2cdma_req_pd               (csb2cdma_req_pd[62:0])
    ,.cvif2cdma_dat_rd_rsp_valid    (cvif2cdma_dat_rd_rsp_valid)
    ,.cvif2cdma_dat_rd_rsp_ready    (cvif2cdma_dat_rd_rsp_ready)
    ,.cvif2cdma_dat_rd_rsp_pd       (cvif2cdma_dat_rd_rsp_pd[513:0])
    ,.cvif2cdma_wt_rd_rsp_valid     (cvif2cdma_wt_rd_rsp_valid)
    ,.cvif2cdma_wt_rd_rsp_ready     (cvif2cdma_wt_rd_rsp_ready)
    ,.cvif2cdma_wt_rd_rsp_pd        (cvif2cdma_wt_rd_rsp_pd[513:0])
    ,.cdma2sc_dat_updt              (cdma2sc_dat_updt)
    ,.cdma2sc_dat_entries           (cdma2sc_dat_entries[11:0])
    ,.cdma2sc_dat_slices            (cdma2sc_dat_slices[11:0])
    ,.sc2cdma_dat_updt              (u_sc_if.sc2cdma_dat_updt)
    ,.sc2cdma_dat_entries           (u_sc_if.sc2cdma_dat_entries[11:0])
    ,.sc2cdma_dat_slices            (u_sc_if.sc2cdma_dat_slices[11:0])
    ,.mcif2cdma_dat_rd_rsp_valid    (mcif2cdma_dat_rd_rsp_valid)
    ,.mcif2cdma_dat_rd_rsp_ready    (mcif2cdma_dat_rd_rsp_ready)
    ,.mcif2cdma_dat_rd_rsp_pd       (mcif2cdma_dat_rd_rsp_pd[513:0])
    ,.mcif2cdma_wt_rd_rsp_valid     (mcif2cdma_wt_rd_rsp_valid)
    ,.mcif2cdma_wt_rd_rsp_ready     (mcif2cdma_wt_rd_rsp_ready)
    ,.mcif2cdma_wt_rd_rsp_pd        (mcif2cdma_wt_rd_rsp_pd[513:0])
    ,.pwrbus_ram_pd                 (32'b0)
    ,.sc2cdma_dat_pending_req       (u_sc_if.sc2cdma_dat_pending_req)
    ,.sc2cdma_wt_pending_req        (u_sc_if.sc2cdma_wt_pending_req)
    ,.cdma2sc_wt_updt               (cdma2sc_wt_updt)
    ,.cdma2sc_wt_kernels            (cdma2sc_wt_kernels[13:0])
    ,.cdma2sc_wt_entries            (cdma2sc_wt_entries[11:0])
    ,.cdma2sc_wmb_entries           (cdma2sc_wmb_entries[8:0])
    ,.sc2cdma_wt_updt               (u_sc_if.sc2cdma_wt_updt)
    ,.sc2cdma_wt_kernels            (u_sc_if.sc2cdma_wt_kernels[13:0])
    ,.sc2cdma_wt_entries            (u_sc_if.sc2cdma_wt_entries[11:0])
    ,.sc2cdma_wmb_entries           (u_sc_if.sc2cdma_wmb_entries[8:0])
    ,.dla_clk_ovr_on_sync           (1'b0)
    ,.global_clk_ovr_on_sync        (1'b0)
    ,.tmc2slcg_disable_clock_gating (1'b1)
  );

  // ---------------- DUT：cbuf（端口序照抄 partition_c:1670-1693） ----------------
  NV_NVDLA_cbuf u_NV_NVDLA_cbuf (
     .nvdla_core_clk                (nvdla_core_clk)
    ,.nvdla_core_rstn               (nvdla_core_rstn)
    ,.pwrbus_ram_pd                 (32'b0)
    ,.cdma2buf_dat_wr_en            (cdma2buf_dat_wr_en)
    ,.cdma2buf_dat_wr_addr          (cdma2buf_dat_wr_addr[11:0])
    ,.cdma2buf_dat_wr_hsel          (cdma2buf_dat_wr_hsel[1:0])
    ,.cdma2buf_dat_wr_data          (cdma2buf_dat_wr_data[1023:0])
    ,.cdma2buf_wt_wr_en             (cdma2buf_wt_wr_en)
    ,.cdma2buf_wt_wr_addr           (cdma2buf_wt_wr_addr[11:0])
    ,.cdma2buf_wt_wr_hsel           (cdma2buf_wt_wr_hsel)
    ,.cdma2buf_wt_wr_data           (cdma2buf_wt_wr_data[511:0])
    ,.sc2buf_dat_rd_en              (sc2buf_dat_rd_en)
    ,.sc2buf_dat_rd_addr            (sc2buf_dat_rd_addr[11:0])
    ,.sc2buf_dat_rd_valid           (sc2buf_dat_rd_valid)
    ,.sc2buf_dat_rd_data            (sc2buf_dat_rd_data[1023:0])
    ,.sc2buf_wt_rd_en               (sc2buf_wt_rd_en)
    ,.sc2buf_wt_rd_addr             (sc2buf_wt_rd_addr[11:0])
    ,.sc2buf_wt_rd_valid            (sc2buf_wt_rd_valid)
    ,.sc2buf_wt_rd_data             (sc2buf_wt_rd_data[1023:0])
    ,.sc2buf_wmb_rd_en              (sc2buf_wmb_rd_en)
    ,.sc2buf_wmb_rd_addr            (sc2buf_wmb_rd_addr[7:0])
    ,.sc2buf_wmb_rd_valid           (sc2buf_wmb_rd_valid)
    ,.sc2buf_wmb_rd_data            (sc2buf_wmb_rd_data[1023:0])
  );

  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.dat_mc_agt*", "dma_vif", u_dat_mc_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.dat_cv_agt*", "dma_vif", u_dat_cv_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.wt_mc_agt*", "dma_vif", u_wt_mc_if);
    uvm_config_db#(virtual dma_if#(79,514,515))::set(
      null, "uvm_test_top.env.wt_cv_agt*", "dma_vif", u_wt_cv_if);

    uvm_config_db#(virtual cbuf_wr_if#(1024,2))::set(
      null, "uvm_test_top.env.dat_wr_mon*", "cbuf_wr_vif", u_dat_wr_if);
    uvm_config_db#(virtual cbuf_wr_if#(512,1))::set(
      null, "uvm_test_top.env.wt_wr_mon*", "cbuf_wr_vif", u_wt_wr_if);

    uvm_config_db#(virtual cbuf_rd_if#(12))::set(
      null, "uvm_test_top.env.dat_rd_agt*", "cbuf_rd_vif", u_dat_rd_if);
    uvm_config_db#(virtual cbuf_rd_if#(12))::set(
      null, "uvm_test_top.env.wt_rd_agt*", "cbuf_rd_vif", u_wt_rd_if);
    uvm_config_db#(virtual cbuf_rd_if#(8))::set(
      null, "uvm_test_top.env.wmb_rd_agt*", "cbuf_rd_vif", u_wmb_rd_if);

    uvm_config_db#(virtual cdma_sc_if)::set(
      null, "uvm_test_top.env.sc_stub*", "cdma_sc_vif", u_sc_if);

    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr_dat0_agt*", "intr_vif", u_intr_dat0_if);
    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr_dat1_agt*", "intr_vif", u_intr_dat1_if);
    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr_wt0_agt*", "intr_vif", u_intr_wt0_if);
    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr_wt1_agt*", "intr_vif", u_intr_wt1_if);

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
