# =============================================================================
# cdp UT : NV_NVDLA_cdp（CDP_RDMA + CDP 双 CSB 块，纯内存到内存归一化引擎）
#   make run                          # 默认跑 T0 寄存器冒烟
#   make run TEST=cdp_t0_reg_test SEED=2
#   make regress                      # T0 x {seed1, seed2}
# =============================================================================

UT_NAME      := cdp
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := cdp_t0_reg_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=cdp_t0_reg_test SEED=1
	$(MAKE) run TEST=cdp_t0_reg_test SEED=2
	@echo "REGRESS PASSED: cdp (t0 x2 seeds)"
