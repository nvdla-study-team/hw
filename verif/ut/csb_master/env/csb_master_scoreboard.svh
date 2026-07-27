// -----------------------------------------------------------------------------
// csb_master_scoreboard : 4 个 analysis imp（17 路 fanout 共用 fan_req/fan_rsp）
//   检查项：
//   1. 路由：mst 请求按 csb_target_of 预测 vs fanout 实际观测口；
//      预测为 dummy 的请求不得出现在任何 fanout 口
//   2. req_pd 字段还原（addr/wdat/write/nposted）+ 保留位 [21:16]/[62:56] == 0
//   3. 响应：读 -> mst rdata == fan rdat == 镜像 mem/default_pattern 复算值，
//      dummy 读 == 0；nposted 写 -> fan type==1 且 mst wr_complete；
//      posted 写不得有任何响应；resp error 位恒 0
//   依赖 driver 串行化带响应事务 => pending_rsp_q 深度 <= 1，跨域顺序有因果保证
//
//   保序模型（RTL 实测，random seed2 抓到）：core_req_prdy 恒 1，FIFO 每拍照常
//   pop 进各目的地各自的 1 级保持寄存器，所以 DUT 只保证【同一目的地口内】请求
//   有序；某口被背压时，后到的请求可先在其它口完成握手 => 预期队列必须按目的地
//   分开（exp_fan_q[NUM_CSB_TGT]），不能用全局 FIFO 序
//   同口覆盖风险（保持寄存器仅 1 级）由激励规避：见 csb_random_seq 尾距约束
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_SCOREBOARD_SVH
`define CSB_MASTER_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_mst_req)
`uvm_analysis_imp_decl(_mst_rsp)
`uvm_analysis_imp_decl(_fan_req)
`uvm_analysis_imp_decl(_fan_rsp)

class csb_master_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_mst_req #(csb_seq_item, csb_master_scoreboard) mst_req_imp;
  uvm_analysis_imp_mst_rsp #(csb_seq_item, csb_master_scoreboard) mst_rsp_imp;
  uvm_analysis_imp_fan_req #(csb_seq_item, csb_master_scoreboard) fan_req_imp;
  uvm_analysis_imp_fan_rsp #(csb_seq_item, csb_master_scoreboard) fan_rsp_imp;

  // 预期出现在扇出口的请求（非 dummy），按目的地分队列（DUT 仅同口保序）
  csb_seq_item exp_fan_q [NUM_CSB_TGT][$];
  // 等待 falcon 侧响应的请求（driver 串行化 => 深度 <= 1）
  csb_seq_item pending_rsp_q[$];
  // 镜像 mem：按 [tgt][字地址] 记写入值，读预期独立复算
  bit [31:0] mirror_mem [int unsigned][bit [15:0]];

  // 统计
  int unsigned n_mst_req, n_rd, n_wr_posted, n_wr_nposted;
  int unsigned n_fan_req [NUM_CSB_TGT];
  int unsigned n_fan_rsp, n_mst_rsp, n_dummy;

  `uvm_component_utils(csb_master_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mst_req_imp = new("mst_req_imp", this);
    mst_rsp_imp = new("mst_rsp_imp", this);
    fan_req_imp = new("fan_req_imp", this);
    fan_rsp_imp = new("fan_rsp_imp", this);
  endfunction

  // ---- 单口面：被接受的请求 ----
  function void write_mst_req(csb_seq_item t);
    t.tgt = csb_target_of(t.addr); // 独立预测（不信任 monitor 填值）
    n_mst_req++;
    if (!t.write)         n_rd++;
    else if (t.nposted)   n_wr_nposted++;
    else                  n_wr_posted++;
    if (t.tgt == CSB_TGT_DUMMY) n_dummy++;
    else                        exp_fan_q[t.tgt].push_back(t);
    if (t.expects_resp())       pending_rsp_q.push_back(t);
  endfunction

  // ---- 扇出面：某路实际观测到的请求 ----
  function void write_fan_req(csb_seq_item t);
    csb_seq_item exp;
    n_fan_req[t.tgt]++;
    if (exp_fan_q[t.tgt].size() == 0) begin
      // dummy 预测的请求出现在真实口 / misroute 都会落到这里
      `uvm_error(get_type_name(),
                 $sformatf("routing error: no request predicted for %s, but observed: %s",
                           t.tgt.name(), t.convert2string()))
      return;
    end
    exp = exp_fan_q[t.tgt].pop_front();
    if (t.addr !== exp.addr || t.wdat !== exp.wdat ||
        t.write !== exp.write || t.nposted !== exp.nposted)
      `uvm_error(get_type_name(),
                 $sformatf("req_pd field mismatch: exp {%s} obs {%s}",
                           exp.convert2string(), t.convert2string()))
    if (t.raw_req_pd[21:16] !== 6'h0 || t.raw_req_pd[62:56] !== 7'h0)
      `uvm_error(get_type_name(),
                 $sformatf("req_pd reserved bits nonzero: pd=0x%016h", t.raw_req_pd))
    if (t.write)
      mirror_mem[t.tgt][t.addr] = t.wdat;
    else begin // 读预期数据在 fan_req 时刻复算（此前所有写已按 FIFO 序观测到）
      exp.exp_rdat = (mirror_mem.exists(t.tgt) && mirror_mem[t.tgt].exists(t.addr))
                     ? mirror_mem[t.tgt][t.addr]
                     : csb_default_pattern(t.tgt, t.addr);
    end
  endfunction

  // ---- 扇出面：某路驱回的响应 ----
  function void write_fan_rsp(csb_seq_item t);
    csb_seq_item exp;
    n_fan_rsp++;
    if (pending_rsp_q.size() == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("unexpected fanout response on %s (no txn outstanding)",
                           t.tgt.name()))
      return;
    end
    exp = pending_rsp_q[0];
    if (exp.tgt == CSB_TGT_DUMMY) begin
      `uvm_error(get_type_name(),
                 $sformatf("fanout response on %s while outstanding txn targets dummy",
                           t.tgt.name()))
      return;
    end
    if (t.tgt != exp.tgt)
      `uvm_error(get_type_name(),
                 $sformatf("response port mismatch: outstanding txn targets %s, response on %s",
                           exp.tgt.name(), t.tgt.name()))
    if (t.resp_error !== 1'b0)
      `uvm_error(get_type_name(),
                 $sformatf("resp_pd error bit set on %s: pd=0x%09h", t.tgt.name(), t.raw_resp_pd))
    if (exp.write) begin // nposted 写
      if (t.resp_type !== 1'b1)
        `uvm_error(get_type_name(),
                   $sformatf("nposted write got read-type response on %s: %s",
                             t.tgt.name(), exp.convert2string()))
    end
    else begin // 读
      if (t.resp_type !== 1'b0)
        `uvm_error(get_type_name(),
                   $sformatf("read got write-type response on %s: %s",
                             t.tgt.name(), exp.convert2string()))
      else if (t.rdat !== exp.exp_rdat)
        `uvm_error(get_type_name(),
                   $sformatf("fanout read data mismatch on %s: exp=0x%08h obs=0x%08h (%s)",
                             t.tgt.name(), exp.exp_rdat, t.rdat, exp.convert2string()))
    end
    exp.got_fan_rsp = 1'b1;
  endfunction

  // ---- 单口面：回到 falcon 侧的响应 ----
  function void write_mst_rsp(csb_seq_item t);
    csb_seq_item exp;
    n_mst_rsp++;
    if (pending_rsp_q.size() == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("unexpected master-side response (rvalid=%0b wr_complete=%0b), posted write must not respond",
                           t.got_rvalid, t.got_wr_complete))
      return;
    end
    exp = pending_rsp_q.pop_front();
    if (exp.write) begin // nposted 写
      if (!t.got_wr_complete)
        `uvm_error(get_type_name(),
                   $sformatf("nposted write got rvalid instead of wr_complete: %s",
                             exp.convert2string()))
    end
    else begin // 读
      if (!t.got_rvalid)
        `uvm_error(get_type_name(),
                   $sformatf("read got wr_complete instead of rvalid: %s",
                             exp.convert2string()))
      else begin
        bit [31:0] exp_data;
        exp_data = (exp.tgt == CSB_TGT_DUMMY) ? 32'h0 : exp.exp_rdat;
        if (t.rdat !== exp_data)
          `uvm_error(get_type_name(),
                     $sformatf("master read data mismatch: exp=0x%08h obs=0x%08h (%s)",
                               exp_data, t.rdat, exp.convert2string()))
      end
    end
    if (exp.tgt != CSB_TGT_DUMMY && !exp.got_fan_rsp)
      `uvm_error(get_type_name(),
                 $sformatf("master response arrived without fanout response: %s",
                           exp.convert2string()))
  endfunction

  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (exp_fan_q[i])
      if (exp_fan_q[i].size() != 0) begin
        csb_tgt_e tt = csb_tgt_e'(i);
        `uvm_error(get_type_name(),
                   $sformatf("%0d request(s) never reached fanout port %s, first: %s",
                             exp_fan_q[i].size(), tt.name(),
                             exp_fan_q[i][0].convert2string()))
        exp_fan_q[i].delete();
      end
    if (pending_rsp_q.size() != 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("%0d txn(s) never got master-side response, first: %s",
                           pending_rsp_q.size(), pending_rsp_q[0].convert2string()))
      pending_rsp_q.delete();
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    string s;
    super.report_phase(phase);
    s = $sformatf("\n  mst_req=%0d (rd=%0d wr_posted=%0d wr_nposted=%0d dummy=%0d)",
                  n_mst_req, n_rd, n_wr_posted, n_wr_nposted, n_dummy);
    s = {s, $sformatf("\n  fan_rsp=%0d mst_rsp=%0d", n_fan_rsp, n_mst_rsp)};
    foreach (n_fan_req[i])
      if (n_fan_req[i] > 0) begin
        csb_tgt_e tt = csb_tgt_e'(i);
        s = {s, $sformatf("\n  fan_req[%-8s]=%0d", tt.name(), n_fan_req[i])};
      end
    `uvm_info(get_type_name(), {"scoreboard stats:", s}, UVM_LOW)
  endfunction

endclass : csb_master_scoreboard

`endif // CSB_MASTER_SCOREBOARD_SVH
