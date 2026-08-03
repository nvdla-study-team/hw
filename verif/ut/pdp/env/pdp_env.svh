// -----------------------------------------------------------------------------
// pdp_env : csb master + MCIF dma slave + sdp2pdp source stub + 2 路中断 +
//           scoreboard 骨架
//   agent 实例名与 tb_top 的 config_db 作用域一一对应（改名要同步 tb）：
//     csb_agt / mc_agt / sdp_src / intr0_agt / intr1_agt
//   CVIF 一组在 tb 内 tie-off（哨兵监出请求即打 "ERROR :"），env 不建组件
// -----------------------------------------------------------------------------
`ifndef PDP_ENV_SVH
`define PDP_ENV_SVH

class pdp_env extends uvm_env;

  csb_master_agent      csb_agt;
  dma_slave_agent_cdp_t mc_agt;     // pdp2mcif 读+写+pop 全接（79/514/515 特化）
  sdp2pdp_source_stub   sdp_src;    // sdp2pdp 直连入口源（T0 冒烟不发数）
  intr_agent            intr0_agt;  // pdp2glb_done_intr_pd[0]
  intr_agent            intr1_agt;  // pdp2glb_done_intr_pd[1]
  pdp_scoreboard        sb;

  `uvm_component_utils(pdp_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    csb_agt   = csb_master_agent::type_id::create("csb_agt", this);
    mc_agt    = dma_slave_agent_cdp_t::type_id::create("mc_agt", this);
    sdp_src   = sdp2pdp_source_stub::type_id::create("sdp_src", this);
    intr0_agt = intr_agent::type_id::create("intr0_agt", this);
    intr1_agt = intr_agent::type_id::create("intr1_agt", this);
    sb        = pdp_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mc_agt.mon.ap.connect(sb.dma_imp);
    intr0_agt.ap.connect(sb.intr_imp);
    intr1_agt.ap.connect(sb.intr_imp);
  endfunction

endclass : pdp_env

`endif // PDP_ENV_SVH
