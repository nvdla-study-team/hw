// -----------------------------------------------------------------------------
// tb_top : NV_NVDLA_csb_master UT 顶层
//   - 双时钟：falcon 10ns / core 7ns（非整数比激活真实 CDC），
//     可用 +falcon_period_ns= / +core_period_ns= 覆盖
//   - 复位：两路同时拉低 ~100ns 后释放（101ns，避开两路时钟沿）
//   - 17 路扇出端口 <-> interface 用宏批量生成（实例化 + config_db set + 端口连接）
//   - WAVES=1 编译（+define+WAVES_FSDB）且运行加 +fsdb 时 dump fsdb
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import csb_master_ut_pkg::*;

  // ---------------- 时钟 / 复位 ----------------
  real falcon_period_ns = 10.0;
  real core_period_ns   = 7.0;

  logic nvdla_falcon_clk  = 1'b0;
  logic nvdla_core_clk    = 1'b0;
  logic nvdla_falcon_rstn = 1'b0;
  logic nvdla_core_rstn   = 1'b0;

  initial begin
    void'($value$plusargs("falcon_period_ns=%f", falcon_period_ns));
    forever #(falcon_period_ns / 2.0) nvdla_falcon_clk = ~nvdla_falcon_clk;
  end

  initial begin
    void'($value$plusargs("core_period_ns=%f", core_period_ns));
    forever #(core_period_ns / 2.0) nvdla_core_clk = ~nvdla_core_clk;
  end

  initial begin
    nvdla_falcon_rstn = 1'b0;
    nvdla_core_rstn   = 1'b0;
    #101; // ~100ns，101 不落在 10ns/7ns 任一时钟沿上
    nvdla_falcon_rstn = 1'b1;
    nvdla_core_rstn   = 1'b1;
  end

  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_falcon_clk), .rstn(nvdla_falcon_rstn));

  // 每路一条：interface 实例 + config_db set
  `define UT_CSB_FAN_IF(idx, xx) \
    csb_fanout_if u_fan_if_``xx (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn)); \
    initial uvm_config_db#(virtual csb_fanout_if)::set( \
              null, "*", $sformatf("fan_vif_%0d", idx), u_fan_if_``xx);

  `UT_CSB_FAN_IF(0,  glb)
  `UT_CSB_FAN_IF(1,  gec)
  `UT_CSB_FAN_IF(2,  mcif)
  `UT_CSB_FAN_IF(3,  cvif)
  `UT_CSB_FAN_IF(4,  bdma)
  `UT_CSB_FAN_IF(5,  cdma)
  `UT_CSB_FAN_IF(6,  csc)
  `UT_CSB_FAN_IF(7,  cmac_a)
  `UT_CSB_FAN_IF(8,  cmac_b)
  `UT_CSB_FAN_IF(9,  cacc)
  `UT_CSB_FAN_IF(10, sdp_rdma)
  `UT_CSB_FAN_IF(11, sdp)
  `UT_CSB_FAN_IF(12, pdp_rdma)
  `UT_CSB_FAN_IF(13, pdp)
  `UT_CSB_FAN_IF(14, cdp_rdma)
  `UT_CSB_FAN_IF(15, cdp)
  `UT_CSB_FAN_IF(16, rbk)

  // 每路 5 个端口连接
  `define UT_CSB_FAN_CONN(xx) \
    .csb2``xx``_req_pvld  (u_fan_if_``xx.req_pvld), \
    .csb2``xx``_req_prdy  (u_fan_if_``xx.req_prdy), \
    .csb2``xx``_req_pd    (u_fan_if_``xx.req_pd), \
    .``xx``2csb_resp_valid(u_fan_if_``xx.resp_valid), \
    .``xx``2csb_resp_pd   (u_fan_if_``xx.resp_pd),

  // ---------------- DUT ----------------
  // 宏组在前（每个宏自带尾逗号），固定端口在后收尾
  NV_NVDLA_csb_master dut (
    `UT_CSB_FAN_CONN(glb)
    `UT_CSB_FAN_CONN(gec)
    `UT_CSB_FAN_CONN(mcif)
    `UT_CSB_FAN_CONN(cvif)
    `UT_CSB_FAN_CONN(bdma)
    `UT_CSB_FAN_CONN(cdma)
    `UT_CSB_FAN_CONN(csc)
    `UT_CSB_FAN_CONN(cmac_a)
    `UT_CSB_FAN_CONN(cmac_b)
    `UT_CSB_FAN_CONN(cacc)
    `UT_CSB_FAN_CONN(sdp_rdma)
    `UT_CSB_FAN_CONN(sdp)
    `UT_CSB_FAN_CONN(pdp_rdma)
    `UT_CSB_FAN_CONN(pdp)
    `UT_CSB_FAN_CONN(cdp_rdma)
    `UT_CSB_FAN_CONN(cdp)
    `UT_CSB_FAN_CONN(rbk)
     .nvdla_core_clk        (nvdla_core_clk)
    ,.nvdla_core_rstn       (nvdla_core_rstn)
    ,.nvdla_falcon_clk      (nvdla_falcon_clk)
    ,.nvdla_falcon_rstn     (nvdla_falcon_rstn)
    ,.pwrbus_ram_pd         (32'h0)
    ,.csb2nvdla_valid       (u_csb_if.valid)
    ,.csb2nvdla_ready       (u_csb_if.ready)
    ,.csb2nvdla_addr        (u_csb_if.addr)
    ,.csb2nvdla_wdat        (u_csb_if.wdat)
    ,.csb2nvdla_write       (u_csb_if.write)
    ,.csb2nvdla_nposted     (u_csb_if.nposted)
    ,.nvdla2csb_valid       (u_csb_if.rvalid)
    ,.nvdla2csb_data        (u_csb_if.rdata)
    ,.nvdla2csb_wr_complete (u_csb_if.wr_complete)
  );

  // ---------------- UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);
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
