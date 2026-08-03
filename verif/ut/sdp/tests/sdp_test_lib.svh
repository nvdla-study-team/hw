// -----------------------------------------------------------------------------
// sdp_test_lib
//   - base   : 建 env，objection + set_drain_time + run_seqs 钩子
//   - t0_reg : T0 双 reg 块寄存器冒烟（环境自证，唯一测试；数据通路测试待后续 Wave）
// -----------------------------------------------------------------------------
`ifndef SDP_TEST_LIB_SVH
`define SDP_TEST_LIB_SVH

class sdp_base_test extends ut_base_test;

  sdp_env env;

  `uvm_component_utils(sdp_base_test)

  function new(string name = "sdp_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = sdp_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "sdp test body");
    phase.get_objection().set_drain_time(this, 1us);
    run_seqs();
    phase.drop_objection(this, "sdp test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : sdp_base_test


class sdp_t0_reg_test extends sdp_base_test;

  `uvm_component_utils(sdp_t0_reg_test)

  function new(string name = "sdp_t0_reg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    sdp_t0_reg_seq t0;
    t0 = sdp_t0_reg_seq::type_id::create("t0");
    t0.start(env.csb_agt.sqr);
  endtask

endclass : sdp_t0_reg_test

`endif // SDP_TEST_LIB_SVH
