# =============================================================================
# common.mk : verif/ut/ 公共 make 片段
#   用例 Makefile 先定义 UT_NAME/TB_TOP/FILELIST/DEFAULT_TEST 再 include 本文件
#   变量全部 ?=，可被环境或 make 命令行覆盖
#   目标：build / run / check / wave / verdi / clean（run 依赖 build 并自动 check）
#   check 判定四连：UVM_FATAL==0、UVM_ERROR==0、无 "^ERROR :"（DUT 内建断言）、
#                  有 "UT RESULT: PASSED"，任一不满足非零退出
# =============================================================================

# ---- 可覆盖变量 ----
VCS_HOME        ?= /home/yian/Synopsys/vcs/V-2023.12-SP2
VERDI_HOME      ?= /home/yian/Synopsys/verdi/V-2023.12-SP2
NOVAS_HOME      ?= $(VERDI_HOME)
LM_LICENSE_FILE ?= 27000@localhost.localdomain
VCS_CC          ?= /usr/bin/g++
UVM_VER         ?= uvm-1.2
TEST            ?= $(DEFAULT_TEST)
SEED            ?= 1
UVM_VERBOSITY   ?= UVM_MEDIUM
WAVES           ?= 0
PLUSARGS        ?=

# WAVES 编译产物隔离，避免与非 WAVES 编译互相覆盖
ifeq ($(WAVES),1)
OUTDIR ?= out_waves
else
OUTDIR ?= out
endif

export VCS_HOME VERDI_HOME NOVAS_HOME LM_LICENSE_FILE

VCS   := $(VCS_HOME)/bin/vcs
VERDI := $(VERDI_HOME)/bin/verdi

# ---- 编译选项（组合沿用上游 verif/sim/Makefile 验证过的 + UT 附加）----
VCS_OPTS := -full64 -sverilog -timescale=1ns/1ps +vcs+lic+wait -cpp $(VCS_CC) \
  -ntb_opts $(UVM_VER) \
  +nospecify +notimingchecks \
  +define+VLIB_NO_UDP +define+PRAND_OFF +define+ASSERT_ON \
  +define+NO_PERFMON_HISTOGRAM +define+NVTOOLS_SYNC2D_GENERIC_CELL \
  +warn=noTFIPC +warn=noTMR \
  -Mdir=$(OUTDIR)/csrc -o $(OUTDIR)/simv -l $(OUTDIR)/compile.log

ifeq ($(WAVES),1)
VCS_OPTS   += -debug_access+all -kdb +define+WAVES_FSDB \
  -P $(VERDI_HOME)/share/PLI/VCS/LINUX64/novas.tab \
  $(VERDI_HOME)/share/PLI/VCS/LINUX64/pli.a
WAVE_ARGS  := +fsdb +fsdbfile=$(OUTDIR)/waves.fsdb
endif

LOG      := $(OUTDIR)/$(TEST)_seed$(SEED).log
SIM_OPTS := +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(UVM_VERBOSITY) \
  +ntb_random_seed=$(SEED) $(WAVE_ARGS) $(PLUSARGS)

# ---- 源文件依赖（任何一处改动触发重编）----
UT_SRCS := $(FILELIST) Makefile ../common.mk \
  $(wildcard ../common/*.sv) $(wildcard ../common/*/*.sv) $(wildcard ../common/*/*.svh) \
  $(wildcard *.sv) $(wildcard tb/*.sv) \
  $(wildcard env/*.svh) $(wildcard seqs/*.svh) $(wildcard tests/*.svh)

.PHONY: build run check wave verdi clean

build: $(OUTDIR)/simv

$(OUTDIR)/simv: $(UT_SRCS)
	@mkdir -p $(OUTDIR)
	$(VCS) $(VCS_OPTS) -f $(FILELIST) -top $(TB_TOP)

run: build
	./$(OUTDIR)/simv -l $(LOG) $(SIM_OPTS)
	@$(MAKE) --no-print-directory check TEST=$(TEST) SEED=$(SEED) WAVES=$(WAVES)

check:
	@test -f $(LOG) || { echo "CHECK FAILED: no log $(LOG)"; exit 1; }
	@status=0; \
	grep -Eq '^UVM_FATAL[[:space:]]*:[[:space:]]*0([[:space:]]|$$)' $(LOG) \
	  || { echo "CHECK: UVM_FATAL != 0 (or summary missing)"; status=1; }; \
	grep -Eq '^UVM_ERROR[[:space:]]*:[[:space:]]*0([[:space:]]|$$)' $(LOG) \
	  || { echo "CHECK: UVM_ERROR != 0 (or summary missing)"; status=1; }; \
	! grep -q '^ERROR :' $(LOG) \
	  || { echo "CHECK: DUT built-in assertion ERROR found"; status=1; }; \
	grep -q 'UT RESULT: PASSED' $(LOG) \
	  || { echo "CHECK: no 'UT RESULT: PASSED' banner"; status=1; }; \
	if [ $$status -eq 0 ]; then echo "CHECK PASSED: $(LOG)"; \
	else echo "CHECK FAILED: $(LOG)"; fi; \
	exit $$status

wave: verdi
verdi:
	$(VERDI) -ssf $(OUTDIR)/waves.fsdb -dbdir $(OUTDIR)/simv.daidir &

clean:
	rm -rf out out_waves csrc simv* ucli.key vc_hdrs.h novas.* verdiLog \
	  *.fsdb *.log .inter.vpd.uvm DVEfiles
