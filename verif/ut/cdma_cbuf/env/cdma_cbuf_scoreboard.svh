// -----------------------------------------------------------------------------
// cdma_cbuf_scoreboard : 四比对面（Wave2）
//   ① DMA 读请求合法性/覆盖：32B 对齐、不跨 256B、ram_type 选路正确、
//      每 32B 块恰取一次、层末足迹齐全
//   ② cbuf 写流：全程维护 cbuf 镜像（flush 当预置状态吸收），active 后
//      写必须落在配置面内且命中 refmodel 期望；层末镜像与期望逐 slot 比对
//   ③ csc 读回：cbuf_rd 事务与镜像逐 entry 比对（写→RAM→读全链路），
//      层末校验读回条数覆盖全部期望 entry
//   ④ cdma2sc 记账：Σentries/slices/kernels/wt_entries/wmb 守恒
//      （updt 出口晚内部事件 9 拍——只对总和比对，done+drain 后调 final_check）
//   用法：test 在 op_en 前调 set_layer(cfg, dat_rsp, wt_rsp)（此前 flush 流量
//   一律吸收），done+drain+读回后调 final_check()
// -----------------------------------------------------------------------------
`ifndef CDMA_CBUF_SCOREBOARD_SVH
`define CDMA_CBUF_SCOREBOARD_SVH

`uvm_analysis_imp_decl(_dat_mc_req)
`uvm_analysis_imp_decl(_dat_cv_req)
`uvm_analysis_imp_decl(_wt_mc_req)
`uvm_analysis_imp_decl(_wt_cv_req)
`uvm_analysis_imp_decl(_cbuf_dat_wr)
`uvm_analysis_imp_decl(_cbuf_wt_wr)
`uvm_analysis_imp_decl(_cbuf_dat_rd)
`uvm_analysis_imp_decl(_cbuf_wt_rd)
`uvm_analysis_imp_decl(_cbuf_wmb_rd)
`uvm_analysis_imp_decl(_sc_updt)

class cdma_cbuf_scoreboard extends uvm_scoreboard;

  uvm_analysis_imp_dat_mc_req  #(dma_seq_item, cdma_cbuf_scoreboard) dat_mc_req_imp;
  uvm_analysis_imp_dat_cv_req  #(dma_seq_item, cdma_cbuf_scoreboard) dat_cv_req_imp;
  uvm_analysis_imp_wt_mc_req   #(dma_seq_item, cdma_cbuf_scoreboard) wt_mc_req_imp;
  uvm_analysis_imp_wt_cv_req   #(dma_seq_item, cdma_cbuf_scoreboard) wt_cv_req_imp;
  uvm_analysis_imp_cbuf_dat_wr #(cbuf_wr_item, cdma_cbuf_scoreboard) cbuf_dat_wr_imp;
  uvm_analysis_imp_cbuf_wt_wr  #(cbuf_wr_item, cdma_cbuf_scoreboard) cbuf_wt_wr_imp;
  uvm_analysis_imp_cbuf_dat_rd #(cbuf_rd_item, cdma_cbuf_scoreboard) cbuf_dat_rd_imp;
  uvm_analysis_imp_cbuf_wt_rd  #(cbuf_rd_item, cdma_cbuf_scoreboard) cbuf_wt_rd_imp;
  uvm_analysis_imp_cbuf_wmb_rd #(cbuf_rd_item, cdma_cbuf_scoreboard) cbuf_wmb_rd_imp;
  uvm_analysis_imp_sc_updt     #(cdma_sc_item, cdma_cbuf_scoreboard) sc_updt_imp;

  cdma_layer_cfg      cfg;
  cdma_cbuf_refmodel  rm;
  bit                 active;          // set_layer 后为 1
  bit                 passive;         // T6：纯吸收模式（多层连跑，数据面不比对）

  // cbuf 镜像（flush 后全阵列有效）
  bit [1023:0] mirror_data  [bit [11:0]];
  bit [3:0]    mirror_valid [bit [11:0]];

  // 面① 计数
  int unsigned dat_chunk_seen [bit [63:0]];
  int unsigned wt_chunk_seen  [bit [63:0]];
  int unsigned n_dat_req, n_wt_req;

  // 面③ 计数
  int unsigned n_dat_rd_checked, n_wt_rd_checked;

  // 面④ 累计
  int unsigned dat_entries_sum, dat_slices_sum;
  int unsigned wt_kernels_sum, wt_entries_sum, wmb_entries_sum;

  int unsigned n_flush_wr; // 非 active 期吸收的写

  `uvm_component_utils(cdma_cbuf_scoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    dat_mc_req_imp  = new("dat_mc_req_imp", this);
    dat_cv_req_imp  = new("dat_cv_req_imp", this);
    wt_mc_req_imp   = new("wt_mc_req_imp", this);
    wt_cv_req_imp   = new("wt_cv_req_imp", this);
    cbuf_dat_wr_imp = new("cbuf_dat_wr_imp", this);
    cbuf_wt_wr_imp  = new("cbuf_wt_wr_imp", this);
    cbuf_dat_rd_imp = new("cbuf_dat_rd_imp", this);
    cbuf_wt_rd_imp  = new("cbuf_wt_rd_imp", this);
    cbuf_wmb_rd_imp = new("cbuf_wmb_rd_imp", this);
    sc_updt_imp     = new("sc_updt_imp", this);
    rm = cdma_cbuf_refmodel::type_id::create("rm");
  endfunction

  // op_en 前调用（dat_wr_base/wt_half_base：跨层环形写指针，首层 0）
  function void set_layer(cdma_layer_cfg cfg_i,
                          dma_slave_responder_cdp_t dat_rsp,
                          dma_slave_responder_cdp_t wt_rsp,
                          int unsigned dat_wr_base = 0,
                          int unsigned wt_half_base = 0);
    cfg = cfg_i;
    rm.build(cfg, dat_rsp, wt_rsp, dat_wr_base, wt_half_base);
    dat_chunk_seen.delete(); wt_chunk_seen.delete();
    n_dat_req = 0; n_wt_req = 0;
    n_dat_rd_checked = 0; n_wt_rd_checked = 0;
    dat_entries_sum = 0; dat_slices_sum = 0;
    wt_kernels_sum = 0; wt_entries_sum = 0; wmb_entries_sum = 0;
    active = 1'b1;
  endfunction

  // ---------------- 面①：DMA 读请求 ----------------
  protected function void check_req(dma_seq_item t, bit is_dat, bit on_mc);
    bit exp_mc;
    if (t.kind != dma_seq_item::DMA_RD_REQ) return;
    if (passive) return;
    if (!active) begin
      `uvm_error(get_type_name(), $sformatf("DMA req outside active layer: %s", t.convert2string()))
      return;
    end
    exp_mc = is_dat ? cfg.dat_ram_mc : cfg.wt_ram_mc;
    if (on_mc != exp_mc)
      `uvm_error(get_type_name(), $sformatf("%s req on wrong ram_type port (%s): %s",
                 is_dat ? "dat" : "wt", on_mc ? "MC" : "CV", t.convert2string()))
    if (t.addr[4:0] != 0)
      `uvm_error(get_type_name(), $sformatf("req addr not 32B aligned: %s", t.convert2string()))
    if ((t.addr % 256) + (t.size + 1) * 32 > 256)
      `uvm_error(get_type_name(), $sformatf("req crosses 256B boundary: %s", t.convert2string()))
    for (int unsigned i = 0; i <= t.size; i++) begin
      bit [63:0] c = t.addr + i * 32;
      if (is_dat) begin
        if (!rm.dat_chunks.exists(c))
          `uvm_error(get_type_name(), $sformatf("dat req chunk 0x%0h outside footprint", c))
        else begin
          dat_chunk_seen[c]++;
          if (dat_chunk_seen[c] > 1)
            `uvm_error(get_type_name(), $sformatf("dat chunk 0x%0h fetched %0d times", c, dat_chunk_seen[c]))
        end
      end
      else begin
        if (!rm.wt_chunks.exists(c))
          `uvm_error(get_type_name(), $sformatf("wt req chunk 0x%0h outside footprint", c))
        else begin
          wt_chunk_seen[c]++;
          if (wt_chunk_seen[c] > 1)
            `uvm_error(get_type_name(), $sformatf("wt chunk 0x%0h fetched %0d times", c, wt_chunk_seen[c]))
        end
      end
    end
    if (is_dat) n_dat_req++; else n_wt_req++;
  endfunction

  function void write_dat_mc_req(dma_seq_item t); check_req(t, 1, 1); endfunction
  function void write_dat_cv_req(dma_seq_item t); check_req(t, 1, 0); endfunction
  function void write_wt_mc_req(dma_seq_item t);  check_req(t, 0, 1); endfunction
  function void write_wt_cv_req(dma_seq_item t);  check_req(t, 0, 0); endfunction

  // ---------------- 面②：cbuf 写流 ----------------
  protected function void mirror_apply(bit [11:0] addr, bit [1:0] half_sel, bit [1023:0] data);
    if (!mirror_data.exists(addr)) begin
      mirror_data[addr]  = '0;
      mirror_valid[addr] = '0;
    end
    if (half_sel[0]) begin
      mirror_data[addr][511:0]  = data[511:0];
      mirror_valid[addr][1:0]   = 2'b11;
    end
    if (half_sel[1]) begin
      mirror_data[addr][1023:512] = data[1023:512];
      mirror_valid[addr][3:2]     = 2'b11;
    end
  endfunction

  function void write_cbuf_dat_wr(cbuf_wr_item t);
    if (!active || passive) begin
      n_flush_wr++;
      mirror_apply(t.addr, t.hsel, t.data);
      return;
    end
    if (t.bank > cfg.data_bank)
      `uvm_error(get_type_name(), $sformatf("dat wr outside data banks(<=%0d): %s",
                 cfg.data_bank, t.convert2string()))
    if (!rm.exp_dat_data.exists(t.addr))
      `uvm_error(get_type_name(), $sformatf("dat wr to unexpected entry: %s", t.convert2string()))
    else begin
      // RTL 实证（T2）：slice 尾部半 entry 经 ext128/ext64 释放时 cvt 连
      // 未占用半一起写（内容为流水线残留，don't-care）——只要求写命中
      // 期望 entry 且至少覆盖一个期望 slot，越界 slot 不比对（面②只对
      // 期望 slot）
      bit [3:0] slots = {{2{t.hsel[1]}}, {2{t.hsel[0]}}};
      if ((slots & rm.exp_dat_slot_mask[t.addr]) == 0)
        `uvm_error(get_type_name(), $sformatf("dat wr touches no expected slot (%b vs %b): %s",
                   slots, rm.exp_dat_slot_mask[t.addr], t.convert2string()))
      else if ((slots & ~rm.exp_dat_slot_mask[t.addr]) != 0)
        `uvm_info(get_type_name(), $sformatf("dat wr fills dont-care slots (%b vs %b): %s",
                  slots, rm.exp_dat_slot_mask[t.addr], t.convert2string()), UVM_HIGH)
    end
    mirror_apply(t.addr, t.hsel, t.data);
  endfunction

  function void write_cbuf_wt_wr(cbuf_wr_item t);
    bit [1:0]    half = t.hsel[0] ? 2'b10 : 2'b01;
    bit [1023:0] d    = t.hsel[0] ? {t.data[511:0], 512'b0} : t.data;
    if (!active || passive) begin
      n_flush_wr++;
      mirror_apply(t.addr, half, d);
      return;
    end
    if (t.bank < cfg.data_bank + 1 || t.bank > cfg.data_bank + 1 + cfg.weight_bank)
      `uvm_error(get_type_name(), $sformatf("wt wr outside weight banks[%0d:%0d]: %s",
                 cfg.data_bank + 1, cfg.data_bank + 1 + cfg.weight_bank, t.convert2string()))
    if (!rm.exp_wt_data.exists(t.addr))
      `uvm_error(get_type_name(), $sformatf("wt wr to unexpected entry: %s", t.convert2string()))
    mirror_apply(t.addr, half, d);
  endfunction

  // ---------------- 面③：csc 读回 vs 镜像 ----------------
  protected function void check_rd(bit [11:0] addr, bit [1023:0] data, string port);
    if (!mirror_data.exists(addr) || mirror_valid[addr] != 4'hF) begin
      `uvm_error(get_type_name(), $sformatf("%s rd of entry 0x%03h with incomplete mirror", port, addr))
      return;
    end
    if (data !== mirror_data[addr])
      `uvm_error(get_type_name(), $sformatf("%s rd mismatch @0x%03h exp[127:0]=0x%032h got[127:0]=0x%032h",
                 port, addr, mirror_data[addr][127:0], data[127:0]))
  endfunction

  function void write_cbuf_dat_rd(cbuf_rd_item t);
    check_rd(t.addr, t.data, "dat");
    if (active && rm.exp_dat_data.exists(t.addr)) n_dat_rd_checked++;
  endfunction

  function void write_cbuf_wt_rd(cbuf_rd_item t);
    check_rd(t.addr, t.data, "wt");
    if (active && rm.exp_wt_data.exists(t.addr)) n_wt_rd_checked++;
  endfunction

  function void write_cbuf_wmb_rd(cbuf_rd_item t);
    check_rd({4'hF, t.addr[7:0]}, t.data, "wmb"); // wmb 口固定 bank15
  endfunction

  // ---------------- 面④：记账 ----------------
  function void write_sc_updt(cdma_sc_item t);
    if (t.kind == cdma_sc_item::SC_DAT_UPDT) begin
      dat_entries_sum += t.entries;
      dat_slices_sum  += t.slices;
    end
    else begin
      wt_kernels_sum  += t.kernels;
      wt_entries_sum  += t.entries;
      wmb_entries_sum += t.wmb_entries;
    end
  endfunction

  // ---------------- 层末总检 ----------------
  function void final_check(bit expect_readback = 1'b1);
    int unsigned n_missing;
    bit [63:0]   ck;
    bit [11:0]   ek;

    // 面① 足迹齐全
    n_missing = 0;
    if (rm.dat_chunks.first(ck)) do
      if (!dat_chunk_seen.exists(ck)) n_missing++;
    while (rm.dat_chunks.next(ck));
    if (n_missing)
      `uvm_error(get_type_name(), $sformatf("face1: %0d dat chunks never fetched", n_missing))
    n_missing = 0;
    if (rm.wt_chunks.first(ck)) do
      if (!wt_chunk_seen.exists(ck)) n_missing++;
    while (rm.wt_chunks.next(ck));
    if (n_missing)
      `uvm_error(get_type_name(), $sformatf("face1: %0d wt chunks never fetched", n_missing))

    // 面② 镜像 vs 期望
    if (rm.exp_dat_data.first(ek)) do begin
      if (!mirror_data.exists(ek))
        `uvm_error(get_type_name(), $sformatf("face2: dat entry 0x%03h never written", ek))
      else
        for (int s = 0; s < 4; s++)
          if (rm.exp_dat_slot_mask[ek][s] &&
              mirror_data[ek][s*256 +: 256] !== rm.exp_dat_data[ek][s*256 +: 256])
            `uvm_error(get_type_name(),
                       $sformatf("face2: dat entry 0x%03h slot%0d exp=0x%064h got=0x%064h",
                                 ek, s, rm.exp_dat_data[ek][s*256 +: 256],
                                 mirror_data[ek][s*256 +: 256]))
    end while (rm.exp_dat_data.next(ek));

    if (rm.exp_wt_data.first(ek)) do begin
      if (!mirror_data.exists(ek))
        `uvm_error(get_type_name(), $sformatf("face2: wt entry 0x%03h never written", ek))
      else
        for (int s = 0; s < 4; s++)
          if (rm.exp_wt_slot_mask[ek][s] &&
              mirror_data[ek][s*256 +: 256] !== rm.exp_wt_data[ek][s*256 +: 256])
            `uvm_error(get_type_name(),
                       $sformatf("face2: wt entry 0x%03h slot%0d exp=0x%064h got=0x%064h",
                                 ek, s, rm.exp_wt_data[ek][s*256 +: 256],
                                 mirror_data[ek][s*256 +: 256]))
    end while (rm.exp_wt_data.next(ek));

    // 面③ 读回覆盖
    if (expect_readback) begin
      if (n_dat_rd_checked < rm.exp_dat_data.num())
        `uvm_error(get_type_name(), $sformatf("face3: dat readback %0d < expected %0d",
                   n_dat_rd_checked, rm.exp_dat_data.num()))
      if (n_wt_rd_checked < rm.exp_wt_data.num())
        `uvm_error(get_type_name(), $sformatf("face3: wt readback %0d < expected %0d",
                   n_wt_rd_checked, rm.exp_wt_data.num()))
    end

    // 面④ 记账守恒
    if (dat_entries_sum != cfg.dat_entries_total())
      `uvm_error(get_type_name(), $sformatf("face4: dat entries sum %0d != %0d",
                 dat_entries_sum, cfg.dat_entries_total()))
    if (dat_slices_sum != cfg.height)
      `uvm_error(get_type_name(), $sformatf("face4: dat slices sum %0d != %0d",
                 dat_slices_sum, cfg.height))
    if (wt_kernels_sum != cfg.kernels)
      `uvm_error(get_type_name(), $sformatf("face4: wt kernels sum %0d != %0d",
                 wt_kernels_sum, cfg.kernels))
    if (wt_entries_sum != cfg.wt_entries_total())
      `uvm_error(get_type_name(), $sformatf("face4: wt entries sum %0d != %0d",
                 wt_entries_sum, cfg.wt_entries_total()))
    if (wmb_entries_sum != 0)
      `uvm_error(get_type_name(), $sformatf("face4: wmb entries sum %0d != 0", wmb_entries_sum))

    `uvm_info(get_type_name(),
              $sformatf("final_check done: dat req=%0d wt req=%0d dat rd=%0d wt rd=%0d flush wr absorbed=%0d",
                        n_dat_req, n_wt_req, n_dat_rd_checked, n_wt_rd_checked, n_flush_wr),
              UVM_LOW)
    active = 1'b0;
  endfunction

endclass : cdma_cbuf_scoreboard

`endif // CDMA_CBUF_SCOREBOARD_SVH
