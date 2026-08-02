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

