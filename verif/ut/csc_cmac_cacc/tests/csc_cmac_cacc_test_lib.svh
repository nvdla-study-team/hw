// -----------------------------------------------------------------------------
// csc_cmac_cacc_test_lib
//   - base       : 建 env，objection + run_seqs 钩子
//   - t0_reg     : T0 四单元寄存器冒烟
//   - layer base : 单层全流程（预载 -> 编程 -> op_en 链 -> pending 握手 ->
//                  updt -> 等 intr -> final_check），激励顺序合同 = 方案书 4.4：
//                  **pending_req 有效期内绝不驱 updt**（sg.v:8344/:8390 静默清零，
//                  层账短斤缺两即挂死）；op_en 从下游到上游
//   - T1 conv    : int8 小层端到端（C 多轮、beat 序校准载体）
//   - T2 clip    : int16 clip_truncate 边角扫 + sat_count 对账
//   - T3 random  : 随机层 + sdp 随机背压 + 长停 + dat updt 随机拆分 x3 seeds
//   - T5 khalf   : int8 K=17-32 双半 + 尾 kernel mask + C 深迭代 + int16 小 K
//   - T6 pingpong: 双层乒乓（同 bank 免 pending / 换 bank 二次 pending、
//                  中断 toggle 交替、S_STATUS/consumer、逐层数据判分）
// -----------------------------------------------------------------------------
`ifndef CSC_CMAC_CACC_TEST_LIB_SVH
`define CSC_CMAC_CACC_TEST_LIB_SVH

class csc_cmac_cacc_base_test extends ut_base_test;

  csc_cmac_cacc_env env;

  `uvm_component_utils(csc_cmac_cacc_base_test)

  function new(string name = "csc_cmac_cacc_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = csc_cmac_cacc_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this, "csc_cmac_cacc test body");
    phase.get_objection().set_drain_time(this, 1us);
    run_seqs();
    phase.drop_objection(this, "csc_cmac_cacc test body");
  endtask

  virtual task run_seqs();
  endtask

endclass : csc_cmac_cacc_base_test


class csc_cmac_cacc_t0_reg_test extends csc_cmac_cacc_base_test;

  `uvm_component_utils(csc_cmac_cacc_t0_reg_test)

  function new(string name = "csc_cmac_cacc_t0_reg_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_seqs();
    ccc_t0_reg_seq t0;
    t0 = ccc_t0_reg_seq::type_id::create("t0");
    t0.start(env.csb_agt.sqr);
  endtask

endclass : csc_cmac_cacc_t0_reg_test


// ---------------------------------------------------------------------------
// layer base：单层全流程骨架，T1/T2/T3/T5/T6 复用 run_layer()
// ---------------------------------------------------------------------------
class csc_cmac_cacc_layer_base_test extends csc_cmac_cacc_base_test;

  ccc_layer_cfg cfg;

  int unsigned n_layers_done;      // 全局层计数（intr toggle 位预测）
  int unsigned n_updt_chunks = 1;  // dat updt 拆分份数（T3 随机）
  bit          inject_pending_updt = 1'b0; // T3：pending 期注入一笔（应被丢弃）
  // 跨层 cbuf 环形指针（同 bank 连续层 CSC 读指针不复位；PEND 清账归零）
  int unsigned dat_entry_base;
  int unsigned wt_entry_base;

  `uvm_component_utils(csc_cmac_cacc_layer_base_test)

  function new(string name = "csc_cmac_cacc_layer_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void make_cfg();
    `uvm_fatal(get_type_name(), "make_cfg not overridden")
  endfunction

  // ---- 步骤：producer 指针选组（4 单元同步）----
  protected task select_group(bit grp);
    ccc_csb_base_seq s = ccc_csb_base_seq::type_id::create("ptr");
    s.set_item_context(null, env.csb_agt.sqr);
    s.csb_write(CSB_TGT_CSC,    12'h004, 32'(grp));
    s.csb_write(CSB_TGT_CMAC_A, 12'h004, 32'(grp));
    s.csb_write(CSB_TGT_CMAC_B, 12'h004, 32'(grp));
    s.csb_write(CSB_TGT_CACC,   12'h004, 32'(grp));
  endtask

  protected task program_layer(ccc_layer_cfg c);
    ccc_layer_seq s = ccc_layer_seq::type_id::create("prog");
    s.cfg = c; s.do_program = 1; s.do_enable = 0;
    s.start(env.csb_agt.sqr);
  endtask

  protected task enable_layer(ccc_layer_cfg c);
    ccc_layer_seq s = ccc_layer_seq::type_id::create("go");
    s.cfg = c; s.do_program = 0; s.do_enable = 1;
    s.start(env.csb_agt.sqr);
  endtask

  // ---- 步骤：pending 握手（expect=1 等 dat+wt 均服务完；=0 校验未发生）----
  protected task wait_pending(int unsigned dat_base, int unsigned wt_base,
                              bit exp_pend, int unsigned max_us = 200);
    int unsigned t = 0;
    if (exp_pend) begin
      while (env.cdma_stub.n_dat_ack_served == dat_base ||
             env.cdma_stub.n_wt_ack_served == wt_base) begin
        #1us; t++;
        if (t > max_us) begin
          `uvm_error(get_type_name(), "pending handshake timeout")
          return;
        end
      end
      // req 已撤（served 计数在 req 下降后递增），再候一拍余量
      #200ns;
    end
    else begin
      #2us; // 非 pending 路径余量
      if (env.cdma_stub.n_dat_ack_served != dat_base ||
          env.cdma_stub.n_wt_ack_served != wt_base)
        `uvm_error(get_type_name(),
                   "unexpected pending handshake (bank unchanged should skip PEND)")
    end
  endtask

  // ---- 步骤：驱 updt（dat 可拆 n_updt_chunks 份；wt 单笔）----
  protected task send_updts(ccc_layer_cfg c);
    int unsigned left = c.height, chunk;
    int unsigned n = (n_updt_chunks == 0) ? 1 : n_updt_chunks;
    if (n > c.height) n = c.height;
    for (int unsigned i = 0; i < n; i++) begin
      chunk = (i == n - 1) ? left : left / (n - i);
      if (chunk == 0) continue;
      env.cdma_stub.send_dat_updt(12'(chunk), 12'(chunk * c.eps()));
      left -= chunk;
      #100ns;
    end
    env.cdma_stub.send_wt_updt(14'(c.kernels), 12'(c.wt_entries()), 9'd0);
  endtask

  // ---- 步骤：等 done 中断（toggle 位 = 全局层序号奇偶）----
  protected task wait_done(int unsigned max_us = 1000);
    bit exp_bit = n_layers_done[0]; // 第 1/3/5…层 bit0（delivery_buffer toggle）
    int unsigned base = exp_bit ? env.intr1_agt.n_rises : env.intr0_agt.n_rises;
    int unsigned other = exp_bit ? env.intr0_agt.n_rises : env.intr1_agt.n_rises;
    int unsigned t = 0;
    while ((exp_bit ? env.intr1_agt.n_rises : env.intr0_agt.n_rises) == base) begin
      #1us; t++;
      if (t > max_us) begin
        `uvm_error(get_type_name(),
                   $sformatf("done intr timeout (layer %0d, expect bit%0d)",
                             n_layers_done, exp_bit))
        return;
      end
    end
    if ((exp_bit ? env.intr0_agt.n_rises : env.intr1_agt.n_rises) != other)
      `uvm_error(get_type_name(),
                 $sformatf("wrong intr bit toggled (layer %0d expected bit%0d)",
                           n_layers_done, exp_bit))
  endtask

  // ---- 单层全流程 ----
  protected task run_layer(ccc_layer_cfg c, bit expect_pending);
    int unsigned dat_base = env.cdma_stub.n_dat_ack_served;
    int unsigned wt_base  = env.cdma_stub.n_wt_ack_served;
    bit grp = n_layers_done[0];

    `uvm_info(get_type_name(),
              $sformatf("layer %0d (group %0d): %s", n_layers_done, grp,
                        c.convert2string()), UVM_LOW)
    select_group(grp);
    if (expect_pending) begin // PEND 清账：两侧指针归零（T2 实测钉死的合同）
      dat_entry_base = 0;
      wt_entry_base  = 0;
    end
    c.preload(env.cbuf_mdl, dat_entry_base, wt_entry_base);
    env.sb.set_layer(c);
    program_layer(c);
    enable_layer(c);

    if (inject_pending_updt && expect_pending) begin
      // H1/B6 路径覆盖：pending_req 有效期注入 updt（RTL 应静默丢弃；判定弱——
      // 丢弃与否对本层完成无观测差异，此处仅保证注入不破坏层流程）
      env.cdma_stub.auto_ack = 1'b0;
      while (env.cdma_stub.vif.sc2cdma_dat_pending_req !== 1'b1) #100ns;
      env.cdma_stub.send_dat_updt(12'd1, 12'(c.eps()));
      env.cdma_stub.auto_ack = 1'b1;
    end

    wait_pending(dat_base, wt_base, expect_pending);
    send_updts(c);
    wait_done();
    n_layers_done++;
    dat_entry_base = (dat_entry_base + c.height * c.eps()) % ((c.data_bank + 1) * 256);
    wt_entry_base  = (wt_entry_base + c.wt_entries()) % ((c.weight_bank + 1) * 256);
    #2us; // drain：dbuf 尾 beat / release 出口
    env.sb.final_check();
  endtask

  // ---- 辅助：读 CACC D_OUT_SATURATION 并与 refmodel 比对（T2）----
  protected task check_sat_count();
    ccc_csb_base_seq s = ccc_csb_base_seq::type_id::create("satrd");
    bit [31:0] rd;
    s.set_item_context(null, env.csb_agt.sqr);
    s.csb_read(CSB_TGT_CACC, 12'h030, rd);
    if (rd != env.sb.rm.exp_sat_count)
      `uvm_error(get_type_name(),
                 $sformatf("sat_count mismatch: reg=%0d refmodel=%0d",
                           rd, env.sb.rm.exp_sat_count))
    else
      `uvm_info(get_type_name(),
                $sformatf("sat_count OK: %0d", rd), UVM_LOW)
  endtask

  virtual task run_seqs();
    make_cfg();
    run_layer(cfg, 1'b1); // 首层必 pending（last_bank 复位 4'hF）
  endtask

endclass : csc_cmac_cacc_layer_base_test


// T1：int8 最小端到端（C=256 -> csurf 8，C 方向必然多轮；K=8 单半）
class csc_cmac_cacc_t1_conv_test extends csc_cmac_cacc_layer_base_test;

  `uvm_component_utils(csc_cmac_cacc_t1_conv_test)

  function new(string name = "csc_cmac_cacc_t1_conv_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void make_cfg();
    cfg = ccc_layer_cfg::type_id::create("cfg");
    cfg.is_int8       = 1;
    cfg.width         = 4;
    cfg.height        = 4;
    cfg.channel       = 256;  // csurf=8, eps=2W=8
    cfg.kernels       = 8;
    cfg.clip_truncate = 6;
    cfg.data_bank     = 0;
    cfg.weight_bank   = 0;
    void'($value$plusargs("ccc_pattern=%d", cfg.pattern_mode)); // 校准图样入口
    if (cfg.pattern_mode != 0) cfg.clip_truncate = 0; // 图样期望值不过截断
    cfg.check_supported();
    cfg.gen_data();
  endfunction

endclass : csc_cmac_cacc_t1_conv_test


// T2：int16 clip 边角扫（0 直通 / 1 / 8 / 16 / 31）+ sat_count 对账
//     全幅随机值下 48b 累加和普遍超 32b，小 clip 层饱和高发（E2/E4/E5）
class csc_cmac_cacc_t2_clip_test extends csc_cmac_cacc_layer_base_test;

  `uvm_component_utils(csc_cmac_cacc_t2_clip_test)

  function new(string name = "csc_cmac_cacc_t2_clip_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(2ms, 1);
  endfunction

  virtual function void make_cfg();
  endfunction

  virtual function ccc_layer_cfg mk(int unsigned clip);
    ccc_layer_cfg c = ccc_layer_cfg::type_id::create($sformatf("cfg_clip%0d", clip));
    c.is_int8       = 0;
    c.width         = 4;
    c.height        = 2;
    c.channel       = 128;  // csurf=8，C 多轮
    c.kernels       = 12;   // 尾 lane 补 0 顺带覆盖
    c.clip_truncate = clip;
    c.data_bank     = 0;
    c.weight_bank   = 0;
    c.check_supported();
    c.gen_data();
    return c;
  endfunction

  virtual task run_seqs();
    int unsigned clips[5] = '{0, 1, 8, 16, 31};
    foreach (clips[i]) begin
      run_layer(mk(clips[i]), n_layers_done == 0); // 首层 pending，其余同 bank 免
      check_sat_count();
    end
  endtask

endclass : csc_cmac_cacc_t2_clip_test


// T3：随机层 + sdp ready 随机背压 + 一次长停 + dat updt 随机拆分 + pending 期注入
class csc_cmac_cacc_t3_random_test extends csc_cmac_cacc_layer_base_test;

  `uvm_component_utils(csc_cmac_cacc_t3_random_test)

  function new(string name = "csc_cmac_cacc_t3_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(3ms, 1);
  endfunction

  virtual function void make_cfg();
    cfg = ccc_layer_cfg::type_id::create("cfg");
    if (!cfg.randomize())
      `uvm_fatal(get_type_name(), "cfg randomize failed")
  endfunction

  virtual task run_seqs();
    // 背压旋钮
    env.sdp_sink.ready_gap_pct = 30;
    env.sdp_sink.ready_gap_min = 1;
    env.sdp_sink.ready_gap_max = 6;
    n_updt_chunks       = $urandom_range(4, 1);
    inject_pending_updt = 1'b1;

    make_cfg();
    fork
      run_layer(cfg, 1'b1);
      begin // 层 0 中段一次长停（F3/F4：credit 环停等；不丢/不重/序不变由判分背书）
        #3us;
        env.sdp_sink.hold_ready_low(400);
      end
    join

    // 第二层：同 bank 免 pending，换一份随机数据与拆分
    n_updt_chunks = $urandom_range(4, 1);
    begin
      ccc_layer_cfg c2 = ccc_layer_cfg::type_id::create("cfg2");
      c2.is_int8 = cfg.is_int8;   c2.width = cfg.width; c2.height = cfg.height;
      c2.channel = cfg.channel;   c2.kernels = cfg.kernels;
      c2.clip_truncate = $urandom_range(16, 0);
      c2.data_bank = cfg.data_bank; c2.weight_bank = cfg.weight_bank;
      c2.check_supported();
      c2.gen_data();
      run_layer(c2, 1'b0);
    end
  endtask

endclass : csc_cmac_cacc_t3_random_test


// T5：K 双半 / 尾 mask / C 深迭代——三层定向
//   L0 int8 K=32 满双半 C=64；L1 int8 K=20（尾 mask）C=192（csurf6 尾双面）；
//   L2 int16 K=5（cmac_b wt 静默半） C=192 深迭代
class csc_cmac_cacc_t5_khalf_test extends csc_cmac_cacc_layer_base_test;

  `uvm_component_utils(csc_cmac_cacc_t5_khalf_test)

  function new(string name = "csc_cmac_cacc_t5_khalf_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(3ms, 1);
  endfunction

  virtual function void make_cfg();
  endfunction

  virtual function ccc_layer_cfg mk(bit i8, int unsigned w, int unsigned h,
                                    int unsigned c, int unsigned k,
                                    int unsigned clip);
    ccc_layer_cfg cf = ccc_layer_cfg::type_id::create("cfg_t5");
    cf.is_int8 = i8; cf.width = w; cf.height = h; cf.channel = c;
    cf.kernels = k;  cf.clip_truncate = clip;
    cf.data_bank = 0; cf.weight_bank = 0;
    cf.check_supported();
    cf.gen_data();
    return cf;
  endfunction

  virtual task run_seqs();
    run_layer(mk(1, 4, 4, 64, 32, 4),  1'b1); // K=32 满双半
    run_layer(mk(1, 4, 6, 192, 20, 5), 1'b0); // K=20 尾 mask + csurf6 尾双面
    run_layer(mk(0, 4, 4, 192, 5, 8),  1'b0); // int16 K=5，b 例 wt 静默
  endtask

endclass : csc_cmac_cacc_t5_khalf_test


// T6：双层乒乓 + bank 变更二次 pending + toggle 中断 + 状态收尾
class csc_cmac_cacc_t6_pingpong_test extends csc_cmac_cacc_layer_base_test;

  `uvm_component_utils(csc_cmac_cacc_t6_pingpong_test)

  function new(string name = "csc_cmac_cacc_t6_pingpong_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(3ms, 1);
  endfunction

  virtual function void make_cfg();
  endfunction

  virtual task run_seqs();
    ccc_csb_base_seq rd;
    bit [31:0] v;
    ccc_layer_cfg c0, c1, c2;

    c0 = ccc_layer_cfg::type_id::create("c0");
    c0.is_int8 = 0; c0.width = 4; c0.height = 4; c0.channel = 64;
    c0.kernels = 16; c0.clip_truncate = 4; c0.data_bank = 0; c0.weight_bank = 0;
    c0.check_supported(); c0.gen_data();

    c1 = ccc_layer_cfg::type_id::create("c1"); // 同 bank -> 免 pending（B7）
    c1.is_int8 = 0; c1.width = 4; c1.height = 4; c1.channel = 64;
    c1.kernels = 16; c1.clip_truncate = 7; c1.data_bank = 0; c1.weight_bank = 0;
    c1.check_supported(); c1.gen_data();

    c2 = ccc_layer_cfg::type_id::create("c2"); // 换 bank -> 二次 pending（F-CBUF-5）
    c2.is_int8 = 1; c2.width = 4; c2.height = 4; c2.channel = 128;
    c2.kernels = 8; c2.clip_truncate = 3; c2.data_bank = 1; c2.weight_bank = 1;
    c2.check_supported(); c2.gen_data();

    run_layer(c0, 1'b1);   // 层 0：首层 pending，intr bit0
    run_layer(c1, 1'b0);   // 层 1：同 bank 免 pending，intr bit1
    run_layer(c2, 1'b1);   // 层 2：bank 变更再 pending，intr bit0

    // 中断 toggle 总账：bit0 两次（层 0/2）、bit1 一次（层 1）
    if (env.intr0_agt.n_rises != 2 || env.intr1_agt.n_rises != 1)
      `uvm_error(get_type_name(),
                 $sformatf("intr toggle mismatch: bit0=%0d(exp 2) bit1=%0d(exp 1)",
                           env.intr0_agt.n_rises, env.intr1_agt.n_rises))

    // 收尾状态：四单元 S_STATUS 归 idle
    rd = ccc_csb_base_seq::type_id::create("rd");
    rd.set_item_context(null, env.csb_agt.sqr);
    rd.csb_check(CSB_TGT_CSC,    12'h000, 32'h0, "final CSC S_STATUS");
    rd.csb_check(CSB_TGT_CMAC_A, 12'h000, 32'h0, "final CMAC_A S_STATUS");
    rd.csb_check(CSB_TGT_CMAC_B, 12'h000, 32'h0, "final CMAC_B S_STATUS");
    rd.csb_check(CSB_TGT_CACC,   12'h000, 32'h0, "final CACC S_STATUS");
    // 奇数层数收尾：consumer 停在 1（3 层完成）
    rd.csb_read(CSB_TGT_CSC, 12'h004, v);
    if (v[16] != 1'b1)
      `uvm_error(get_type_name(),
                 $sformatf("CSC consumer expected 1 after 3 layers: S_POINTER=0x%08h", v))
  endtask

endclass : csc_cmac_cacc_t6_pingpong_test

`endif // CSC_CMAC_CACC_TEST_LIB_SVH
