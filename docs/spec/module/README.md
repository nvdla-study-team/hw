# RTL 模块说明索引

本目录按 RTL 源码层级镜像放置单个 `.v` 模块说明。

路径约定：

```text
vmod/nvdla/cdma/NV_NVDLA_CDMA_dma_mux.v
  -> docs/spec/module/vmod/nvdla/cdma/NV_NVDLA_CDMA_dma_mux.md
```

每篇模块说明只解释一个 RTL 文件，优先覆盖：

- 模块在上级单元中的位置；
- 主要输入/输出接口；
- 关键数据流；
- ready/valid、pipe、FIFO、状态机等协议点；
- 设计前提与断言保护；
- 容易误解的边界。

## 已整理模块

### CBUF

- `vmod/nvdla/cbuf/NV_NVDLA_cbuf.v`

### CDMA

- `vmod/nvdla/cdma/` 下 DC、IMG、CVT、status、shared buffer 和 DMA mux 等主模块

### CSC

- `NV_NVDLA_csc.v`：CSC 顶层架构与总数据通路
- `NV_NVDLA_CSC_sg.v`：序列生成、资源/credit 与操作包
- `NV_NVDLA_CSC_dl.v`：activation 读取、重排与广播
- `NV_NVDLA_CSC_wl.v`：weight/WMB 读取、展开与双半阵列分发
- `NV_NVDLA_CSC_WL_dec.v`：压缩权重位置恢复
- `NV_NVDLA_CSC_SG_dat_fifo.v` / `NV_NVDLA_CSC_SG_wt_fifo.v`：命令 FIFO
- `NV_NVDLA_CSC_pra_cell.v`：Winograd PRA
- `NV_NVDLA_CSC_regfile.v` / `single_reg.v` / `dual_reg.v`：寄存器乒乓
- `NV_NVDLA_CSC_slcg.v`：时钟门控

### CMAC

- `NV_NVDLA_cmac.v`：单个 8-kernel CMAC 半阵列顶层与 CSC/CACC 接口
- `NV_NVDLA_CMAC_core.v`：配置、输入重定时、8 路 kernel MAC、输出重定时和 20 组 SLCG
- `NV_NVDLA_CMAC_CORE_active.v`：INT8/INT16/FP16 操作数展开、mask、非零、指数和 NaN 预处理
- `NV_NVDLA_CMAC_CORE_mac.v`：单 kernel lane 的 64 路乘法、归约树和 Winograd 后加
- `NV_NVDLA_CMAC_CORE_MAC_mul.v`：Booth 乘法阵列与双 INT8/单 INT16、FP16 乘积
- `NV_NVDLA_CMAC_CORE_MAC_exp.v` / `MAC_nan.v`：FP16 指数对齐与 NaN 载荷传播
- `NV_NVDLA_CMAC_CORE_rt_in.v` / `rt_out.v`：CSC 输入和 CACC 输出流水重定时
- `NV_NVDLA_CMAC_CORE_cfg.v`：精度/模式快照与 Winograd 时钟使能
- `NV_NVDLA_CMAC_reg.v` / `REG_single.v` / `REG_dual.v`：CSB 寄存器和双组配置乒乓
- `NV_NVDLA_CMAC_CORE_slcg.v`：普通操作与 Winograd 专用时钟门控
