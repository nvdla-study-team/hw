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

  `include "cbuf/cbuf_wr_item.svh"
  `include "cbuf/cbuf_wr_monitor.svh"
  `include "cbuf/cbuf_rd_item.svh"
  `include "cbuf/cbuf_rd_agent.svh"
  `include "cbuf/cbuf_model.svh"

  `include "cdma_sc/cdma_sc_item.svh"
  `include "cdma_sc/cdma_sc_stub.svh"
  `include "cdma_sc/csc_cdma_stub.svh"

  `include "sdp/sdp_item.svh"
  `include "sdp/sdp_sink_stub.svh"
  `include "sdp/sdp_source_stub.svh"

  `include "sdp2pdp/sdp2pdp_item.svh"
  `include "sdp2pdp/sdp2pdp_sink_stub.svh"
  `include "sdp2pdp/sdp2pdp_source_stub.svh"

  `include "intr/intr_agent.svh"

  `include "base/ut_base_test.svh"

  // 阶段2 可实例化性证明：cdp 位宽（79/514/515）特化（cdma 四路 DMA 位宽相同，复用）
  typedef dma_slave_agent     #(79, 514, 515) dma_slave_agent_cdp_t;
  typedef dma_slave_responder #(79, 514, 515) dma_slave_responder_cdp_t;
  typedef dma_slave_monitor   #(79, 514, 515) dma_slave_monitor_cdp_t;

  // cbuf 写口两形态（dat 1024b/hsel2、wt 512b/hsel1）与读口三形态（dat/wt=12、wmb=8）
  typedef cbuf_wr_monitor #(1024, 2) cbuf_wr_monitor_dat_t;
  typedef cbuf_wr_monitor #(512, 1)  cbuf_wr_monitor_wt_t;
  typedef cbuf_rd_agent   #(12)      cbuf_rd_agent_12_t;
  typedef cbuf_rd_agent   #(8)       cbuf_rd_agent_8_t;
  typedef cbuf_rd_driver  #(12)      cbuf_rd_driver_12_t;
  typedef cbuf_rd_driver  #(8)       cbuf_rd_driver_8_t;
  typedef cbuf_rd_monitor #(12)      cbuf_rd_monitor_12_t;
  typedef cbuf_rd_monitor #(8)       cbuf_rd_monitor_8_t;

endpackage : nvdla_ut_pkg
