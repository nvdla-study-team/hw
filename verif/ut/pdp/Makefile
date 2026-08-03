# =============================================================================
# pdp UT : NV_NVDLA_pdp（平面池化单元：rdma + core + wdma + reg + nan + slcg）
#   make run                              # 默认跑 T0 寄存器冒烟
#   make run TEST=pdp_t0_reg_test SEED=2
# =============================================================================

UT_NAME      := pdp
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := pdp_t0_reg_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=pdp_t0_reg_test SEED=1
	$(MAKE) run TEST=pdp_t0_reg_test SEED=2
	@echo "REGRESS PASSED: pdp (t0 x2)"
