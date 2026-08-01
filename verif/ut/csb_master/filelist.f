// -----------------------------------------------------------------------------
// filelist.f : csb_master UT 编译清单（路径相对 verif/ut/csb_master/）
//   顺序：incdir -> vlibs cell 闭包 -> DUT（FIFO 在前）-> -y 兜底 ->
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

// ---- vlibs cell / 断言闭包（显式列出，已核实）----
../../../outdir/nv_full/vmod/vlibs/CKLNQD12.v
../../../outdir/nv_full/vmod/vlibs/NV_CLK_gate_power.v
../../../outdir/nv_full/vmod/vlibs/NV_BLKBOX_SINK.v
../../../outdir/nv_full/vmod/vlibs/NV_BLKBOX_SRC0.v
../../../outdir/nv_full/vmod/vlibs/p_SSYNC3DO_C_PPP.v
../../../outdir/nv_full/vmod/vlibs/p_STRICTSYNC3DOTM_C_PPP.v
../../../outdir/nv_full/vmod/vlibs/nv_assert_no_x.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_never.vlib
../../../outdir/nv_full/vmod/vlibs/nv_assert_zero_one_hot.vlib

// ---- DUT（异步 FIFO 两件在前）----
../../../outdir/nv_full/vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_csb2falcon_fifo.v
../../../outdir/nv_full/vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_falcon2csb_fifo.v
../../../outdir/nv_full/vmod/nvdla/csb_master/NV_NVDLA_csb_master.v

// ---- 库目录兜底 ----
-y ../../../outdir/nv_full/vmod/vlibs
+libext+.v+.vlib

// ---- TB interface ----
../common/csb/csb_if.sv
../common/csb/csb_fanout_if.sv
../common/dma/dma_if.sv
../common/cbuf/cbuf_wr_if.sv
../common/cbuf/cbuf_rd_if.sv
../common/cdma_sc/cdma_sc_if.sv
../common/intr/intr_if.sv

// ---- package ----
../common/nvdla_ut_pkg.sv
csb_master_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
