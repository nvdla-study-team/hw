// -----------------------------------------------------------------------------
// cdma_cbuf_env : csb master + 4 路 DMA slave + cbuf 写监测/读 stub + sc stub +
//                 4 路中断 + scoreboard 空壳
//   agent 实例名与 tb_top 的 config_db 作用域一一对应（改名要同步 tb）
// -----------------------------------------------------------------------------
`ifndef CDMA_CBUF_ENV_SVH
`define CDMA_CBUF_ENV_SVH

class cdma_cbuf_env extends uvm_env;

  csb_master_agent          csb_agt;

  dma_slave_agent_cdp_t     dat_mc_agt;
  dma_slave_agent_cdp_t     dat_cv_agt;
  dma_slave_agent_cdp_t     wt_mc_agt;
  dma_slave_agent_cdp_t     wt_cv_agt;

  cbuf_wr_monitor_dat_t     dat_wr_mon;
  cbuf_wr_monitor_wt_t      wt_wr_mon;

  cbuf_rd_agent_12_t        dat_rd_agt;
  cbuf_rd_agent_12_t        wt_rd_agt;
  cbuf_rd_agent_8_t         wmb_rd_agt;

  cdma_sc_stub              sc_stub;

  intr_agent                intr_dat0_agt;
  intr_agent                intr_dat1_agt;
  intr_agent                intr_wt0_agt;
  intr_agent                intr_wt1_agt;

  cdma_cbuf_scoreboard      sb;

  `uvm_component_utils(cdma_cbuf_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    csb_agt    = csb_master_agent::type_id::create("csb_agt", this);

    dat_mc_agt = dma_slave_agent_cdp_t::type_id::create("dat_mc_agt", this);
    dat_cv_agt = dma_slave_agent_cdp_t::type_id::create("dat_cv_agt", this);
    wt_mc_agt  = dma_slave_agent_cdp_t::type_id::create("wt_mc_agt", this);
    wt_cv_agt  = dma_slave_agent_cdp_t::type_id::create("wt_cv_agt", this);

    dat_wr_mon = cbuf_wr_monitor_dat_t::type_id::create("dat_wr_mon", this);
    wt_wr_mon  = cbuf_wr_monitor_wt_t::type_id::create("wt_wr_mon", this);

    dat_rd_agt = cbuf_rd_agent_12_t::type_id::create("dat_rd_agt", this);
    wt_rd_agt  = cbuf_rd_agent_12_t::type_id::create("wt_rd_agt", this);
    wmb_rd_agt = cbuf_rd_agent_8_t::type_id::create("wmb_rd_agt", this);

    sc_stub    = cdma_sc_stub::type_id::create("sc_stub", this);

    intr_dat0_agt = intr_agent::type_id::create("intr_dat0_agt", this);
    intr_dat1_agt = intr_agent::type_id::create("intr_dat1_agt", this);
    intr_wt0_agt  = intr_agent::type_id::create("intr_wt0_agt", this);
    intr_wt1_agt  = intr_agent::type_id::create("intr_wt1_agt", this);

    sb = cdma_cbuf_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    dat_mc_agt.mon.ap.connect(sb.dat_mc_req_imp);
    dat_cv_agt.mon.ap.connect(sb.dat_cv_req_imp);
    wt_mc_agt.mon.ap.connect(sb.wt_mc_req_imp);
    wt_cv_agt.mon.ap.connect(sb.wt_cv_req_imp);
    dat_wr_mon.ap.connect(sb.cbuf_dat_wr_imp);
    wt_wr_mon.ap.connect(sb.cbuf_wt_wr_imp);
    dat_rd_agt.mon.ap.connect(sb.cbuf_dat_rd_imp);
    wt_rd_agt.mon.ap.connect(sb.cbuf_wt_rd_imp);
    wmb_rd_agt.mon.ap.connect(sb.cbuf_wmb_rd_imp);
    sc_stub.ap.connect(sb.sc_updt_imp);
  endfunction

endclass : cdma_cbuf_env

`endif // CDMA_CBUF_ENV_SVH
