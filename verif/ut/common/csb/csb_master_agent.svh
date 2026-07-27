// -----------------------------------------------------------------------------
// csb_master_agent : CSB 单口面 agent（driver + sequencer + monitor）
//   virtual interface 经 config_db 键 "csb_vif" 获取
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_AGENT_SVH
`define CSB_MASTER_AGENT_SVH

typedef uvm_sequencer #(csb_seq_item) csb_master_sequencer;

class csb_master_agent extends uvm_agent;

  virtual csb_if       vif;
  csb_master_driver    drv;
  csb_master_sequencer sqr;
  csb_master_monitor   mon;

  `uvm_component_utils(csb_master_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual csb_if)::get(this, "", "csb_vif", vif))
      `uvm_fatal(get_type_name(), "config_db lookup for csb_vif failed")
    mon = csb_master_monitor::type_id::create("mon", this);
    mon.vif = vif;
    if (get_is_active() == UVM_ACTIVE) begin
      drv = csb_master_driver::type_id::create("drv", this);
      sqr = csb_master_sequencer::type_id::create("sqr", this);
      drv.vif = vif;
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : csb_master_agent

`endif // CSB_MASTER_AGENT_SVH
