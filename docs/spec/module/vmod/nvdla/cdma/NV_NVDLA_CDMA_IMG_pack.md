# NV_NVDLA_CDMA_IMG_pack

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_pack.v`

## 1. 模块定位

`IMG_pack` 位于 shared buffer 与 CDMA CVT 之间。SG 已经把 DMA response 的基本分量顺序整理好并写入 shared buffer；PACK 再把这些临时数据组织成一个完整的 CBUF entry 写事务。

```text
sg2pack bundle 元数据
          |
          v
shared_buffer 读控制 -> plane/位宽组包 -> padding/mean 对齐
                                      |
                                      v
                    CBUF 地址与 info 生成 -> img2cvt_*
```

## 2. 输入和输出

### 2.1 来自 SG 的 bundle 元数据

`sg2pack_img_pd[10:0]` 解码为：

| 位 | 字段 | 含义 |
|---|---|---|
| `[3:0]` | `img_p0_burst` | 本 bundle 的 image plane 0 数据量 |
| `[8:4]` | `img_p1_burst` | 本 bundle 的 image plane 1 数据量 |
| `[9]` | `img_line_end` | 本 bundle 位于图像行末 |
| `[10]` | `img_layer_end` | 本 bundle 是整层最后一组 |

### 2.2 shared buffer 读口

```verilog
img2sbuf_p0_rd_en/addr/data[255:0]
img2sbuf_p1_rd_en/addr/data[255:0]
```

PACK 根据 bundle 中的 burst 数产生读地址，并跟踪当前读的是 image plane 0 还是 plane 1、当前 sub-height 和行边界。

### 2.3 到 CVT 的输出

```verilog
img2cvt_dat_wr_en
img2cvt_dat_wr_addr[11:0]
img2cvt_dat_wr_hsel
img2cvt_dat_wr_data[1023:0]
img2cvt_dat_wr_pad_mask[127:0]
img2cvt_dat_wr_info_pd[11:0]
img2cvt_mn_wr_data[1023:0]
```

IMG 一次可以给出 1024-bit 完整 entry，同时带 128-bit lane mask 和对齐后的 mean。CVT 根据这些附加信息逐 lane 做数值预处理。

## 3. 为什么还需要 PACK

外存中的图像以“像素”为中心，而卷积硬件以“通道原子和 CBUF entry”为中心。例如外存可能是：

```text
R0 G0 B0 A0 | R1 G1 B1 A1 | ...
```

或：

```text
plane 0: Y0 Y1 Y2 ...
plane 1: U0 V0 U1 V1 ...
```

CSC 后续需要在同一空间位置读取输入通道并形成卷积窗口。PACK 的任务是把这些不同来源、位宽和边界的数据装进固定宽度 entry，并明确哪些 lane 有效。

## 4. bundle 握手

PACK 看到 `sg2pack_img_pvld` 后开始读取该 bundle。它不会立即拉高 ready；关键条件是：

```verilog
sg2pack_img_prdy = rd_vld & rd_sub_h_end;
```

也就是与该元数据对应的 shared buffer 读操作走到 sub-height 末尾后，才真正消费 FIFO 头。这样 SG 给出的 burst 数在整个读取期间保持稳定。

## 5. shared buffer 读控制

读侧根据以下层次推进：

```text
bundle -> sub-height -> plane -> burst -> 256-bit RAM word
```

`pixel_planar=0` 时只读单 surface；`pixel_planar=1` 时先后处理两个 image plane。RTL 检查双 plane 的 p0/p1 burst 比例，防止软件配置的两平面几何关系不一致。

这里存在两个“p0/p1”概念：

- `img_p0_burst/img_p1_burst`：image plane 0/1 的数据量；
- `img2sbuf_p0/p1_rd_*`：shared buffer 两个 256-bit RAM 读端口。

名字相似，但一个是图像格式维度，一个是物理 RAM 端口。

## 6. 数据组包

### 6.1 普通 8-bit/16-bit packed 数据

SG 已经把分量顺序换成内部约定，PACK 再根据 `pixel_precision`、`pixel_data_expand` 和 `pixel_data_shrink` 将连续字节放入正确 lane，并处理行末不足一个完整 entry 的部分。

“expand/shrink”在 PACK 中主要影响数据如何占据 1024-bit 总线以及何时需要扩展到额外 64/128-bit 区域。最终的数值饱和和截断仍由 CVT 完成。

### 6.2 packed 10-bit 数据

对于 `A2B10G10R10` 一类格式，一个像素的通道边界不落在 byte 边界上。PACK 使用专门的 10-bit merge 路径，将 SG 已重排的位段提取后放到内部 lane，并为无效 A2 或边界位置产生 mask。

所以 packed 10-bit 不能用普通的 8-bit byte shuffle 替代。

### 6.3 双 plane 数据

planar 格式的数据分多次写入内部暂存：先接收 plane 0，再按 `pixel_planar0_sft/pixel_planar1_sft` 对齐 plane 1。`pk_rsp_wr_cnt` 指示当前正在形成输出中的第几个分量组。

对 YUV planar 来说，这一步是把 Y surface 与 UV surface 的通道数据组织到统一 entry；它没有计算 RGB/YUV 颜色公式。

## 7. padding 处理

卷积 padding 表示输入张量边界之外的虚拟像素。IMG 没必要从 DRAM 读取这些位置，而是产生：

- 零数据；
- `img2cvt_dat_wr_pad_mask[127:0]`，指出 1024-bit entry 中哪些数据 lane 属于 padding。

CVT 用 mask 决定 padding lane 的处理。这样左右 padding 可以与真实像素一起形成规则的 CBUF entry，CSC 不必为图像边缘使用完全不同的读取协议。

## 8. mean 数据对齐

软件可配置四个 mean：

```text
mean_ry, mean_gu, mean_bv, mean_ax
```

命名同时兼容 RGB 和 YUV：R/Y、G/U、B/V、A/X。PACK 根据当前像素格式把对应 mean 复制到与每个数据 lane 相同的位置，例如四通道路径等价于反复排列：

```text
{mean_ax, mean_bv, mean_gu, mean_ry}
```

输出为 `img2cvt_mn_wr_data[1023:0]`。

关键区别：PACK 只把 mean 与像素对齐，不执行 `pixel - mean`；减法发生在 CVT。

## 9. `img2cvt_dat_wr_info_pd`

内部 `pk_out_info_pd` 携带：

| 位 | 含义 |
|---|---|
| `[3:0]` | 有效 half/segment mask |
| `[4]` | interleave 标志 |
| `[5]` | 需要 64-bit 扩展 |
| `[6]` | 需要 128-bit 扩展 |
| `[7]` | mean 处理使能 |
| `[8]` | unsigned 输入标志 |
| `[11:9]` | sub-height 信息 |

CVT 使用这些字段选择数据拆分、符号解释和 mean 路径。它们不是写入 CBUF 的卷积数据，而是伴随数据的处理控制。

## 10. CBUF 写地址生成

PACK 以 `status2dma_wr_idx` 为当前可写 entry 起点，再结合：

- 当前 width/bundle 偏移；
- sub-height；
- `pixel_bank = reg2dp_data_bank + 1`；
- entry 起始、中间、结束位置；

生成 `img2cvt_dat_wr_addr` 和 `hsel`。地址到达分配给 data 的最后一个 bank 后回绕，不进入 weight bank 区域。

这一步只生成将来写 CBUF 的地址。真正的 `cdma2buf_dat_wr_*` 仍由 CVT 输出。

## 11. status 更新

当输出推进到约定的行/sub-height 边界，PACK 产生：

```verilog
img2status_dat_updt
img2status_dat_entries
img2status_dat_slices
```

`entries` 表示新写入多少 CBUF entry，`slices` 表示多少输入高度 slice 已可供 CSC 使用。status 据此通知 CSC，不必等整层图像全部搬完才开始卷积。

## 12. 完成条件

当一个有效输出同时携带 `layer_end` 时，`pack_is_done` 置位。它说明最后一个 bundle 已经离开 PACK，而不是仅仅写入 shared buffer。

IMG_ctrl 将 `pack_is_done` 与 `sg_is_done` 合并，确保外存侧和组包侧都已结束。

## 13. 本模块做与不做的边界

PACK 会做：

- shared buffer 读取调度；
- 单/双 plane 合并；
- 8/10/16-bit 布局组包；
- padding mask 生成；
- mean lane 对齐；
- CBUF entry 地址和 status 增量生成。

PACK 不会做：

- 外存 DMA 请求；
- RGB/YUV 颜色空间变换；
- mean subtraction、scale、truncate 的算术；
- 卷积窗口展开或 kernel 乘法。

数值预处理属于 CVT，窗口读取属于 CSC，乘加属于 CMAC。

