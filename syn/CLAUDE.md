# syn/ — DC 综合流程

入口：`scripts/syn_launch.sh -mode wlm|dct|dcg|de -config <config.sh>`（config 模板 templates/config.sh）。

- 本机 dc_shell（V-2023.12-SP3）在 PATH，license `SNPSLMD_LICENSE_FILE=27000@localhost.localdomain`
- **尚未跑通**：缺工艺库（TARGET_LIB/LINK_LIB/WIRELOAD_MODEL_NAME 未配置）。配好前不要宣称综合可用
- RTL 输入 = outdir/nv_full/（先在根目录 tmake 构建）
- 约束：cons/NV_NVDLA_partition_{a,c,m,o,p}.sdc，5 个物理分区分别综合

## 本目录规矩

- 改 SDC 必须在提交说明写清时序意图（先例：commit eb2564c）
- 个性化配置走自己的 config.sh，不改 scripts/ 流程逻辑
