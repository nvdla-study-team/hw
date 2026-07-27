# =============================================================================
# csb_master UT
#   make run                                    # 默认跑 smoke
#   make run TEST=csb_master_random_test SEED=2
#   make regress                                # smoke + random x3 种子
# =============================================================================

UT_NAME      := csb_master
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := csb_master_smoke_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=csb_master_smoke_test  SEED=1
	$(MAKE) run TEST=csb_master_random_test SEED=1
	$(MAKE) run TEST=csb_master_random_test SEED=2
	$(MAKE) run TEST=csb_master_random_test SEED=3
	@echo "REGRESS PASSED: csb_master (smoke + random x3 seeds)"
