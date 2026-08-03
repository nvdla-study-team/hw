// -----------------------------------------------------------------------------
// sdp_env : csb master + 4 路 MCIF dma slave + cacc 源 stub + pdp 收 stub +
//           2 路中断 + scoreboard 骨架
//   agent 实例名与 tb_top 的 config_db 作用域一一对应（改名要同步 tb）：
//   mc_agt = main 客户端（mrdma 读 + wdma 写共用）、b/n/e_agt = 只读客户端；
//   CVIF 侧在 tb 内 tie-off + 哨兵，不建 agent
// -----------------------------------------------------------------------------
`ifndef SDP_ENV_SVH
`define SDP_ENV_SVH

class sdp_env extends uvm_env;

  csb_master_agent          csb_agt;
  dma_slave_agent_cdp_t     mc_agt;    // sdp2mcif（读+写）+ mcif2sdp_rd/wr_rsp
  dma_slave_agent_cdp_t     b_agt;     // sdp_b2mcif（只读）
  dma_slave_agent_cdp_t     n_agt;     // sdp_n2mcif（只读）
  dma_slave_agent_cdp_t     e_agt;     // sdp_e2mcif（只读）
  sdp_source_stub           cacc_src;  // cacc2sdp 入口激励（冒烟不发数）
  sdp2pdp_sink_stub         pdp_sink;  // sdp2pdp 出口（默认恒 ready）
  intr_agent                intr0_agt; // sdp2glb_done_intr_pd[0]
  intr_agent                intr1_agt; // sdp2glb_done_intr_pd[1]
  sdp_scoreboard            sb;

  `uvm_component_utils(sdp_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    csb_agt   = csb_master_agent::type_id::create("csb_agt", this);
    mc_agt    = dma_slave_agent_cdp_t::type_id::create("mc_agt", this);
    b_agt     = dma_slave_agent_cdp_t::type_id::create("b_agt", this);
    n_agt     = dma_slave_agent_cdp_t::type_id::create("n_agt", this);
    e_agt     = dma_slave_agent_cdp_t::type_id::create("e_agt", this);
    cacc_src  = sdp_source_stub::type_id::create("cacc_src", this);
    pdp_sink  = sdp2pdp_sink_stub::type_id::create("pdp_sink", this);
    intr0_agt = intr_agent::type_id::create("intr0_agt", this);
    intr1_agt = intr_agent::type_id::create("intr1_agt", this);
    sb        = sdp_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mc_agt.mon.ap.connect(sb.dma_imp);
    b_agt.mon.ap.connect(sb.dma_imp);
    n_agt.mon.ap.connect(sb.dma_imp);
    e_agt.mon.ap.connect(sb.dma_imp);
    pdp_sink.ap.connect(sb.pdp_imp);
    intr0_agt.ap.connect(sb.intr_imp);
    intr1_agt.ap.connect(sb.intr_imp);
  endfunction

endclass : sdp_env

`endif // SDP_ENV_SVH
