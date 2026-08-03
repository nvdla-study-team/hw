// -----------------------------------------------------------------------------
// cdp_ut_pkg : cdp UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package cdp_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "cdp_scoreboard.svh"
  `include "cdp_env.svh"

  `include "cdp_csb_base_seq.svh"
  `include "cdp_t0_reg_seq.svh"

  `include "cdp_test_lib.svh"

endpackage : cdp_ut_pkg
