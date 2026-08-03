// -----------------------------------------------------------------------------
// filelist.f : sdp UT 编译清单（路径相对 verif/ut/sdp/）
//   顺序：incdir -> vlibs cell 闭包 -> DUT（sdp 全部 56 件，顶层最后）->
//         -y 兜底（vlibs + rams/synth + rams/model）-> interface -> 公共 pkg ->
//         用例 pkg -> tb
//   与 csc_cmac_cacc 的差异（实测 2026-08）：sdp 源无 DW_*/DESIGNWARE 引用，
//   不带 +define+DESIGNWARE_NOEXIST、不列 NV_DW_* 替身文件
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
+incdir+../common/sdp
+incdir+../common/sdp2pdp
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

// ---- DUT：sdp 全部（顶层 NV_NVDLA_sdp.v 最后）----
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_BRDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_BRDMA_EG_ro.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_BRDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_BRDMA_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_BRDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_brdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_cmux.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_c.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_core.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_x.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_core.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_cvt.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_dmapack.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_dppack.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_dpunpack.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_idx.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_inp.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_Y_lut.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_CORE_y.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_ERDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_ERDMA_EG_ro.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_ERDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_ERDMA_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_ERDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_erdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_EG_cmd.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_EG_din.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_EG_dout.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_MRDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_mrdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_NRDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_NRDMA_EG_ro.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_NRDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_NRDMA_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_NRDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_nrdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_RDMA_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_RDMA_REG_single.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_RDMA_reg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_rdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_REG_single.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_reg.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_cmd.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_DAT_in.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_DAT_out.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_dat.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_dmaif.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_WDMA_gate.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_SDP_wdma.v
../../../outdir/nv_full/vmod/nvdla/sdp/NV_NVDLA_sdp.v

// ---- 库目录兜底（vlibs cell + RAM 行为模型壳 + RAM 宏行为模型）----
-y ../../../outdir/nv_full/vmod/vlibs
-y ../../../outdir/nv_full/vmod/rams/synth
-y ../../../outdir/nv_full/vmod/rams/model
+libext+.v+.vlib

// ---- TB interface（nvdla_ut_pkg 引用的全集，与老 UT 一致）----
../common/csb/csb_if.sv
../common/csb/csb_fanout_if.sv
../common/dma/dma_if.sv
../common/cbuf/cbuf_wr_if.sv
../common/cbuf/cbuf_rd_if.sv
../common/cbuf/cbuf_resp_if.sv
../common/cdma_sc/cdma_sc_if.sv
../common/cdma_sc/csc_cdma_if.sv
../common/sdp/sdp_if.sv
../common/sdp2pdp/sdp2pdp_if.sv
../common/intr/intr_if.sv

// ---- package ----
../common/nvdla_ut_pkg.sv
sdp_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
