# =============================================================================
# cdma_cbuf UT : NV_NVDLA_cdma + NV_NVDLA_cbuf
#   make run                                    # 默认跑 T0 寄存器冒烟
#   make run TEST=cdma_cbuf_t0_reg_test SEED=2
# =============================================================================

UT_NAME      := cdma_cbuf
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := cdma_cbuf_t0_reg_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=cdma_cbuf_t0_reg_test   SEED=1
	$(MAKE) run TEST=cdma_cbuf_t1_smoke_test SEED=1
	$(MAKE) run TEST=cdma_cbuf_t2_odd_tail_test SEED=1
	$(MAKE) run TEST=cdma_cbuf_t3_random_test SEED=1
	$(MAKE) run TEST=cdma_cbuf_t3_random_test SEED=2
	$(MAKE) run TEST=cdma_cbuf_t3_random_test SEED=3
	$(MAKE) run TEST=cdma_cbuf_t5_buffer_full_test SEED=1
	$(MAKE) run TEST=cdma_cbuf_t6_pingpong_test SEED=1
	@echo "REGRESS PASSED: cdma_cbuf (t0 + t1 + t2 + t3 x3 + t5 + t6)"
