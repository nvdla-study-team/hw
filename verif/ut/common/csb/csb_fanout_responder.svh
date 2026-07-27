// -----------------------------------------------------------------------------
// csb_fanout_responder : 扇出面纯 reactive responder（core 域，无 sequencer）
//   - 握手线程：按 cfg 概率背压 req_prdy；pvld && prdy 拍解码 req_pd；
//       写（含 posted）更新本地 mem；读 / nposted 写压响应队列
//   - 响应线程：出队后延迟 resp_dly 拍，驱 resp_valid 单拍 +
//       resp_pd = {type, error=0, rdat}；读数据 = mem 命中值或
//       csb_default_pattern(tgt_id, addr)（scoreboard 可独立复算）
// -----------------------------------------------------------------------------
`ifndef CSB_FANOUT_RESPONDER_SVH
`define CSB_FANOUT_RESPONDER_SVH

class csb_fanout_responder extends uvm_component;

  virtual csb_fanout_if vif;
  csb_fanout_cfg        cfg;

  bit [31:0] mem [bit [15:0]];

  typedef struct {
    bit          rtype;   // resp_pd[33]: 0=读数据 1=写完成
    bit [31:0]   rdat;
    int unsigned dly;
  } resp_s;
  resp_s resp_q[$];

  `uvm_component_utils(csb_fanout_responder)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (vif == null)
      `uvm_fatal(get_type_name(), "csb_fanout_responder has no virtual interface")
    if (cfg == null)
      `uvm_fatal(get_type_name(), "csb_fanout_responder has no cfg")

    vif.rsp_cb.req_prdy   <= 1'b0;
    vif.rsp_cb.resp_valid <= 1'b0;
    vif.rsp_cb.resp_pd    <= '0;
    wait (vif.rstn === 1'b1);
    @(vif.rsp_cb);

    fork
      handshake_loop();
      response_loop();
    join
  endtask

  task handshake_loop();
    forever begin
      if (cfg.rdy_gap_pct > 0 && ($urandom_range(99) < cfg.rdy_gap_pct)) begin
        int unsigned gap = $urandom_range(cfg.gap_max, cfg.gap_min);
        vif.rsp_cb.req_prdy <= 1'b0;
        repeat (gap) @(vif.rsp_cb);
      end
      vif.rsp_cb.req_prdy <= 1'b1;
      @(vif.rsp_cb);
      if (vif.rsp_cb.req_pvld === 1'b1)
        take_req();
    end
  endtask

  function void take_req();
    bit [15:0] a;
    bit [31:0] d;
    bit        wr, np;
    resp_s     r;
    a  = vif.rsp_cb.req_pd[15:0];
    d  = vif.rsp_cb.req_pd[53:22];
    wr = vif.rsp_cb.req_pd[54];
    np = vif.rsp_cb.req_pd[55];
    if (wr) begin
      mem[a] = d;
      if (np) begin // nposted 写回写完成；posted 写无响应
        r.rtype = 1'b1;
        r.rdat  = '0;
        r.dly   = $urandom_range(cfg.resp_dly_max, cfg.resp_dly_min);
        resp_q.push_back(r);
      end
    end
    else begin
      r.rtype = 1'b0;
      r.rdat  = mem.exists(a) ? mem[a]
                              : csb_default_pattern(cfg.tgt_id, a);
      r.dly   = $urandom_range(cfg.resp_dly_max, cfg.resp_dly_min);
      resp_q.push_back(r);
    end
  endfunction

  task response_loop();
    resp_s r;
    forever begin
      @(vif.rsp_cb);
      while (resp_q.size() > 0) begin
        r = resp_q.pop_front();
        repeat (r.dly) @(vif.rsp_cb);
        vif.rsp_cb.resp_valid <= 1'b1;
        vif.rsp_cb.resp_pd    <= {r.rtype, 1'b0, r.rdat};
        @(vif.rsp_cb);
        vif.rsp_cb.resp_valid <= 1'b0;
        vif.rsp_cb.resp_pd    <= '0;
      end
    end
  endtask

endclass : csb_fanout_responder

`endif // CSB_FANOUT_RESPONDER_SVH
