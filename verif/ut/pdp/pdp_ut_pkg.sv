// -----------------------------------------------------------------------------
// pdp_ut_pkg : pdp UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package pdp_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "pdp_scoreboard.svh"
  `include "pdp_env.svh"

  `include "pdp_csb_base_seq.svh"
  `include "pdp_t0_reg_seq.svh"

  `include "pdp_test_lib.svh"

endpackage : pdp_ut_pkg
