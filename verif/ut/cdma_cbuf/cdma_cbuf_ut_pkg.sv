// -----------------------------------------------------------------------------
// cdma_cbuf_ut_pkg : cdma_cbuf UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package cdma_cbuf_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "cdma_layer_cfg.svh"
  `include "cdma_cbuf_refmodel.svh"
  `include "cdma_cbuf_scoreboard.svh"
  `include "cdma_cbuf_env.svh"

  `include "cdma_csb_base_seq.svh"
  `include "cdma_t0_reg_seq.svh"
  `include "cdma_layer_seq.svh"
  `include "cbuf_rd_list_seq.svh"

  `include "cdma_cbuf_test_lib.svh"

endpackage : cdma_cbuf_ut_pkg
