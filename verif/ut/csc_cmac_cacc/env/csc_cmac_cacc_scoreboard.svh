// -----------------------------------------------------------------------------
// csc_cmac_cacc_scoreboard : 唯一判分面 = cacc2sdp beat 流（in-order 全比对）
//   - set_layer(cfg)：内部 refmodel 建期望 beat 队列 + 期望 sat 数 + 归还合同
//   - write_ccc_sdp：sdp_sink 每个握手 beat 到来即与期望队首比对（值 512b +
//     batch_end 恒 0 + layer_end 位），失配报层内坐标（pixel/K 半）
//   - write_ccc_sc_rls：累计 sc2cdma 归还（dat entries/slices、wt kernels/
//     entries/wmb），final_check 与配置合同对账（B8）
//   - 读址域检查在 cbuf_model（cfg.preload 已按 bank 划分开旋钮），此处不重复
//   - passive=1：只收不判（机制类测试用）
// -----------------------------------------------------------------------------
`ifndef CSC_CMAC_CACC_SCOREBOARD_SVH
`define CSC_CMAC_CACC_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_ccc_sdp)
`uvm_analysis_imp_decl(_ccc_sc_rls)

class csc_cmac_cacc_scoreboard extends uvm_component;

  uvm_analysis_imp_ccc_sdp    #(sdp_item, csc_cmac_cacc_scoreboard)     sdp_imp;
  uvm_analysis_imp_ccc_sc_rls #(cdma_sc_item, csc_cmac_cacc_scoreboard) sc_rls_imp;

  ccc_layer_cfg cfg;
  ccc_refmodel  rm;

  bit          passive;
  int unsigned n_sdp_beats;      // 本层已收 beat 数
  int unsigned n_beat_errs;
  // 归还累计
  int unsigned rls_dat_entries, rls_dat_slices;
  int unsigned rls_wt_kernels, rls_wt_entries, rls_wmb_entries;
  int unsigned n_sc_rls;

  `uvm_component_utils(csc_cmac_cacc_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    sdp_imp    = new("sdp_imp", this);
    sc_rls_imp = new("sc_rls_imp", this);
    rm         = ccc_refmodel::type_id::create("rm");
  endfunction

  // 层初始化：建期望、清计数（多层测试每层调一次）
  function void set_layer(ccc_layer_cfg c);
    cfg = c;
    rm.build(c);
    n_sdp_beats     = 0;
    n_beat_errs     = 0;
    rls_dat_entries = 0; rls_dat_slices = 0;
    rls_wt_kernels  = 0; rls_wt_entries = 0; rls_wmb_entries = 0;
    n_sc_rls        = 0;
  endfunction

  virtual function void write_ccc_sdp(sdp_item tr);
    bit [513:0] exp;
    int unsigned pix, half;
    n_sdp_beats++;
    if (passive || cfg == null) return;
    if (rm.exp_beats.size() == 0) begin
      `uvm_error(get_type_name(),
                 $sformatf("unexpected extra beat #%0d: %s", n_sdp_beats, tr.convert2string()))
      return;
    end
    exp  = rm.exp_beats.pop_front();
    pix  = (n_sdp_beats - 1) / cfg.beats_per_pixel();
    half = (n_sdp_beats - 1) % cfg.beats_per_pixel();
    if (tr.pd !== exp) begin
      n_beat_errs++;
      `uvm_error(get_type_name(),
                 $sformatf("beat #%0d mismatch @pixel(h=%0d,w=%0d) khalf=%0d",
                           n_sdp_beats, pix / cfg.out_w(), pix % cfg.out_w(), half))
      for (int l = 0; l < 16; l++)
        if (tr.pd[l*32 +: 32] !== exp[l*32 +: 32])
          `uvm_info(get_type_name(),
                    $sformatf("  lane%02d (k=%0d): exp=0x%08h got=0x%08h",
                              l, half*16 + l, exp[l*32 +: 32], tr.pd[l*32 +: 32]),
                    UVM_LOW)
      if (tr.pd[513:512] !== exp[513:512])
        `uvm_info(get_type_name(),
                  $sformatf("  flags: exp layer_end=%0b batch_end=%0b got %0b/%0b",
                            exp[513], exp[512], tr.pd[513], tr.pd[512]), UVM_LOW)
    end
  endfunction

  virtual function void write_ccc_sc_rls(cdma_sc_item tr);
    n_sc_rls++;
    if (tr.kind == cdma_sc_item::SC_DAT_UPDT) begin
      rls_dat_entries += tr.entries;
      rls_dat_slices  += tr.slices;
    end
    else begin
      rls_wt_kernels  += tr.kernels;
      rls_wt_entries  += tr.entries;
      rls_wmb_entries += tr.wmb_entries;
    end
    `uvm_info(get_type_name(),
              $sformatf("sc release #%0d: %s", n_sc_rls, tr.convert2string()), UVM_MEDIUM)
  endfunction

  // 层末总检：beat 数清空 + 归还合同（dat: slices=H entries=H*eps；
  // wt: kernels=K entries=wt_entries wmb=0）
  function void final_check();
    if (passive || cfg == null) return;
    if (rm.exp_beats.size() != 0)
      `uvm_error(get_type_name(),
                 $sformatf("beat stream incomplete: %0d expected beats never came (got %0d)",
                           rm.exp_beats.size(), n_sdp_beats))
    if (rls_dat_slices != cfg.height || rls_dat_entries != cfg.height * cfg.eps())
      `uvm_error(get_type_name(),
                 $sformatf("dat release mismatch: slices=%0d(exp %0d) entries=%0d(exp %0d)",
                           rls_dat_slices, cfg.height,
                           rls_dat_entries, cfg.height * cfg.eps()))
    // 注意：CSC 的 wt 归还 kernels 字段 RTL 硬拴 0（NV_NVDLA_CSC_wl.v:3668），
    // 跨单元合同以 entries 记账，kernels 恒 0（T1 实测发现）
    if (rls_wt_kernels != 0 || rls_wt_entries != cfg.wt_entries() ||
        rls_wmb_entries != 0)
      `uvm_error(get_type_name(),
                 $sformatf("wt release mismatch: kernels=%0d(exp 0, RTL tied) entries=%0d(exp %0d) wmb=%0d(exp 0)",
                           rls_wt_kernels, rls_wt_entries, cfg.wt_entries(),
                           rls_wmb_entries))
    if (n_beat_errs == 0 && rm.exp_beats.size() == 0)
      `uvm_info(get_type_name(),
                $sformatf("layer PASS: %0d beats all matched, releases balanced", n_sdp_beats),
                UVM_LOW)
  endfunction

endclass : csc_cmac_cacc_scoreboard

`endif // CSC_CMAC_CACC_SCOREBOARD_SVH
