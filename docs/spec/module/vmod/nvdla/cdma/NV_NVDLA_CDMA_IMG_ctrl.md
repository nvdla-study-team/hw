# NV_NVDLA_CDMA_IMG_ctrl

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_ctrl.v`

## 1. 模块定位

`IMG_ctrl` 是 IMG 通道的控制和参数预计算模块。它不搬运像素数据，主要完成三件事：

1. 判断当前层是否应由 IMG 通道执行；
2. 管理 `IDLE/PEND/BUSY/DONE` 生命周期；
3. 把软件寄存器中的 pixel format、宽度、offset 和 padding 翻译为 SG/PACK 可直接使用的硬件参数。

## 2. IMG 启用条件

核心条件是：

```verilog
img_en = reg2dp_op_en
       & (reg2dp_conv_mode == DIRECT)
       & (reg2dp_datain_format == PIXEL);
```

因此 IMG 只服务 direct convolution 的 pixel 输入。普通 feature 输入走 DC，Winograd feature 输入走 WG。

## 3. 主状态机

```verilog
IDLE = 2'b00;
PEND = 2'b01;
BUSY = 2'b10;
DONE = 2'b11;
```

| 当前状态 | 条件 | 下一状态 | 含义 |
|---|---|---|---|
| `IDLE` | `img_en & need_pending` | `PEND` | CBUF data bank 配置改变，先等待旧账清理 |
| `IDLE` | 正常 `img_en` | `BUSY` | 开始本层 IMG 取数 |
| `IDLE` | reuse 快捷条件 | `DONE` | 复用 CBUF 中已有 data，不重新取数 |
| `PEND` | `pending_req_end` | `BUSY` | pending 请求撤销，清账结束 |
| `BUSY` | `img_done` | `DONE` | SG 和 PACK 都完成 |
| `DONE` | `status2dma_fsm_switch` | `IDLE` | status 已完成层切换 |

`need_pending` 的判断是上一层和本层的 data bank 数是否不同。CBUF 的 data/weight 分区改变时，旧的 entry 计数不能直接沿用，所以 CDMA 必须先与 CSC/status 完成 pending 清账。

`pending_req_end = pending_req_d1 & ~pending_req` 检测 pending 请求的下降沿。等待下降沿而不是仅等待高电平，是为了确认对端已经看见请求并完成释放流程。

## 4. 完成判定

```text
sg_is_done   = 外存请求和返回处理结束
pack_is_done = 最后一组数据已经送出 PACK
```

只有二者都成立，数据才既“取完”又“排完”。RTL 将该条件经过三级、三级、三级流水延迟后形成 `img_done`，给最后的寄存器写入和状态更新留出收尾时间。

## 5. pixel format 的 CNN 含义

卷积输入最终是三维张量 `H x W x C`，但摄像头或图像文件常按像素保存：

```text
RGB interleaved: R0 G0 B0, R1 G1 B1, ...
RGBA packed:     一个 32-bit word 保存一个像素
YUV planar:      Y 平面和 UV 平面使用不同基地址/stride
```

CMAC 不按文件里的字节顺序工作。它需要在每个空间位置拿到固定通道顺序的数值向量。因此 IMG 必须先解释存储格式，再把分量整理成内部统一顺序。

## 6. 格式解析结果

### 6.1 `pixel_precision`

内部编码用于描述输入分量：

| 编码 | 含义 |
|---|---|
| `0` | 8-bit 像素分量 |
| `1` | 16-bit unsigned/int 类格式 |
| `2` | 16-bit signed 类格式 |
| `3` | FP16 |

它不是最终 MAC 精度。`reg2dp_proc_precision` 才描述后续卷积处理精度，二者差异决定是否需要 expand/shrink。

### 6.2 `pixel_data_expand` 和 `pixel_data_shrink`

- `expand`：输入分量较窄而处理精度较宽，例如 INT8 输入进入 INT16 数据通路；
- `shrink`：输入分量较宽而处理精度较窄，例如 16-bit 像素进入 INT8 数据通路。

CTRL 只生成控制标志，真正的符号扩展、转换和截断在 PACK/CVT 后续路径中完成。

### 6.3 `pixel_uint`

`reg2dp_pixel_sign_override` 决定整数像素按 unsigned 还是 signed 解释。图像字节通常是 `0..255`，而网络计算可能使用有符号 INT8；CVT 会结合该标志和 offset/scale 完成数值域转换。

### 6.4 `pixel_planar`

`pixel_planar=0` 表示所有分量来自一个 surface；`pixel_planar=1` 表示 plane 0 和 plane 1 使用独立地址。例如 YUV semi-planar 中，Y 来自 plane 0，UV 来自 plane 1。

### 6.5 `pixel_order[10:0]`

这是 one-hot 式的数据换位选择。SG 针对不同格式预先生成 11 种位段排列，再由 `pixel_order` 选择一种。它覆盖：

- ABGR/ARGB/BGRA/RGBA 等 8-bit 顺序；
- 对应的 16-bit 顺序；
- A2B10G10R10 等 packed 10-bit 顺序；
- planar UV 的 8-bit/16-bit 顺序。

其目的只是统一内部通道次序，不是颜色空间转换。

## 7. 支持的格式类别

`reg2dp_pixel_format` 的合法范围为 0 到 35，主要分为：

| 类别 | 示例 | 特点 |
|---|---|---|
| 单通道 | `R8/R10/R12/R16/R16_F` | 一个像素一个有效分量 |
| 四分量 16-bit | `A16B16G16R16` | 每分量 16 bit |
| 四分量 8-bit | `A8B8G8R8`、`R8G8B8A8` | 一个像素通常 32 bit |
| packed 10-bit | `A2B10G10R10` | 四分量压在 32 bit 中 |
| 单 surface YUV | `A8Y8U8V8` 等 | Y/U/V 同一 surface |
| 双 plane YUV | `Y8___U8V8_N444` 等 | Y 与 UV 分开取数 |

RTL 只支持 pitch-linear mapping，并对非法 format、mapping、offset 和 burst 越界设置断言。

## 8. 行边界参数为什么复杂

DMA 地址按 32-byte atom 对齐，但一行的有效像素可能从 atom 中间开始，也可能在 atom 中间结束。再加上卷积 padding，一行被拆成：

```text
left partial burst | middle full bursts | right partial burst
```

CTRL 预计算以下参数：

- `*_byte_sft`：首个 atom 中需要跳过多少字节；
- `*_lp_burst` / `*_rp_burst`：左右部分需要多少 burst；
- `*_width_burst`：中间完整区域的长度；
- `*_bundle_limit`：多少 response atom 组成一个 PACK bundle；
- `*_sft`、mask：planar 数据合并时的位移和有效范围。

这样 SG 的运行时逻辑只需按计数器推进，不必每拍重新做复杂除法和边界推导。

## 9. 时钟门控和模式互斥

CTRL 记录上一层是否为 IMG，并输出 `slcg_img_gate_dc`、`slcg_img_gate_wg`。当 IMG 活跃时，DC/WG 的相关时钟可被关闭；反之亦然。这个逻辑保证三种 data 取数模式只激活当前需要的一条路径。

## 10. 本模块不做什么

- 不发 DMA 请求；
- 不接收或存储像素数据；
- 不执行 RGB/YUV 颜色矩阵；
- 不做 mean subtraction、scale 或 truncate；
- 不直接写 CBUF。

它产生的是后两级处理数据所需的“执行计划”。

