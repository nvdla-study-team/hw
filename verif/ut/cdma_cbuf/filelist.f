// -----------------------------------------------------------------------------
// filelist.f : cdma_cbuf UT 编译清单（路径相对 verif/ut/cdma_cbuf/）
//   顺序：incdir -> vlibs cell 闭包 -> DUT -> -y 兜底（vlibs + rams/synth）->
//         interface -> 公共 pkg -> 用例 pkg -> tb
// -----------------------------------------------------------------------------

// ---- include 路径 ----
+incdir+../../../outdir/nv_full/vmod/include
+incdir+../../../outdir/nv_full/vmod/vlibs
+incdir+../common
+incdir+../common/base
+incdir+../common/csb
+incdir+../common/dma
+incdir+../common/cbuf
+incdir+../common/cdma_sc
+incdir+../common/intr
+incdir+env
+incdir+seqs
+incdir+tests

// ---- vlibs cell / 断言闭包（其余由 -y 兜底）----
../../../outdir/nv_full/vmod/vlibs/CKLNQD12.v
../../../outdir/nv_full/vmod/vlibs/NV_CLK_gate_power.v
../../../outdir/nv_full/vmod/vlibs/NV_BLKBOX_SINK.v
../../../outdir/nv_full/vmod/vlibs/NV_BLKBOX_SRC0.v
../../../outdir/nv_full/vmod/vlibs/nv_assert_no_x.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_never.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_one_hot.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_zero_one_hot.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_at_time_interval.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_hold_throughout_event_interval.vlib

// ---- DUT：cdma 全部 + cbuf ----
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_CVT_cell.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_cvt.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_DC_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_dc.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_dma_mux.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_dual_reg.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_ctrl.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_pack.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_sg2pack_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_sg.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_img.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_regfile.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_shared_buffer.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_single_reg.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_slcg.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_status.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_cdma.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_WG_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_wg.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_WT_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_WT_sp_arb.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_wt.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_WT_wgs_fifo.v
../../../outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_WT_wrr_arb.v
../../../outdir/nv_full/vmod/nvdla/cbuf/NV_NVDLA_cbuf.v

// ---- 库目录兜底（vlibs cell + RAM 行为模型壳 + RAM 宏行为模型）----
-y ../../../outdir/nv_full/vmod/vlibs
-y ../../../outdir/nv_full/vmod/rams/synth
-y ../../../outdir/nv_full/vmod/rams/model
+libext+.v+.vlib

// ---- TB interface ----
../common/csb/csb_if.sv
../common/csb/csb_fanout_if.sv
../common/dma/dma_if.sv
../common/cbuf/cbuf_wr_if.sv
../common/cbuf/cbuf_rd_if.sv
../common/cbuf/cbuf_resp_if.sv
../common/cdma_sc/cdma_sc_if.sv
../common/cdma_sc/csc_cdma_if.sv
../common/sdp/sdp_if.sv
../common/intr/intr_if.sv

// ---- package ----
../common/nvdla_ut_pkg.sv
cdma_cbuf_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
