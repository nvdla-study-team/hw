// -----------------------------------------------------------------------------
// csb_fanout_agent : 扇出面 agent（reactive responder + monitor）
//   1 个类 × 17 实例，env 在 build 期先填好 cfg（tgt_id 等）再进 agent build；
//   virtual interface 经 config_db 键 "fan_vif_<tgt_id>" 获取。
//   阶段3：可加 is_active + driver/sequencer，把同一 agent 变成主动 master 复用。
// -----------------------------------------------------------------------------
`ifndef CSB_FANOUT_AGENT_SVH
`define CSB_FANOUT_AGENT_SVH

class csb_fanout_agent extends uvm_agent;

  csb_fanout_cfg        cfg;
  virtual csb_fanout_if vif;
  csb_fanout_responder  rsp;
  csb_fanout_monitor    mon;

  `uvm_component_utils(csb_fanout_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      cfg = csb_fanout_cfg::type_id::create("cfg");
      `uvm_warning(get_type_name(), "cfg not provided, using defaults (tgt_id=0)")
    end
    if (!uvm_config_db#(virtual csb_fanout_if)::get(
          this, "", $sformatf("fan_vif_%0d", cfg.tgt_id), vif))
      `uvm_fatal(get_type_name(),
                 $sformatf("config_db lookup for fan_vif_%0d failed", cfg.tgt_id))

    rsp = csb_fanout_responder::type_id::create("rsp", this);
    rsp.vif = vif;
    rsp.cfg = cfg;

    mon = csb_fanout_monitor::type_id::create("mon", this);
    mon.vif    = vif;
    mon.tgt_id = cfg.tgt_id;
  endfunction

endclass : csb_fanout_agent

`endif // CSB_FANOUT_AGENT_SVH
