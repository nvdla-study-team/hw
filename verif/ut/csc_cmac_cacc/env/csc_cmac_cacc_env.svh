// -----------------------------------------------------------------------------
// csc_cmac_cacc_env : csb master + cbuf_model + csc_cdma_stub + sdp_sink +
//                     2 路中断 + scoreboard 骨架
//   agent 实例名与 tb_top 的 config_db 作用域一一对应（改名要同步 tb）
// -----------------------------------------------------------------------------
`ifndef CSC_CMAC_CACC_ENV_SVH
`define CSC_CMAC_CACC_ENV_SVH

class csc_cmac_cacc_env extends uvm_env;

  csb_master_agent          csb_agt;
  cbuf_model                cbuf_mdl;
  csc_cdma_stub             cdma_stub;
  sdp_sink_stub             sdp_sink;
  // cacc 中断位是 toggle 交替选位（delivery_buffer.v:1530-1532，不同于 CDMA 的
  // consumer 选位；done 与中断脉冲是两个时刻）——Wave2 层测试按 toggle 语义建预期
  intr_agent                intr0_agt;   // cacc2glb_done_intr_pd[0]
  intr_agent                intr1_agt;   // cacc2glb_done_intr_pd[1]
  csc_cmac_cacc_scoreboard  sb;

  `uvm_component_utils(csc_cmac_cacc_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    csb_agt   = csb_master_agent::type_id::create("csb_agt", this);
    cbuf_mdl  = cbuf_model::type_id::create("cbuf_mdl", this);
    cdma_stub = csc_cdma_stub::type_id::create("cdma_stub", this);
    sdp_sink  = sdp_sink_stub::type_id::create("sdp_sink", this);
    intr0_agt = intr_agent::type_id::create("intr0_agt", this);
    intr1_agt = intr_agent::type_id::create("intr1_agt", this);
    sb        = csc_cmac_cacc_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    sdp_sink.ap.connect(sb.sdp_imp);
    cdma_stub.ap.connect(sb.sc_rls_imp);
  endfunction

endclass : csc_cmac_cacc_env

`endif // CSC_CMAC_CACC_ENV_SVH
