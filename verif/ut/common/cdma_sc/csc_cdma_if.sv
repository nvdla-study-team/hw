// -----------------------------------------------------------------------------
// csc_cdma_if : cdma <-> csc 状态-信用面 interface（csc UT 用，TB 扮演 cdma 侧）
//   信号集与 cdma_sc_if 相同、clocking 方向对偶；独立成一个 interface 而非在
//   cdma_sc_if 加第二套 clocking，是为避免"clocking 输出 + tb assign"对同一
//   interface 变量构成静态双驱动（VCS 警告并将升级为 error）
//   cdma->sc（TB 驱动，csc_cdma_stub）: updt 组（入账通告）+ pending_ack
//   sc->cdma（TB 监测）: updt 组（层末归还）+ dat/wt_pending_req
//   事实源 : outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_csc.v:583-599、:1137-1144
//   注意 : wmb 计数端口名是 cdma2sc_wmb_entries / sc2cdma_wmb_entries
//         （无 _wt_ 中缀），与 cdma 侧命名一致但易与 wt_entries 混淆
// -----------------------------------------------------------------------------
interface csc_cdma_if (input logic clk, input logic rstn);

  // cdma -> sc（TB 驱动）
  logic        cdma2sc_dat_updt;
  logic [11:0] cdma2sc_dat_entries;
  logic [11:0] cdma2sc_dat_slices;
  logic        cdma2sc_wt_updt;
  logic [13:0] cdma2sc_wt_kernels;
  logic [11:0] cdma2sc_wt_entries;
  logic [8:0]  cdma2sc_wmb_entries;
  logic        cdma2sc_dat_pending_ack;
  logic        cdma2sc_wt_pending_ack;

  // sc -> cdma（TB 监测）
  logic        sc2cdma_dat_updt;
  logic [11:0] sc2cdma_dat_entries;
  logic [11:0] sc2cdma_dat_slices;
  logic        sc2cdma_wt_updt;
  logic [13:0] sc2cdma_wt_kernels;
  logic [11:0] sc2cdma_wt_entries;
  logic [8:0]  sc2cdma_wmb_entries;
  logic        sc2cdma_dat_pending_req;
  logic        sc2cdma_wt_pending_req;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output cdma2sc_dat_updt, cdma2sc_dat_entries, cdma2sc_dat_slices,
           cdma2sc_wt_updt, cdma2sc_wt_kernels, cdma2sc_wt_entries,
           cdma2sc_wmb_entries, cdma2sc_dat_pending_ack, cdma2sc_wt_pending_ack;
    input  sc2cdma_dat_pending_req, sc2cdma_wt_pending_req;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input cdma2sc_dat_updt, cdma2sc_dat_entries, cdma2sc_dat_slices,
          cdma2sc_wt_updt, cdma2sc_wt_kernels, cdma2sc_wt_entries,
          cdma2sc_wmb_entries, cdma2sc_dat_pending_ack, cdma2sc_wt_pending_ack,
          sc2cdma_dat_updt, sc2cdma_dat_entries, sc2cdma_dat_slices,
          sc2cdma_wt_updt, sc2cdma_wt_kernels, sc2cdma_wt_entries,
          sc2cdma_wmb_entries, sc2cdma_dat_pending_req, sc2cdma_wt_pending_req;
  endclocking

endinterface : csc_cdma_if
