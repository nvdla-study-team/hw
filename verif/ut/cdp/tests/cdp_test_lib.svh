// -----------------------------------------------------------------------------
// cdp_test_lib
//   - base   : 建 env，objection + run_seqs 钩子
//   - t0_reg : T0 双块寄存器冒烟（环境自证，纯 CSB 面）
//   其余测试待测试点分解（阶段4 只搭环境）
// -----------------------------------------------------------------------------
`ifndef CDP_TEST_LIB_SVH
`define CDP_TEST_LIB_SVH

class cdp_base_test extends ut_base_test;

  cdp_env env;

  `uvm_component_utils(cdp_base_test)

  function new(string name = "cdp_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cdp_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "cdp test body");
    phase.get_objection().set_drain_time(this, 1us);
    run_seqs();
    phase.drop_objection(this, "cdp test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : cdp_base_test


class cdp_t0_reg_test extends cdp_base_test;

  `uvm_component_utils(cdp_t0_reg_test)

  function new(string name = "cdp_t0_reg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    cdp_t0_reg_seq t0;
    t0 = cdp_t0_reg_seq::type_id::create("t0");
    t0.start(env.csb_agt.sqr);
  endtask

endclass : cdp_t0_reg_test

`endif // CDP_TEST_LIB_SVH
