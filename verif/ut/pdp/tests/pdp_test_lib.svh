// -----------------------------------------------------------------------------
// pdp_test_lib
//   - base   : 建 env，objection + run_seqs 钩子
//   - t0_reg : T0 双 reg 块寄存器冒烟（阶段4 环境自证，唯一测试）
// -----------------------------------------------------------------------------
`ifndef PDP_TEST_LIB_SVH
`define PDP_TEST_LIB_SVH

class pdp_base_test extends ut_base_test;

  pdp_env env;

  `uvm_component_utils(pdp_base_test)

  function new(string name = "pdp_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = pdp_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "pdp test body");
    phase.get_objection().set_drain_time(this, 1us);
    run_seqs();
    phase.drop_objection(this, "pdp test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : pdp_base_test


class pdp_t0_reg_test extends pdp_base_test;

  `uvm_component_utils(pdp_t0_reg_test)

  function new(string name = "pdp_t0_reg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    pdp_t0_reg_seq t0;
    t0 = pdp_t0_reg_seq::type_id::create("t0");
    t0.start(env.csb_agt.sqr);
  endtask

endclass : pdp_t0_reg_test

`endif // PDP_TEST_LIB_SVH
