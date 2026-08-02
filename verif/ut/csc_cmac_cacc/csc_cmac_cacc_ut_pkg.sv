// -----------------------------------------------------------------------------
// csc_cmac_cacc_ut_pkg : csc_cmac_cacc UT 用例 package（env + seqs + tests）
// -----------------------------------------------------------------------------
package csc_cmac_cacc_ut_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import nvdla_ut_pkg::*;

  `include "ccc_layer_cfg.svh"
  `include "ccc_refmodel.svh"
  `include "csc_cmac_cacc_scoreboard.svh"
  `include "csc_cmac_cacc_env.svh"

  `include "ccc_csb_base_seq.svh"
  `include "ccc_t0_reg_seq.svh"
  `include "ccc_layer_seq.svh"

  `include "csc_cmac_cacc_test_lib.svh"

endpackage : csc_cmac_cacc_ut_pkg
