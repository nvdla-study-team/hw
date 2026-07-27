// -----------------------------------------------------------------------------
// intr_agent : 中断 monitor-only agent（阶段2 骨架：编译 + 可实例化）
//   检测 intr 上升沿，经 analysis port 发布置位事件（bit=1）
//   virtual interface 经 config_db 键 "intr_vif" 获取；未绑定则空转
// -----------------------------------------------------------------------------
`ifndef INTR_AGENT_SVH
`define INTR_AGENT_SVH

class intr_agent extends uvm_agent;

  virtual intr_if vif;

  uvm_analysis_port #(bit) ap;
  int unsigned             n_rises;

  `uvm_component_utils(intr_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual intr_if)::get(this, "", "intr_vif", vif))
      `uvm_info(get_type_name(), "intr_vif not found, agent in skeleton mode", UVM_HIGH)
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit prev;
    if (vif == null) return;
    forever begin
      @(vif.mon_cb);
      if (vif.rstn !== 1'b1) begin
        prev = 1'b0;
        continue;
      end
      if (vif.mon_cb.intr === 1'b1 && !prev) begin
        n_rises++;
        ap.write(1'b1);
      end
      prev = (vif.mon_cb.intr === 1'b1);
    end
  endtask

endclass : intr_agent

`endif // INTR_AGENT_SVH
