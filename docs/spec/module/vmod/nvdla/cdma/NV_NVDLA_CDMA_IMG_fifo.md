# NV_NVDLA_CDMA_IMG_fifo

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_fifo.v`

## 1. 模块定位

`NV_NVDLA_CDMA_IMG_fifo` 是 SG 内部的 DMA 请求元数据 FIFO。它不保存 512-bit 像素数据，只保存每笔请求对应的 11-bit 描述信息。

```text
请求被接受 -> 元数据入 FIFO -> 等待 DMA response -> 元数据出 FIFO
```

## 2. 规格

| 项目 | 值 |
|---|---|
| 深度 | 128 entries |
| 宽度 | 11 bit |
| 存储体 | `nv_ram_rwsp_128x11` |
| 时钟 | `nvdla_core_clk` |
| 接口 | ready/valid 风格的 `wr_req/wr_ready`、`rd_req/rd_ready` |

11-bit 数据在 SG 中解释为：

```text
{planar, req_end, line_end, bundle_end, line_start, is_dummy, size[4:0]}
```

## 3. 为什么需要它

DMA 请求和 response 之间可能隔很多周期，而且可以同时存在多笔未完成请求。response 数据包不会重复携带 IMG 内部的 plane、line、bundle 等控制信息。

由于 MCIF/CVIF 保持该通道内的返回顺序，FIFO 可用相同顺序把请求属性重新附着到 response 上。response 侧依据 `size` 消耗完一笔请求后，才弹出下一条。

## 4. 握手语义

- `wr_req & wr_ready`：一笔请求元数据成功入队；
- `rd_req`：FIFO 非空，头部元数据有效；
- `rd_ready`：SG response 侧已处理完头部请求，可以出队；
- FIFO 满时 `wr_ready=0`，SG 必须停止继续发请求。

本模块的命名容易误读：`rd_req` 实际相当于输出 valid，`rd_ready` 是消费者 ready。

## 5. dummy 请求

dummy 请求不访问外存，但仍写入本 FIFO。response 控制看到 `is_dummy` 后生成零数据，并按普通请求相同方式推进 line/bundle 状态。

这样 padding 不需要另一套独立状态机，同时仍能保持真实请求与图像位置严格对齐。

## 6. 实现细节

FIFO 包含读写指针、占用计数、满/空判断和 RAM 时钟门控。仿真配置可用 `wr_limit` 人为缩小有效深度以制造背压；这不是正常硬件运行时的数据格式功能。

`pwrbus_ram_pd` 传给 RAM 宏，用于存储体功耗控制。

## 7. 与 sg2pack FIFO 的区别

| FIFO | 保存对象 | 生产时刻 | 消费者 |
|---|---|---|---|
| `IMG_fifo` | 每笔 DMA 请求的元数据 | 请求发出时 | SG response 处理 |
| `IMG_sg2pack_fifo` | 每个完整 bundle 的读取说明 | shared buffer 写完时 | PACK |

前者解决 request/response 匹配，后者解决 SG/PACK 流水解耦。

