// -----------------------------------------------------------------------------
// filelist.f : cdp UT 编译清单（路径相对 verif/ut/cdp/）
//   顺序：incdir -> vlibs cell/断言闭包 -> DUT（cdp 全部 31 件，顶层最后）->
//         -y 兜底（vlibs + rams/synth + rams/model）-> interface -> 公共 pkg ->
//         用例 pkg -> tb
//   注意：cdp 源无 DW_*/DESIGNWARE 引用（已实测 grep），故不带
//   +define+DESIGNWARE_NOEXIST、不列 NV_DW_* 替身（与 csc_cmac_cacc 的差异点）
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

// ---- DUT：cdp 全部（子模块前、顶层 NV_NVDLA_cdp.v 最后）----
../../../outdir/nv_full/vmod/nvdla/cdp/fp_format_cvt.v
../../../outdir/nv_full/vmod/nvdla/cdp/fp_sum_block.v
../../../outdir/nv_full/vmod/nvdla/cdp/int_sum_block.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_bufferin.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_cvtin.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_cvtout.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_INTP_unit.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_intp.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_LUT_CTRL_unit.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_LUT_ctrl.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_lut.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_MUL_unit.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_mul.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_nan.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_sum.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_DP_syncfifo.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_dp.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_cq.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_eg.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_REG_single.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_reg.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_rdma.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_REG_single.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_reg.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_slcg.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_CDP_wdma.v
../../../outdir/nv_full/vmod/nvdla/cdp/NV_NVDLA_cdp.v

// ---- 库目录兜底（vlibs cell + RAM 行为模型壳 + RAM 宏行为模型）----
-y ../../../outdir/nv_full/vmod/vlibs
-y ../../../outdir/nv_full/vmod/rams/synth
-y ../../../outdir/nv_full/vmod/rams/model
+libext+.v+.vlib

// ---- TB interface（common 全集单列，全 UT 惯例）----
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
cdp_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
