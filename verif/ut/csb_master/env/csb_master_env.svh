// -----------------------------------------------------------------------------
// csb_master_env : mst_agt（单口面）+ fan_agt[17]（扇出面）+ scoreboard
//   背压/延迟旋钮由 test 经 config_db(int unsigned) 设到本 env（作用域 "env"）：
//     rdy_gap_pct / gap_min / gap_max / resp_dly_min / resp_dly_max
//   默认：零背压、resp 延迟 0..2（smoke 档）
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_ENV_SVH
`define CSB_MASTER_ENV_SVH

class csb_master_env extends uvm_env;

  csb_master_agent      mst_agt;
  csb_fanout_agent      fan_agt [NUM_CSB_TGT];
  csb_master_scoreboard sb;

  int unsigned rdy_gap_pct  = 0;
  int unsigned gap_min      = 1;
  int unsigned gap_max      = 8;
  int unsigned resp_dly_min = 0;
  int unsigned resp_dly_max = 2;

  `uvm_component_utils(csb_master_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    void'(uvm_config_db#(int unsigned)::get(this, "", "rdy_gap_pct",  rdy_gap_pct));
    void'(uvm_config_db#(int unsigned)::get(this, "", "gap_min",      gap_min));
    void'(uvm_config_db#(int unsigned)::get(this, "", "gap_max",      gap_max));
    void'(uvm_config_db#(int unsigned)::get(this, "", "resp_dly_min", resp_dly_min));
    void'(uvm_config_db#(int unsigned)::get(this, "", "resp_dly_max", resp_dly_max));
    `uvm_info(get_type_name(),
              $sformatf("fanout knobs: rdy_gap_pct=%0d gap=[%0d:%0d] resp_dly=[%0d:%0d]",
                        rdy_gap_pct, gap_min, gap_max, resp_dly_min, resp_dly_max),
              UVM_LOW)

    mst_agt = csb_master_agent::type_id::create("mst_agt", this);

    for (int i = 0; i < NUM_CSB_TGT; i++) begin
      csb_fanout_cfg c;
      c = csb_fanout_cfg::type_id::create($sformatf("fan_cfg_%0d", i));
      c.tgt_id       = i;
      c.rdy_gap_pct  = rdy_gap_pct;
      c.gap_min      = gap_min;
      c.gap_max      = gap_max;
      c.resp_dly_min = resp_dly_min;
      c.resp_dly_max = resp_dly_max;
      fan_agt[i] = csb_fanout_agent::type_id::create($sformatf("fan_agt_%0d", i), this);
      fan_agt[i].cfg = c; // env build 先于 agent build，直接递 handle
    end

    sb = csb_master_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mst_agt.mon.ap_req.connect(sb.mst_req_imp);
    mst_agt.mon.ap_rsp.connect(sb.mst_rsp_imp);
    foreach (fan_agt[i]) begin
      fan_agt[i].mon.ap_req.connect(sb.fan_req_imp);
      fan_agt[i].mon.ap_rsp.connect(sb.fan_rsp_imp);
    end
  endfunction

endclass : csb_master_env

`endif // CSB_MASTER_ENV_SVH
