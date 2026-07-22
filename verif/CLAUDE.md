# verif/ — VCS trace-player 验证环境

所有 make 在 verif/sim/ 下执行，**必须带本机覆盖串**（Makefile 写死的路径本机无效；已实测 2026-07）：

    OVR="VCS_HOME=$HOME/Synopsys/vcs/V-2023.12-SP2 VERDI_HOME=$HOME/Synopsys/verdi/V-2023.12-SP2 NOVAS_HOME=$HOME/Synopsys/verdi/V-2023.12-SP2 LM_LICENSE_FILE=27000@localhost.localdomain VCS_CC=/usr/bin/g++ PERL=/usr/bin/perl TEE=/usr/bin/tee"

- 编译：`make build $OVR`
- 单测：`make run TESTDIR=../traces/traceplayer/sanity0 $OVR`（判定唯一标准：`checktest : PASSED`）
- 波形：build/run 加 `DUMP=1 DUMPER=VERDI` 生成 fsdb；`make verdi DUMP=1 DUMPER=VERDI TESTDIR=... $OVR` 打开
- 短回归：`make regress MINIREGRESS=1 $OVR`（8 个短测试）

## 本目录规矩

- RTL 改动后先回根目录 tmake 重建 outdir，再 make build
- 测试 = traces/traceplayer/<name>/ 目录（CSB trace + 内存镜像），新用例照抄现有目录结构
- "could not find any golden ./*chiplib_dump.raw2" 是无害告警
