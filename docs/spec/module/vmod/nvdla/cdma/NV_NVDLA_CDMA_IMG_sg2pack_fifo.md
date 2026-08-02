# NV_NVDLA_CDMA_IMG_sg2pack_fifo

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_sg2pack_fifo.v`

## 1. 模块定位

`NV_NVDLA_CDMA_IMG_sg2pack_fifo` 保存 SG 已写完、等待 PACK 从 shared buffer 读取的 bundle 描述。

```text
SG 写完 bundle
      |
      v
sg2pack FIFO：保存 burst 数和边界
      |
      v
PACK 按描述读取 shared_buffer
```

它只传控制信息，真正的像素数据留在 shared buffer 中。

## 2. 规格和 packet

| 项目 | 值 |
|---|---|
| 深度 | 128 entries |
| 宽度 | 11 bit |
| 存储体 | `NV_NVDLA_CDMA_IMG_sg2pack_fifo_flopram_rwsa_128x11` |

packet 位定义：

| 位 | 字段 | PACK 的用途 |
|---|---|---|
| `[3:0]` | `p0_burst` | 读取 image plane 0 对应的数据量 |
| `[8:4]` | `p1_burst` | 读取 image plane 1 对应的数据量 |
| `[9]` | `line_end` | 更新行/sub-height 和 status 边界 |
| `[10]` | `layer_end` | 识别整层最后一个 bundle |

## 3. 入队时机

```verilog
sg2pack_push_req = rsp_img_bundle_done_d1;
```

只有 SG 确认该 bundle 的 response 已经整理并写入 shared buffer 后才入队。因此 FIFO 中每条记录也是一张“数据可读”的凭证。

RTL 断言入队时 FIFO 必须 ready。系统通过前面的容量控制保证不会无条件写爆 FIFO。

## 4. 出队握手

SG 顶层连接为：

```verilog
sg2pack_img_pvld = sg2pack_pop_req;
sg2pack_img_pd   = sg2pack_pop_data;
sg2pack_pop_ready = sg2pack_img_prdy;
```

这里：

- `pop_req` 相当于 FIFO 输出 valid；
- `sg2pack_img_prdy` 由 PACK 给出；
- 二者同时为 1 时，当前 bundle 描述出队。

PACK 会在相关 shared buffer 读取推进到 sub-height 末尾后才给 ready，所以 packet 在整个处理期间保持在 FIFO 头部。

## 5. 为什么不能只传一个 done 脉冲

一个脉冲只能说明“有东西写好了”，不能说明：

- plane 0 和 plane 1 各有多少 burst；
- 是否到达图像行末；
- 是否到达整层末尾；
- PACK 暂停时如何保存多个连续完成事件。

FIFO 同时保存事件和参数，并允许 SG、PACK 以不同速率运行。

## 6. 与 shared buffer 的关系

可以把二者看成一对：

```text
shared buffer        = 数据队列
sg2pack FIFO         = 数据队列中每个 bundle 的目录
```

SG 先写数据再写目录；PACK 先读目录，再按目录读数据。只要两边都保持顺序，就不需要在每个 256-bit RAM word 中附带大量控制位。

## 7. 实现细节

本文件包含 FIFO 控制和一个 128x11 flop-RAM 子模块，具有占用计数、读写指针、满/空控制和时钟门控。仿真可通过 `wr_limit` 缩小深度以验证背压行为。

它与 `IMG_fifo` 深度和宽度相同，但存储内容、入队时机和消费者完全不同，不能互换理解。

