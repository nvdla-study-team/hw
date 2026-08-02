# =============================================================================
# csc_cmac_cacc UT : NV_NVDLA_csc + RT_csc2cmac_a/b + NV_NVDLA_cmac x2 +
#                    RT_cmac_a2cacc/b + NV_NVDLA_cacc（卷积核心子流水线）
#   make run                                        # 默认跑 T0 寄存器冒烟
#   make run TEST=csc_cmac_cacc_t0_reg_test SEED=2
# =============================================================================

UT_NAME      := csc_cmac_cacc
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := csc_cmac_cacc_t0_reg_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=csc_cmac_cacc_t0_reg_test SEED=1
	$(MAKE) run TEST=csc_cmac_cacc_t0_reg_test SEED=2
	$(MAKE) run TEST=csc_cmac_cacc_t1_conv_test SEED=1
	$(MAKE) run TEST=csc_cmac_cacc_t2_clip_test SEED=1
	$(MAKE) run TEST=csc_cmac_cacc_t3_random_test SEED=1
	$(MAKE) run TEST=csc_cmac_cacc_t3_random_test SEED=2
	$(MAKE) run TEST=csc_cmac_cacc_t3_random_test SEED=3
	$(MAKE) run TEST=csc_cmac_cacc_t5_khalf_test SEED=1
	$(MAKE) run TEST=csc_cmac_cacc_t6_pingpong_test SEED=1
	@echo "REGRESS PASSED: csc_cmac_cacc (t0 + t1 + t2 + t3 x3 + t5 + t6)"
