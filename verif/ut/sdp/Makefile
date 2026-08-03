# =============================================================================
# sdp UT : NV_NVDLA_sdp（后处理单元：mrdma/brdma/nrdma/erdma + core + wdma + reg）
#   make run                              # 默认跑 T0 寄存器冒烟
#   make run TEST=sdp_t0_reg_test SEED=2
#   阶段4 环境版：仅 T0（寄存器面自证环境），数据通路测试待后续 Wave
# =============================================================================

UT_NAME      := sdp
TB_TOP       := tb_top
FILELIST     := filelist.f
DEFAULT_TEST := sdp_t0_reg_test

include ../common.mk

.PHONY: regress
regress:
	$(MAKE) run TEST=sdp_t0_reg_test SEED=1
	$(MAKE) run TEST=sdp_t0_reg_test SEED=2
	@echo "REGRESS PASSED: sdp (t0 x2)"
