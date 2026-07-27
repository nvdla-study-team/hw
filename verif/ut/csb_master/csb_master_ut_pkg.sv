// -----------------------------------------------------------------------------
// csb_master_ut_pkg : csb_master UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package csb_master_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "csb_master_scoreboard.svh"
  `include "csb_master_env.svh"

  `include "csb_base_seq.svh"
  `include "csb_smoke_seq.svh"
  `include "csb_dummy_seq.svh"
  `include "csb_random_seq.svh"

  `include "csb_master_test_lib.svh"

endpackage : csb_master_ut_pkg
