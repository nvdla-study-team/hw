# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# NVDLA v1 硬件仓库（nv_full）

NVDLA 深度学习加速器 v1 开源 RTL，固定 nv_full 配置（2048 int8 / 1024 int16 MAC）。团队学习与开发仓库：开发在 `developer` 分支（自 `nvdlav1` 拉出）；上游 `master`/`nv_small` 是分叉后的另一代码线。

## 常用命令（均已实测，2026-07）

前置（tmake 依赖的 perl 模块 YAML/IO::Tee 装在 ~/perl5）：

    export PERL5LIB=$HOME/perl5/lib/perl5

- 构建全部 RTL：`./tools/bin/tmake -build vmod_nvdla_top`（仓库根目录执行，产物进 outdir/nv_full/，日志 outdir/build.log）
- 构建单个单元：`./tools/bin/tmake -build vmod_nvdla_<unit>`（unit 如 sdp、cdma；加 `-only` 跳过依赖重建）
- 仿真：在 verif/sim/ 下 `make build` / `make run TESTDIR=../traces/traceplayer/sanity0`，**必须带本机路径覆盖串**，完整命令见 verif/CLAUDE.md
- 综合：`syn/scripts/syn_launch.sh -mode wlm -config <config.sh>` —— 未实测（本机尚无工艺库），见 syn/CLAUDE.md

## 架构指针

- 顶层 vmod/nvdla/top/NV_nvdla.v：5 种物理分区 6 个实例（c=卷积前端、m=MAC 阵列×2、a=累加、p=SDP、o=其余）
- 卷积数据流：cdma → cbuf → csc → cmac → cacc → sdp
- 完整地图：@docs/architecture.md

## 规矩（每条都有原因）

- vmod/ 源码要经 vcp（宏）+ eperl（插件）生成 outdir/ 下工具真正消费的 Verilog——永远改 vmod/ 后用 tmake 重建，严禁改 outdir/（重建即被覆盖，且不进 git）。
- 禁止从 master/nv_small merge（已分叉 382+ 提交，结构不兼容）；上游修复只可 cherry-pick。
- 仓库 Makefile 里写死的 /home/tools、/home/utils 是 NVIDIA 内部路径，本机一律用 make 命令行变量覆盖，不改上游 Makefile（保持与上游可 diff）。
- tree.make 是个人环境配置（gitignored，已按本机生成），勿提交、勿写死到文档以外的地方。

## 已知坑

- 系统 perl 缺 YAML/IO::Tee：不设 PERL5LIB 时 tmake 直接报 "Can't locate YAML.pm"。
- verif/sim/Makefile 的 `export VCS_HOME :=` 等赋值会压过环境变量，只有 make 命令行变量能覆盖。
- sanity 日志里 "could not find any golden ./*chiplib_dump.raw2" 是无害告警；判定只看 `checktest : PASSED`。
