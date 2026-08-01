// -----------------------------------------------------------------------------
// cdma_sc_if : cdma <-> csc 状态-信用面 interface
//   事实源 : outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_cdma.v:89-90、:114-136
//   cdma->sc（监测）: dat_updt/entries/slices、wt_updt/kernels/entries/wmb_entries、
//                    dat_pending_ack / wt_pending_ack（对 sc2cdma_*_pending_req 的应答）
//   sc->cdma（驱动）: 同构 updt 组（释放 credit）+ dat/wt_pending_req；
//                    Wave1 全 tie 0，Wave2 经 cdma_sc_stub 的 send_* task 驱动
// -----------------------------------------------------------------------------
interface cdma_sc_if (input logic clk, input logic rstn);

  // cdma -> sc（TB 监测）
  logic        cdma2sc_dat_updt;
  logic [11:0] cdma2sc_dat_entries;
  logic [11:0] cdma2sc_dat_slices;
  logic        cdma2sc_wt_updt;
  logic [13:0] cdma2sc_wt_kernels;
  logic [11:0] cdma2sc_wt_entries;
  logic [8:0]  cdma2sc_wmb_entries;
  logic        cdma2sc_dat_pending_ack;
  logic        cdma2sc_wt_pending_ack;

  // sc -> cdma（TB 驱动，Wave1 tie 0）
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
    output sc2cdma_dat_updt, sc2cdma_dat_entries, sc2cdma_dat_slices,
           sc2cdma_wt_updt, sc2cdma_wt_kernels, sc2cdma_wt_entries,
           sc2cdma_wmb_entries, sc2cdma_dat_pending_req, sc2cdma_wt_pending_req;
    input  cdma2sc_dat_pending_ack, cdma2sc_wt_pending_ack;
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

endinterface : cdma_sc_if
