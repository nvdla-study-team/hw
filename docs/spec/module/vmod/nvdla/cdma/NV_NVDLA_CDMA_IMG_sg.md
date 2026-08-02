# NV_NVDLA_CDMA_IMG_sg

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_sg.v`

## 1. 模块定位

`IMG_sg` 是 image 通道的 DMA scatter/gather 和 response 整理模块。它位于外存接口与 shared buffer 之间：

```text
MCIF/CVIF
   |
   v
DMA 请求/响应控制
   |
   v
像素分量初步重排
   |
   v
shared_buffer 写口
```

“SG”在这里可以理解为按图像行、plane 和 burst 生成分散地址，再把返回数据聚合成 PACK 可消费的 bundle。

## 2. 两条并行信息流

SG 内部必须同时保持数据和描述它的数据结构：

```text
数据流：DMA response -> 分量重排 -> shared_buffer
控制流：请求元数据 FIFO -> response 边界恢复 -> sg2pack FIFO
```

如果只有数据而没有元数据，512-bit response 本身无法说明它属于 plane 0 还是 plane 1、是否是一行末尾、还剩多少 atom。

## 3. CBUF 容量预约

发起一组 image DMA 之前，SG 检查：

```verilog
status2dma_free_entries >= total_required_entry
```

`img_entry_onfly` 记录已经获准取数、但尚未通过 `img2status_dat_updt` 正式入账的 entry。这样并发中的多个请求不会重复使用同一份 free entry。

原因是 CBUF 写端没有逐拍 `ready`。一旦外存读取开始，返回数据最终必须有位置可写，所以容量需要在发请求前预约。

## 4. DMA 请求生成

### 4.1 地址层次

SG 的计数器按以下层次推进：

```text
height/sub-height -> plane -> line -> section -> bundle -> burst
```

单 plane 格式只遍历 plane 0。双 plane 格式先后生成 plane 0 和 plane 1 的请求，但两者使用独立配置：

```text
plane 0 address = base_addr_0 + line_index * line_stride
plane 1 address = base_addr_1 + line_index * uv_line_stride
```

请求地址按 32 byte 对齐，`pd[63:0]` 为地址，`pd[78:64]` 为 0-based atom 数。

### 4.2 三种 request source

内部 request source 为：

| source | 含义 |
|---|---|
| `SRC_DUMMY` | padding 或边界所需的虚拟数据，不访问外存 |
| `SRC_P0` | plane 0 的真实 DMA 请求 |
| `SRC_P1` | plane 1 的真实 DMA 请求 |

dummy 请求仍会进入元数据 FIFO，但不会送 MCIF/CVIF。response 侧为它合成零数据和相同的边界推进，使真实数据和 padding 共用一套控制状态机。

### 4.3 MCIF/CVIF 选择

`reg2dp_datain_ram_type` 决定请求发往 MCIF 还是 CVIF。两路 response 在模块内部合并，RTL 断言它们不能同时有效。

## 5. 请求元数据 FIFO

每接受一个真实或 dummy 请求，`NV_NVDLA_CDMA_IMG_fifo` 保存 11 bit：

```text
{planar, req_end, line_end, bundle_end, line_start, is_dummy, size[4:0]}
```

字段作用：

| 字段 | response 侧用途 |
|---|---|
| `planar` | 判断返回数据属于 plane 0 还是 plane 1 |
| `req_end` | 当前请求最后一个 response beat 的边界 |
| `line_end` | 图像行结束标志 |
| `bundle_end` | 可以向 PACK 宣告一个 bundle 完成 |
| `line_start` | 首 burst 的 byte shift/边界处理 |
| `is_dummy` | 不等外存，生成零数据 |
| `size` | 该请求包含多少 32B atom |

FIFO 保证请求和 response 顺序对应，并吸收 DMA 往返延迟。

## 6. response 消费

DMA response packet 为：

```text
mask[1:0] + data[511:0]
```

每个 mask bit 对应一个 256-bit half/atom。response 侧结合 FIFO 头部的 `size` 计数：一笔请求的数据全部消耗后才弹出该条元数据。

当内部 shared buffer 写路径或元数据路径不能继续时，SG 拉低 response ready，向 MCIF/CVIF 施加反压。

## 7. 像素重排

response 数据进入 shared buffer 前，会根据 `pixel_order[10:0]` 从 11 种固定布线中选择一种。典型变化包括：

```text
外存：A R G B A R G B ...
内部：B G R A B G R A ...  （示意）
```

对 packed 10-bit，重排不是简单按 byte 交换，而是从每个 32-bit pixel 中抽取 A2/R10/G10/B10 位段再重新拼接。对 planar UV，则按 8-bit 或 16-bit 分量交换 U/V 次序。

这一阶段做的是物理位段整理，不做加减乘除，也不执行颜色空间矩阵。

## 8. 写 shared buffer

整理后的 512-bit 数据拆为两个 256-bit 写口：

```verilog
img2sbuf_p0_wr_en/addr/data
img2sbuf_p1_wr_en/addr/data
```

这里的 p0/p1 是 shared buffer 的两个物理端口，不应与 image plane 0/plane 1 混为一谈。image plane 描述源图像 surface；shared-buffer p0/p1 描述一次 512-bit 返回的两个 256-bit 存储半区。

## 9. SG 到 PACK 的 bundle FIFO

一个 bundle 的 response 全部写完后：

```verilog
sg2pack_push_req = rsp_img_bundle_done_d1;
```

压入的数据为：

| 位 | 字段 |
|---|---|
| `[3:0]` | `p0_burst` |
| `[8:4]` | `p1_burst` |
| `[9]` | `line_end` |
| `[10]` | `layer_end` |

PACK 只有拿到这条记录，才知道 shared buffer 中已有多少 plane 0/1 数据可读。`valid/ready` 握手允许 PACK 暂停，而 SG 继续填充后续 bundle，直到 FIFO 或 shared buffer 容量受限。

## 10. status 更新与完成

SG 在预定的数据组进入流水后向 status 输出：

```verilog
img2status_dat_updt
img2status_dat_entries
```

`sg_is_done` 要求：

```text
不是层开始首拍
并且全部 request 已生成
并且全部 response 已处理到层末
```

它只代表 SG 侧结束，不代表 PACK 已经把 shared buffer 中最后的数据送给 CVT，所以 IMG_ctrl 还要等待 `pack_is_done`。

## 11. 性能计数

- `dp2reg_img_rd_stall`：请求有效但 MCIF/CVIF 未 ready 的周期；
- `dp2reg_img_rd_latency`：有未完成读取期间累计的等待周期。

这些计数用于软件分析 image DMA 是否受内存带宽或仲裁限制。

## 12. 最容易混淆的点

1. SG 会做 RGB/YUV 分量的位段重排，因此不是纯地址发生器。
2. SG 不把最终数据直接送 CVT，而是先写 shared buffer。
3. 请求 FIFO 保存“每笔 DMA”的信息，sg2pack FIFO 保存“每个完整 bundle”的信息，两者粒度不同。
4. plane 0/1 是图像布局概念，shared-buffer p0/p1 是物理 256-bit 端口概念。
5. SG 完成不等于 IMG 层完成；PACK 还可能正在消费尾部数据。

