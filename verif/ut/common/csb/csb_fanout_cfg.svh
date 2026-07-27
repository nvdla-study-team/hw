// -----------------------------------------------------------------------------
// csb_fanout_cfg : 扇出面 responder 每实例配置
//   - tgt_id       : 目的地块号（== csb_tgt_e 枚举值）
//   - rdy_gap_pct  : req_prdy 背压概率（百分比，0 = 恒 ready）
//   - gap_min/max  : 单次背压持续拍数范围
//   - resp_dly_min/max : 请求接受到响应驱出的额外延迟拍数范围
// -----------------------------------------------------------------------------
`ifndef CSB_FANOUT_CFG_SVH
`define CSB_FANOUT_CFG_SVH

class csb_fanout_cfg extends uvm_object;

  int unsigned tgt_id       = 0;
  int unsigned rdy_gap_pct  = 0;
  int unsigned gap_min      = 1;
  int unsigned gap_max      = 8;
  int unsigned resp_dly_min = 0;
  int unsigned resp_dly_max = 2;

  `uvm_object_utils(csb_fanout_cfg)

  function new(string name = "csb_fanout_cfg");
    super.new(name);
  endfunction

endclass : csb_fanout_cfg

`endif // CSB_FANOUT_CFG_SVH
