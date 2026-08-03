// -----------------------------------------------------------------------------
// sdp_ut_pkg : sdp UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package sdp_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "sdp_scoreboard.svh"
  `include "sdp_env.svh"

  `include "sdp_csb_base_seq.svh"
  `include "sdp_t0_reg_seq.svh"

  `include "sdp_test_lib.svh"

endpackage : sdp_ut_pkg
