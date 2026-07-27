// -----------------------------------------------------------------------------
// csb_master_test_lib : base / smoke / random 三个 test
//   - base   : 建 env，run_phase 抓 objection（drain 1us），run_seqs() 留空钩子
//   - smoke  : smoke_seq + dummy_seq，零背压、resp 延迟 0..2（env 默认）
//   - random : 300 笔全随机 + 17 路背压（30%, 1..8 拍）+ resp 延迟 0..8
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_TEST_LIB_SVH
`define CSB_MASTER_TEST_LIB_SVH

class csb_master_base_test extends ut_base_test;

  csb_master_env env;

  `uvm_component_utils(csb_master_base_test)

  function new(string name = "csb_master_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = csb_master_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "csb_master test body");
    phase.get_objection().set_drain_time(this, 1us); // 收尾 CDC 余响
    run_seqs();
    phase.drop_objection(this, "csb_master test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : csb_master_base_test


class csb_master_smoke_test extends csb_master_base_test;

  `uvm_component_utils(csb_master_smoke_test)

  function new(string name = "csb_master_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    csb_smoke_seq smoke;
    csb_dummy_seq dummy;
    smoke = csb_smoke_seq::type_id::create("smoke");
    smoke.start(env.mst_agt.sqr);
    dummy = csb_dummy_seq::type_id::create("dummy");
    dummy.start(env.mst_agt.sqr);
  endtask

endclass : csb_master_smoke_test


class csb_master_random_test extends csb_master_base_test;

  `uvm_component_utils(csb_master_random_test)

  function new(string name = "csb_master_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    uvm_config_db#(int unsigned)::set(this, "env", "rdy_gap_pct",  30);
    uvm_config_db#(int unsigned)::set(this, "env", "gap_min",      1);
    uvm_config_db#(int unsigned)::set(this, "env", "gap_max",      8);
    uvm_config_db#(int unsigned)::set(this, "env", "resp_dly_min", 0);
    uvm_config_db#(int unsigned)::set(this, "env", "resp_dly_max", 8);
    super.build_phase(phase);
  endfunction

  virtual task run_seqs();
    csb_random_seq rnd;
    rnd = csb_random_seq::type_id::create("rnd");
    rnd.num_txns = 300;
    rnd.start(env.mst_agt.sqr);
  endtask

endclass : csb_master_random_test

`endif // CSB_MASTER_TEST_LIB_SVH
