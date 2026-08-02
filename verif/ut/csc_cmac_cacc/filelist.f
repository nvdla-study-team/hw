// -----------------------------------------------------------------------------
// filelist.f : csc_cmac_cacc UT 编译清单（路径相对 verif/ut/csc_cmac_cacc/）
//   顺序：incdir -> vlibs cell 闭包 -> DUT（csc/cmac/cacc 全部 + retiming 4 件）->
//         -y 兜底（vlibs + rams/synth + rams/model）-> interface -> 公共 pkg ->
//         用例 pkg -> tb
// -----------------------------------------------------------------------------

// ---- 宏：本机无 Synopsys DesignWare 授权模型，cmac 内 DW_minmax/DW02_tree/
//      DW_lsd 用 vlibs 的 NV_DW_* 替身（同上游 verif/sim/Makefile
//      DESIGNWARE_NOEXIST=1 路径）----
+define+DESIGNWARE_NOEXIST

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
../../../outdir/nv_full/vmod/vlibs/NV_DW02_tree.v
../../../outdir/nv_full/vmod/vlibs/NV_DW_lsd.v
../../../outdir/nv_full/vmod/vlibs/NV_DW_minmax.v

// ---- DUT：csc 全部 ----
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_dl.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_dual_reg.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_pra_cell.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_regfile.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_SG_dat_fifo.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_sg.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_SG_wt_fifo.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_single_reg.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_slcg.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_csc.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_WL_dec.v
../../../outdir/nv_full/vmod/nvdla/csc/NV_NVDLA_CSC_wl.v

// ---- DUT：cmac 全部（单套源，A/B 双实例） ----
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_active.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_cfg.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_MAC_exp.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_MAC_mul.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_MAC_nan.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_mac.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_rt_in.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_rt_out.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_CORE_slcg.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_core.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_REG_dual.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_REG_single.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_CMAC_reg.v
../../../outdir/nv_full/vmod/nvdla/cmac/NV_NVDLA_cmac.v

// ---- DUT：cacc 全部 ----
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_assembly_buffer.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_assembly_ctrl.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_CALC_fp_48b.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_CALC_int16.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_CALC_int8.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_calculator.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_delivery_buffer.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_delivery_ctrl.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_dual_reg.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_regfile.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_single_reg.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_CACC_slcg.v
../../../outdir/nv_full/vmod/nvdla/cacc/NV_NVDLA_cacc.v

// ---- DUT：retiming（只这 4 件；csb RT 不进 tb，CSB 由 tb 直驱） ----
../../../outdir/nv_full/vmod/nvdla/retiming/NV_NVDLA_RT_csc2cmac_a.v
../../../outdir/nv_full/vmod/nvdla/retiming/NV_NVDLA_RT_csc2cmac_b.v
../../../outdir/nv_full/vmod/nvdla/retiming/NV_NVDLA_RT_cmac_a2cacc.v
../../../outdir/nv_full/vmod/nvdla/retiming/NV_NVDLA_RT_cmac_b2cacc.v

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
csc_cmac_cacc_ut_pkg.sv

// ---- 顶层 ----
tb/tb_top.sv
