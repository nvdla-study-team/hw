// -----------------------------------------------------------------------------
// filelist.f : pdp UT 编译清单（路径相对 verif/ut/pdp/）
//   顺序：incdir -> vlibs cell/断言闭包 -> DUT（pdp 全部 23 件，顶层最后）->
//         -y 兜底（vlibs + rams/synth + rams/model）-> interface -> 公共 pkg ->
//         用例 pkg -> tb
//   注：pdp 源无 DW_*/DESIGNWARE 引用（2026-08 实测 grep 零命中），故不带
//       +define+DESIGNWARE_NOEXIST、不列 NV_DW_* 替身（与 csc_cmac_cacc 不同）
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

// ---- DUT：pdp 全部（顶层 NV_NVDLA_pdp.v 最后）----
../../../outdir/nv_full/vmod/nvdla/pdp/cal1d_fp16_pool_sum.v
../../../outdir/nv_full/vmod/nvdla/pdp/fp16_4add.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_CORE_cal1d.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_CORE_cal2d.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_CORE_preproc.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_CORE_unit1d.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_core.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_nan.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_REG_single.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_RDMA_reg.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_rdma.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_REG_single.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_reg.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_slcg.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_WDMA_cmd.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_WDMA_dat.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_PDP_wdma.v
../../../outdir/nv_full/vmod/nvdla/pdp/NV_NVDLA_pdp.v

// ---- 库目录兜底（vlibs cell + RAM 行为模型壳 + RAM 宏行为模型）----
-y ../../../outdir/nv_full/vmod/vlibs
-y ../../../outdir/nv_full/vmod/rams/synth
-y ../../../outdir/nv_full/vmod/rams/model
+libext+.v+.vlib

// ---- TB interface（照老 UT filelist 现列全集）----
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
pdp_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
