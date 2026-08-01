// -----------------------------------------------------------------------------
// cdma_cbuf_test_lib : base / t0_reg
//   - base   : 建 env，run_phase 抓 objection（drain 1us），run_seqs() 留空钩子
//   - t0_reg : T0 寄存器冒烟（默认测试）
// -----------------------------------------------------------------------------
`ifndef CDMA_CBUF_TEST_LIB_SVH
`define CDMA_CBUF_TEST_LIB_SVH

class cdma_cbuf_base_test extends ut_base_test;

  cdma_cbuf_env env;

  `uvm_component_utils(cdma_cbuf_base_test)

  function new(string name = "cdma_cbuf_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cdma_cbuf_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "cdma_cbuf test body");
    phase.get_objection().set_drain_time(this, 1us);
    run_seqs();
    phase.drop_objection(this, "cdma_cbuf test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : cdma_cbuf_base_test


class cdma_cbuf_t0_reg_test extends cdma_cbuf_base_test;

  `uvm_component_utils(cdma_cbuf_t0_reg_test)

  function new(string name = "cdma_cbuf_t0_reg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    cdma_t0_reg_seq t0;
    t0 = cdma_t0_reg_seq::type_id::create("t0");
    t0.start(env.csb_agt.sqr);
  endtask

endclass : cdma_cbuf_t0_reg_test


// ---------------------------------------------------------------------------
// layer base：单层 DC 全流程（flush 等待→编程→set_layer→op_en→等 done 中断→
// drain→cbuf 读回→final_check），T1/T2/T3 只差 make_cfg/旋钮
// ---------------------------------------------------------------------------
class cdma_cbuf_layer_base_test extends cdma_cbuf_base_test;

  cdma_layer_cfg cfg;

  // dma responder 扰动旋钮（T3 覆盖）
  int unsigned rsp_dly_min = 0;
  int unsigned rsp_dly_max = 2;
  int unsigned req_gap_pct = 0;
  int unsigned req_gap_min = 1;
  int unsigned req_gap_max = 4;

  `uvm_component_utils(cdma_cbuf_layer_base_test)

  function new(string name = "cdma_cbuf_layer_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // 子类必须给 cfg 赋值
  virtual function void make_cfg();
    `uvm_fatal(get_type_name(), "make_cfg not overridden")
  endfunction

  function dma_slave_responder_cdp_t dat_rsp();
    return cfg.dat_ram_mc ? env.dat_mc_agt.rsp : env.dat_cv_agt.rsp;
  endfunction
  function dma_slave_responder_cdp_t wt_rsp();
    return cfg.wt_ram_mc ? env.wt_mc_agt.rsp : env.wt_cv_agt.rsp;
  endfunction

  virtual function void apply_knobs();
    dma_slave_responder_cdp_t rq[4];
    rq[0] = env.dat_mc_agt.rsp; rq[1] = env.dat_cv_agt.rsp;
    rq[2] = env.wt_mc_agt.rsp;  rq[3] = env.wt_cv_agt.rsp;
    foreach (rq[i]) begin
      rq[i].rd_rsp_dly_min = rsp_dly_min;
      rq[i].rd_rsp_dly_max = rsp_dly_max;
      rq[i].req_gap_pct    = req_gap_pct;
      rq[i].req_gap_min    = req_gap_min;
      rq[i].req_gap_max    = req_gap_max;
    end
  endfunction

  // 默认：dat 面预载伪随机镜像，wt 用 responder 默认 addr 哈希 pattern
  virtual function void preload_mem();
    bit [7:0] blob[];
    int unsigned n = cfg.csurf() * cfg.surf_stride;
    blob = new[n];
    foreach (blob[i]) blob[i] = 8'((i * 37) ^ (i >> 6) ^ 8'hC3);
    dat_rsp().load_bytes(cfg.dat_addr, blob);
  endfunction

  // ---- 可复用步骤 ----
  protected task program_layer(cdma_layer_cfg c);
    cdma_layer_seq prog;
    prog = cdma_layer_seq::type_id::create("prog");
    prog.cfg = c; prog.do_program = 1; prog.do_enable = 0;
    prog.start(env.csb_agt.sqr);
  endtask

  protected task enable_layer(cdma_layer_cfg c);
    cdma_layer_seq go;
    go = cdma_layer_seq::type_id::create("go");
    go.cfg = c; go.do_program = 0; go.do_enable = 1;
    go.start(env.csb_agt.sqr);
  endtask

  // grp：done 中断位（=寄存器组号）
  protected task wait_done_intr(bit grp, int unsigned max_us = 1000);
    int unsigned t = 0;
    int unsigned nd, nw;
    do begin
      nd = grp ? env.intr_dat1_agt.n_rises : env.intr_dat0_agt.n_rises;
      nw = grp ? env.intr_wt1_agt.n_rises  : env.intr_wt0_agt.n_rises;
      if (nd > 0 && nw > 0) break;
      #1us;
      t++;
    end while (t <= max_us);
    if (!(nd > 0 && nw > 0))
      `uvm_error(get_type_name(),
                 $sformatf("group%0d done intr timeout (dat=%0d wt=%0d)", grp, nd, nw))
  endtask

  // csc 侧读回 + 层末总检（dat 口、wt 口串行，规避同拍 hazard）
  protected task readback_and_check();
    cbuf_rd_list_seq rl;
    bit [11:0]       q[$];
    env.sb.rm.get_dat_addr_list(q);
    rl = cbuf_rd_list_seq::type_id::create("rl_dat");
    rl.addr_q = q;
    rl.start(env.dat_rd_agt.sqr);
    env.sb.rm.get_wt_addr_list(q);
    rl = cbuf_rd_list_seq::type_id::create("rl_wt");
    rl.addr_q = q;
    rl.start(env.wt_rd_agt.sqr);
    #500ns; // 6 拍读延迟收尾
    env.sb.final_check();
  endtask

  virtual task run_seqs();
    make_cfg();
    cfg.check_supported();
    `uvm_info(get_type_name(), $sformatf("layer cfg: %s", cfg.convert2string()), UVM_LOW)
    apply_knobs();
    preload_mem();

    program_layer(cfg);                            // 内含 flush_done 轮询
    env.sb.set_layer(cfg, dat_rsp(), wt_rsp());
    enable_layer(cfg);
    wait_done_intr(0);
    #2us; // drain：updt 出口 +9 拍 / cvt-cbuf 写流水尾
    readback_and_check();
  endtask

endclass : cdma_cbuf_layer_base_test


// T1：int16 定向主冒烟（csurf=2 尾双面打包、MC 双路、grain=2）
class cdma_cbuf_t1_smoke_test extends cdma_cbuf_layer_base_test;

  `uvm_component_utils(cdma_cbuf_t1_smoke_test)

  function new(string name = "cdma_cbuf_t1_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void make_cfg();
    cfg = cdma_layer_cfg::type_id::create("cfg");
    cfg.is_int8     = 0;            // int16
    cfg.width       = 4;
    cfg.height      = 4;
    cfg.channel     = 32;           // csurf=2, eps=2
    cfg.dat_ram_mc  = 1;
    cfg.dat_addr    = 64'h4000;
    cfg.line_stride = 128;          // W*32
    cfg.surf_stride = 512;
    cfg.line_packed = 1;
    cfg.grain       = 2;
    cfg.data_bank   = 0;
    cfg.wt_ram_mc   = 1;
    cfg.wt_addr     = 64'h10_0000;
    cfg.bpk         = 64;
    cfg.kernels     = 16;           // int16 单满组
    cfg.weight_bank = 0;
  endfunction

endclass : cdma_cbuf_t1_smoke_test


// T2：int8 + 非 256B 对齐首笔 + 奇数 32B 尾块（激 rsp mask=2'b01 与奇 size 请求）
class cdma_cbuf_t2_odd_tail_test extends cdma_cbuf_layer_base_test;

  `uvm_component_utils(cdma_cbuf_t2_odd_tail_test)

  function new(string name = "cdma_cbuf_t2_odd_tail_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void make_cfg();
    cfg = cdma_layer_cfg::type_id::create("cfg");
    cfg.is_int8     = 1;            // int8
    cfg.width       = 6;            // csurf==1 要求偶 W；末 entry 半写
    cfg.height      = 3;
    cfg.channel     = 32;           // csurf=1, eps=2
    cfg.dat_ram_mc  = 1;
    cfg.dat_addr    = 64'h8020;     // 256B 块内 atom 偏移 1 -> 首笔 7 atom（奇）
    cfg.line_stride = 192;          // W*32
    cfg.surf_stride = 576;
    cfg.line_packed = 1;
    cfg.grain       = 3;            // 单 grain 全层
    cfg.data_bank   = 0;
    cfg.wt_ram_mc   = 1;
    cfg.wt_addr     = 64'h10_0060;  // atom 偏移 3 -> 首笔 5 atom（奇）
    cfg.bpk         = 48;
    cfg.kernels     = 8;            // int8 尾组 8 kernel，384B=3 entry
    cfg.weight_bank = 0;
  endfunction

  // 不预载：全走 responder 默认 addr 哈希 pattern（refmodel 同公式）
  virtual function void preload_mem();
  endfunction

endclass : cdma_cbuf_t2_odd_tail_test


// T3：响应扰动随机（延迟/req 背压/多笔在途），层参数在支持面内随机，3 seeds
class cdma_cbuf_t3_random_test extends cdma_cbuf_layer_base_test;

  `uvm_component_utils(cdma_cbuf_t3_random_test)

  function new(string name = "cdma_cbuf_t3_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(2ms, 1);
    rsp_dly_min = 0;
    rsp_dly_max = 6;
    req_gap_pct = 30;
    req_gap_min = 1;
    req_gap_max = 4;
  endfunction

  virtual function void make_cfg();
    cfg = cdma_layer_cfg::type_id::create("cfg");
    if (!cfg.randomize() with { width <= 8; height <= 4; channel <= 128; })
      `uvm_fatal(get_type_name(), "cfg randomize failed")
  endfunction

endclass : cdma_cbuf_t3_random_test


// T5：buffer-full 停等/释放——设计合同是单层足迹必须装进 data bank（RTL 配置
// 断言 "Error config! data bank is not big enough!"，dc.v is_running &
// data_bank*256 < eps*H 即触发，T5 初版实测证实），真实停等场景是**跨层**：
// 层 0 占住 192/256 不释放 -> 层 1（同 192）取满剩余 64 entry 后 free=0 停等；
// 显式验证：无释放时层 1 不完成且 DMA 请求停发；随后分批释放层 0 -> 层 1 恢复
// 完成，四面全绿（层 1 期望按环形 wr_idx 基准 192 建模，dat/wt 指针跨层不复位）
class cdma_cbuf_t5_buffer_full_test extends cdma_cbuf_layer_base_test;

  `uvm_component_utils(cdma_cbuf_t5_buffer_full_test)

  function new(string name = "cdma_cbuf_t5_buffer_full_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(3ms, 1);
  endfunction

  virtual function void make_cfg();
    cfg = cdma_layer_cfg::type_id::create("cfg");
    cfg.is_int8     = 0;            // int16
    cfg.width       = 8;
    cfg.height      = 48;
    cfg.channel     = 32;           // csurf=2, eps=4 -> 足迹 192（容量 256）
    cfg.dat_ram_mc  = 1;
    cfg.dat_addr    = 64'h4000;
    cfg.line_stride = 256;          // W*32
    cfg.surf_stride = 48 * 256;
    cfg.line_packed = 1;
    cfg.grain       = 4;
    cfg.data_bank   = 0;            // 1 bank = 256 entry
    cfg.wt_ram_mc   = 1;
    cfg.wt_addr     = 64'h10_0000;
    cfg.bpk         = 64;
    cfg.kernels     = 16;
    cfg.weight_bank = 0;
  endfunction

  virtual task run_seqs();
    cdma_layer_cfg    cfg1;
    cdma_csb_base_seq ptr;
    int unsigned      n_req_frozen, released;

    make_cfg();
    cfg.check_supported();
    apply_knobs();

    // ---- 层 0：正常跑完但不释放（占住 192 entry）----
    program_layer(cfg);
    env.sb.set_layer(cfg, dat_rsp(), wt_rsp());
    enable_layer(cfg);
    wait_done_intr(0);
    #2us;
    readback_and_check();

    // ---- 层 1：producer=1，free 只剩 64 -> 中途停等 ----
    cfg1 = cdma_layer_cfg::type_id::create("cfg1");
    cfg1.is_int8     = cfg.is_int8;     cfg1.width       = cfg.width;
    cfg1.height      = cfg.height;      cfg1.channel     = cfg.channel;
    cfg1.dat_ram_mc  = cfg.dat_ram_mc;  cfg1.line_stride = cfg.line_stride;
    cfg1.surf_stride = cfg.surf_stride; cfg1.line_packed = cfg.line_packed;
    cfg1.grain       = cfg.grain;       cfg1.data_bank   = cfg.data_bank;
    cfg1.wt_ram_mc   = cfg.wt_ram_mc;   cfg1.bpk         = cfg.bpk;
    cfg1.kernels     = cfg.kernels;     cfg1.weight_bank = cfg.weight_bank;
    cfg1.dat_addr = 64'h4_0000;
    cfg1.wt_addr  = 64'h10_8000;

    ptr = cdma_csb_base_seq::type_id::create("ptr");
    ptr.set_item_context(null, env.csb_agt.sqr);
    ptr.csb_write(12'h004, 32'h1);      // S_POINTER.producer=1
    program_layer(cfg1);
    cfg = cfg1;                         // dat_rsp()/wt_rsp() 取层 1 选路
    env.sb.set_layer(cfg1, dat_rsp(), wt_rsp(),
                     /*dat_wr_base*/ 192, /*wt_half_base*/ 16); // 层0: 192 entry / 16 半entry
    enable_layer(cfg1);

    // 停等验证：无释放 20us，dat 不得完成；随后 10us 请求数必须冻结
    #20us;
    if (env.intr_dat1_agt.n_rises != 0)
      `uvm_error(get_type_name(), "layer1 dat done without any release -- stall not engaged")
    n_req_frozen = env.sb.n_dat_req;
    #10us;
    if (env.sb.n_dat_req != n_req_frozen)
      `uvm_error(get_type_name(),
                 $sformatf("dat requests continued while buffer full (%0d -> %0d)",
                           n_req_frozen, env.sb.n_dat_req))
    else
      `uvm_info(get_type_name(),
                $sformatf("stall confirmed: dat req frozen at %0d", n_req_frozen), UVM_LOW)

    // 分批释放层 0 足迹（16 entry/4 slice 一批，共 192/48）-> 层 1 恢复
    released = 0;
    while (released < 192) begin
      env.sc_stub.send_dat_release(12'd16, 12'd4);
      released += 16;
      #200ns;
    end
    wait_done_intr(1);
    #2us;
    readback_and_check();
  endtask

endclass : cdma_cbuf_t5_buffer_full_test


// T6：ping-pong 双层——D0+D1 背靠背两层（同 bank 配置，层间无 pending），
// 校验 done 中断 bit0/bit1 各一次、consumer 两次翻转、S_STATUS 组状态、
// producer 影子编程（d0 运行中编 d1）。数据面 scoreboard 入 passive 模式
// （多层连跑的写流/记账重叠，Wave3 扩展多层 refmodel 后再开）
class cdma_cbuf_t6_pingpong_test extends cdma_cbuf_layer_base_test;

  `uvm_component_utils(cdma_cbuf_t6_pingpong_test)

  function new(string name = "cdma_cbuf_t6_pingpong_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void make_cfg();
    cfg = cdma_layer_cfg::type_id::create("cfg");
    cfg.is_int8     = 0;
    cfg.width       = 4;
    cfg.height      = 8;
    cfg.channel     = 32;           // csurf=2, eps=2
    cfg.dat_ram_mc  = 1;
    cfg.dat_addr    = 64'h4000;
    cfg.line_stride = 128;
    cfg.surf_stride = 1024;
    cfg.line_packed = 1;
    cfg.grain       = 2;
    cfg.data_bank   = 0;
    cfg.wt_ram_mc   = 1;
    cfg.wt_addr     = 64'h10_0000;
    cfg.bpk         = 64;
    cfg.kernels     = 16;
    cfg.weight_bank = 0;
  endfunction

  virtual task run_seqs();
    cdma_layer_seq   prog, go;
    cdma_csb_base_seq rdseq;
    cdma_layer_cfg   cfg1;
    bit [31:0]       rd;
    int unsigned     t;

    make_cfg();
    env.sb.passive = 1'b1; // 双层连跑：数据面吸收，只测控制机制
    apply_knobs();

    // ---- 层 0（producer=0）----
    prog = cdma_layer_seq::type_id::create("prog0");
    prog.cfg = cfg; prog.do_program = 1; prog.do_enable = 0;
    prog.start(env.csb_agt.sqr);
    go = cdma_layer_seq::type_id::create("go0");
    go.cfg = cfg; go.do_program = 0; go.do_enable = 1;
    go.start(env.csb_agt.sqr);

    // ---- 切 producer=1，d0 运行期间编层 1（同 bank，不同地址）----
    cfg1 = cdma_layer_cfg::type_id::create("cfg1");
    cfg1.is_int8     = cfg.is_int8;     cfg1.width       = cfg.width;
    cfg1.height      = cfg.height;      cfg1.channel     = cfg.channel;
    cfg1.dat_ram_mc  = cfg.dat_ram_mc;  cfg1.line_stride = cfg.line_stride;
    cfg1.surf_stride = cfg.surf_stride; cfg1.line_packed = cfg.line_packed;
    cfg1.grain       = cfg.grain;       cfg1.data_bank   = cfg.data_bank;
    cfg1.wt_ram_mc   = cfg.wt_ram_mc;   cfg1.bpk         = cfg.bpk;
    cfg1.kernels     = cfg.kernels;     cfg1.weight_bank = cfg.weight_bank;
    cfg1.dat_addr = 64'h2_0000;
    cfg1.wt_addr  = 64'h10_8000;
    rdseq = cdma_csb_base_seq::type_id::create("ptr");
    rdseq.set_item_context(null, env.csb_agt.sqr); // 直呼 csb_write/read 用
    rdseq.csb_write(12'h004, 32'h1); // S_POINTER.producer=1
    prog = cdma_layer_seq::type_id::create("prog1");
    prog.cfg = cfg1; prog.do_program = 1; prog.do_enable = 0;
    prog.start(env.csb_agt.sqr);
    go = cdma_layer_seq::type_id::create("go1");
    go.cfg = cfg1; go.do_program = 0; go.do_enable = 1;
    go.start(env.csb_agt.sqr);

    // 若层 0 尚在跑：status_0=1(running) 时应有 status_1=2(pending)
    rdseq.csb_read(12'h000, rd);
    if (rd[1:0] == 2'd1 && rd[17:16] != 2'd2)
      `uvm_error(get_type_name(),
                 $sformatf("S_STATUS group0 running but group1 not pending: 0x%08h", rd))

    // ---- 等两组 done 中断（bit0 后 bit1）----
    t = 0;
    while (!(env.intr_dat0_agt.n_rises > 0 && env.intr_wt0_agt.n_rises > 0)) begin
      #1us; t++;
      if (t > 1000) begin `uvm_error(get_type_name(), "group0 done intr timeout") break; end
    end
    t = 0;
    while (!(env.intr_dat1_agt.n_rises > 0 && env.intr_wt1_agt.n_rises > 0)) begin
      #1us; t++;
      if (t > 1000) begin `uvm_error(get_type_name(), "group1 done intr timeout") break; end
    end
    #2us;

    // ---- 终态校验 ----
    if (env.intr_dat0_agt.n_rises != 1 || env.intr_wt0_agt.n_rises != 1 ||
        env.intr_dat1_agt.n_rises != 1 || env.intr_wt1_agt.n_rises != 1)
      `uvm_error(get_type_name(),
                 $sformatf("done intr counts dat0/wt0/dat1/wt1 = %0d/%0d/%0d/%0d (all should be 1)",
                           env.intr_dat0_agt.n_rises, env.intr_wt0_agt.n_rises,
                           env.intr_dat1_agt.n_rises, env.intr_wt1_agt.n_rises))
    rdseq.csb_read(12'h004, rd); // S_POINTER：consumer 翻两次回 0，producer 保持 1
    if (rd[16] != 1'b0)
      `uvm_error(get_type_name(), $sformatf("consumer should be back to 0: S_POINTER=0x%08h", rd))
    rdseq.csb_read(12'h000, rd); // S_STATUS：两组均 idle
    if (rd !== 32'h0)
      `uvm_error(get_type_name(), $sformatf("S_STATUS not idle after both done: 0x%08h", rd))
    `uvm_info(get_type_name(), "ping-pong double layer done", UVM_LOW)
  endtask

endclass : cdma_cbuf_t6_pingpong_test

`endif // CDMA_CBUF_TEST_LIB_SVH
