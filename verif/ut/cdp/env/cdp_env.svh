// -----------------------------------------------------------------------------
// cdp_env : csb master + 1 路 DMA slave（MCIF 宿）+ 2 路中断 + scoreboard 骨架
//   agent 实例名与 tb_top 的 config_db 作用域一一对应（改名要同步 tb）：
//     mc_agt / intr0_agt / intr1_agt
// -----------------------------------------------------------------------------
`ifndef CDP_ENV_SVH
`define CDP_ENV_SVH

class cdp_env extends uvm_env;

  csb_master_agent      csb_agt;
  dma_slave_agent_cdp_t mc_agt;      // cdp2mcif 读+写+pop（79/514/515 原型位宽）
  intr_agent            intr0_agt;   // cdp2glb_done_intr_pd[0]
  intr_agent            intr1_agt;   // cdp2glb_done_intr_pd[1]
  cdp_scoreboard        sb;

  `uvm_component_utils(cdp_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    csb_agt   = csb_master_agent::type_id::create("csb_agt", this);
    mc_agt    = dma_slave_agent_cdp_t::type_id::create("mc_agt", this);
    intr0_agt = intr_agent::type_id::create("intr0_agt", this);
    intr1_agt = intr_agent::type_id::create("intr1_agt", this);
    sb        = cdp_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mc_agt.mon.ap.connect(sb.dma_imp);
    intr0_agt.ap.connect(sb.intr_imp);
    intr1_agt.ap.connect(sb.intr_imp);
  endfunction

endclass : cdp_env

`endif // CDP_ENV_SVH
