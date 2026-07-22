# vmod/ — RTL 源码（预处理前）

此处 .v/.vlib 是 vcp+eperl 的**输入**，不是工具消费的最终 Verilog（那在 outdir/nv_full/vmod/）。

- 单元重建（仓库根目录）：`PERL5LIB=$HOME/perl5/lib/perl5 ./tools/bin/tmake -build vmod_nvdla_<unit>`
- NVDLA_* 宏由 outdir/nv_full/spec/defs/project.h 注入，源头是 spec/defs/nv_full.spec
- eperl 插件：plugins/{assert,flop,pipe,retime}.pm

## 本目录规矩

- 跨分区接口改动必须同步 nvdla/top/ 的分区包装（NV_NVDLA_partition_*.v）与 NV_NVDLA_RT_* retiming 级
- rams/model（仿真行为模型）与 rams/synth（综合包装）接口要保持一致
