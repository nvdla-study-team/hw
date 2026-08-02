# NV_NVDLA_CDMA_img

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_img.v`

## 1. 模块定位

`NV_NVDLA_CDMA_img` 是 CDMA 的 image 输入通道顶层。它处理：

```text
reg2dp_conv_mode     = DIRECT
reg2dp_datain_format = PIXEL
```

这里的 image 不是一种新的卷积算法，而是一种输入内存布局。软件可以把首层网络的 RGB、RGBA、YUV 等原始像素直接交给 NVDLA；IMG 通道负责理解像素格式、搬运并整理成 CBUF 能接收的布局。

## 2. 顶层结构

本模块自身几乎不计算，主要实例化三个子模块并连接信号：

```text
                         +--------------------+
reg2dp 配置 ------------>| IMG_ctrl           |
                         | 状态机和格式解析   |
                         +-----+----------+---+
                               |          |
                               v          v
DRAM/MCIF/CVIF <-------> IMG_sg -------> IMG_pack -------> CDMA_cvt -------> CBUF
                          |   ^             |
                          v   |             |
                       shared_buffer <------+
```

三个子模块的分工：

| 子模块 | 主要职责 |
|---|---|
| `IMG_ctrl` | 判断 IMG 是否启用，管理层状态，解析 pixel format，预计算地址和边界参数 |
| `IMG_sg` | 生成 DMA 请求，匹配 response，初步重排像素，并写 shared buffer |
| `IMG_pack` | 读 shared buffer，合并 plane，生成 padding/mean 信息和 CBUF 写地址，送 CVT |

## 3. 完整数据流

### 3.1 配置阶段

层开始时，`IMG_ctrl` 锁存寄存器配置，并把 `reg2dp_pixel_format` 翻译成内部控制量，例如：

- `pixel_planar`：是否有两个独立 plane；
- `pixel_order`：DMA 返回的分量需要怎样换位；
- `pixel_precision`：像素是 8 bit、16 bit 或 FP16；
- `pixel_packed_10b`：是否为 10 bit packed 格式；
- 左右边界 burst、byte shift、bundle limit；
- `pixel_bank = reg2dp_data_bank + 1`：IMG 可以使用的 CBUF data bank 数。

这些量同时送给 `IMG_sg` 和 `IMG_pack`，让取数端和组包端使用同一套格式解释。

### 3.2 DMA 和 shared buffer 阶段

`IMG_sg` 按 plane、图像行和 burst 生成读请求：

```text
plane 0: base_addr_0 + y * line_stride
plane 1: base_addr_1 + y * uv_line_stride
```

DMA response 返回后，SG 根据请求 FIFO 中的元数据恢复当前 response 属于哪一行、哪个 plane、是否到达 bundle 末尾。随后它根据 `pixel_order` 做位段/分量重排，把 512 bit response 拆成两个 256 bit 端口写入 shared buffer。

### 3.3 SG 到 PACK 的交接

当一个可供 PACK 消费的 bundle 已完整写入 shared buffer 时，SG 向 `IMG_sg2pack_fifo` 写入：

```text
{layer_end, line_end, p1_burst[4:0], p0_burst[3:0]}
```

它不是像素数据，只是“这一组数据已经写好，应读多少 burst”的完成凭证。

### 3.4 PACK 和 CVT 阶段

`IMG_pack` 取出一条完成凭证后，按其中的 p0/p1 burst 数从 shared buffer 读取数据，然后：

1. 合并单 plane 或双 plane 数据；
2. 处理 8/10/16 bit 的打包差异；
3. 生成左右 padding mask；
4. 把每个通道的 mean 值复制并对齐到相应像素；
5. 生成 CBUF entry 地址、半区选择和写入信息；
6. 输出 `img2cvt_*` 给 `NV_NVDLA_CDMA_cvt`。

CVT 再执行真正的数值预处理，例如 mean subtraction、数据类型转换、缩放和截断，最后写 CBUF。

## 4. shared buffer 两侧是先后还是并行

从单个 bundle 看，顺序严格是：

```text
DMA response -> SG 重排并写完 -> sg2pack 凭证 -> PACK 读取 -> CVT
```

从整个层看，两侧是流水并行的：

```text
时刻 T0：SG 写 bundle 0
时刻 T1：PACK 读 bundle 0，同时 SG 写 bundle 1
时刻 T2：PACK 读 bundle 1，同时 SG 写 bundle 2
```

`IMG_sg2pack_fifo` 解耦了生产和消费速度，shared buffer 保存尚未被 PACK 消费的像素数据。

## 5. 它对 RGB/YUV 做了什么

IMG 不只是把 RGB 和普通 data 分开搬运。它确实理解像素存储格式，并做以下布局处理：

- 识别 RGBA、BGRA、ARGB 等分量顺序；
- 对 8/10/16 bit 分量进行抽取和重排；
- 对 Y 与 UV 分 plane 的格式分别取数后再组织；
- 生成通道对应的 mean 数据；
- 将图像行布局整理成后续 CBUF/CSC 可消费的 entry 布局。

但它不做 RGB 到 YUV 或 YUV 到 RGB 的颜色矩阵变换。Y、U、V 在这里仍被看成三个输入通道；软件和网络必须按照配置约定解释这些通道。

## 6. 与 DC 通道的区别

| 项目 | DC | IMG |
|---|---|---|
| 输入布局 | 已编排的 feature map | 原始或接近原始的 pixel surface |
| 格式理解 | 主要理解 feature surface | 理解 RGB/RGBA/YUV、planar、packed 10b |
| 数据重排 | 按 feature/atomic C 组织 | 先做像素分量抽取、换位、plane 合并 |
| padding/mean | 不承担 image 专用处理 | PACK 生成 pad mask 和逐通道 mean |
| 到 CVT 宽度 | 512 bit 半 entry | 1024 bit entry，并附 pad/mean 信息 |

## 7. 完成条件

IMG 通道完成需要两件事同时成立：

- `sg_is_done`：DMA 请求、response 和 SG 侧写入均结束；
- `pack_is_done`：最后一个带 `layer_end` 的 bundle 已被 PACK 输出。

`IMG_ctrl` 对两者求与并延迟若干拍，形成 `img_done`，再进入 `DONE` 状态等待 CDMA status 切层。

## 8. 阅读顺序

建议按以下顺序继续看源码：

1. `NV_NVDLA_CDMA_IMG_ctrl.v`：先理解模式和格式参数从哪里来；
2. `NV_NVDLA_CDMA_IMG_sg.v`：理解数据怎样从外存进入 shared buffer；
3. `NV_NVDLA_CDMA_IMG_pack.v`：理解数据怎样从 shared buffer 变成 CVT 输入；
4. 两个 FIFO：最后确认请求和 bundle 元数据怎样保持顺序。

