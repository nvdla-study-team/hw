// -----------------------------------------------------------------------------
// dma_slave_agent : DMA slave agent（参数化，阶段2 骨架：编译 + 可实例化）
//   virtual interface 经 config_db 键 "dma_vif"（可带实例名前缀）获取；
//   未绑定 vif 时子组件进 skeleton 空转模式，不报错——方便先挂骨架后接线。
// -----------------------------------------------------------------------------
`ifndef DMA_SLAVE_AGENT_SVH
`define DMA_SLAVE_AGENT_SVH

class dma_slave_agent #(
  int RD_REQ_W = 79,
  int RD_RSP_W = 514,
  int WR_REQ_W = 515
) extends uvm_agent;

  typedef dma_slave_agent #(RD_REQ_W, RD_RSP_W, WR_REQ_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual dma_if #(RD_REQ_W, RD_RSP_W, WR_REQ_W) vif_t;
  typedef dma_slave_responder #(RD_REQ_W, RD_RSP_W, WR_REQ_W) responder_t;
  typedef dma_slave_monitor   #(RD_REQ_W, RD_RSP_W, WR_REQ_W) monitor_t;

  vif_t       vif;
  responder_t rsp;
  monitor_t   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(vif_t)::get(this, "", "dma_vif", vif))
      `uvm_info(get_type_name(), "dma_vif not found, agent in skeleton mode", UVM_HIGH)
    rsp = responder_t::type_id::create("rsp", this);
    rsp.vif = vif;
    mon = monitor_t::type_id::create("mon", this);
    mon.vif = vif;
  endfunction

endclass : dma_slave_agent

`endif // DMA_SLAVE_AGENT_SVH
