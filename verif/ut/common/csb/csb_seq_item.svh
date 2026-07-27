// -----------------------------------------------------------------------------
// csb_seq_item : CSB 事务，单口面与扇出面共用一套 item
//   - rand 域       : 请求内容（addr/wdat/write/nposted）+ 发起前空闲拍数
//   - 回填域        : driver / monitor 观测到的响应
//   - 扇出观测域    : fanout monitor 填 tgt/raw_pd/resp_*
//   - scoreboard 域 : exp_rdat / got_fan_rsp 记账
//   expects_resp() = !write || nposted（读与 nposted 写有响应，posted 写没有）
// -----------------------------------------------------------------------------
`ifndef CSB_SEQ_ITEM_SVH
`define CSB_SEQ_ITEM_SVH

class csb_seq_item extends uvm_sequence_item;

  // ---- 请求（随机域） ----
  rand bit [15:0]      addr;        // 字地址
  rand bit [31:0]      wdat;
  rand bit             write;
  rand bit             nposted;
  rand int unsigned    idle_before; // 发起前 falcon 空闲拍数

  constraint idle_c { soft idle_before inside {[0:5]}; } // soft：序列可加大尾距

  // ---- 单口面回填域（driver / master monitor 填） ----
  bit [31:0] rdat;            // 读回数据
  bit        got_rvalid;      // 观测到 nvdla2csb_valid
  bit        got_wr_complete; // 观测到 nvdla2csb_wr_complete
  bit        timed_out;       // driver 等响应超时

  // ---- 扇出面观测域（fanout monitor 填） ----
  csb_tgt_e  tgt;             // 观测口 / 预测目的地
  bit [62:0] raw_req_pd;
  bit [33:0] raw_resp_pd;
  bit        resp_type;       // resp_pd[33] 0=读数据 1=写完成
  bit        resp_error;      // resp_pd[32]

  // ---- scoreboard 记账域 ----
  bit [31:0] exp_rdat;        // 预测读回数据（fan_req 时刻由镜像 mem 复算）
  bit        got_fan_rsp;     // 已观测到对应扇出面响应

  `uvm_object_utils(csb_seq_item)

  function new(string name = "csb_seq_item");
    super.new(name);
  endfunction

  function bit expects_resp();
    return (!write) || nposted;
  endfunction

  virtual function string convert2string();
    return $sformatf("%s addr=0x%04h wdat=0x%08h nposted=%0b idle=%0d tgt=%s rdat=0x%08h",
                     write ? "WR" : "RD", addr, wdat, nposted, idle_before,
                     tgt.name(), rdat);
  endfunction

endclass : csb_seq_item

`endif // CSB_SEQ_ITEM_SVH
