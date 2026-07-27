// -----------------------------------------------------------------------------
// nvdla_ut_pkg : UT 平台唯一公共 package（复用层）
//   include 顺序 = 依赖顺序：types -> csb item/组件 -> dma/intr 骨架 -> base test
//   文末 typedef 强制参数化类特化一次，保证骨架真正走过编译（阶段2要求）
// -----------------------------------------------------------------------------
package nvdla_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "base/ut_types.svh"

  `include "csb/csb_seq_item.svh"
  `include "csb/csb_master_driver.svh"
  `include "csb/csb_master_monitor.svh"
  `include "csb/csb_master_agent.svh"
  `include "csb/csb_fanout_cfg.svh"
  `include "csb/csb_fanout_responder.svh"
  `include "csb/csb_fanout_monitor.svh"
  `include "csb/csb_fanout_agent.svh"

  `include "dma/dma_seq_item.svh"
  `include "dma/dma_slave_responder.svh"
  `include "dma/dma_slave_monitor.svh"
  `include "dma/dma_slave_agent.svh"

  `include "intr/intr_agent.svh"

  `include "base/ut_base_test.svh"

  // 阶段2 可实例化性证明：cdp 位宽（79/514/515）特化
  typedef dma_slave_agent     #(79, 514, 515) dma_slave_agent_cdp_t;
  typedef dma_slave_responder #(79, 514, 515) dma_slave_responder_cdp_t;
  typedef dma_slave_monitor   #(79, 514, 515) dma_slave_monitor_cdp_t;

endpackage : nvdla_ut_pkg
