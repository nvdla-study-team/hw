# NV_NVDLA_CDMA_wt

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_wt.v`

## 1. 模块定位

`NV_NVDLA_CDMA_wt` 是 CDMA 的权重取数引擎，负责把外存中的 weight，以及压缩模式需要的 WMB/WGS，搬到卷积前端可使用的位置。

主路径是：

```text
外部 MCIF/CVIF
  -> WT/WMB/WGS 三路请求生成
  -> 两级请求仲裁
  -> 一条 weight DMA 读接口
  -> response 按请求来源分流
     |-> WT  拼成 512 bit -> CBUF weight 区
     |-> WMB 拼成 512 bit -> CBUF bank15
     `-> WGS 拆成 32-bit group size -> WGS FIFO
  -> 按 kernel group 向 CSC 通告新增 kernels/entries
```

它与 data 侧 DC/WG/IMG 的共同点是都包含 DMA 请求、response、容量限制、CBUF 写入和 CSC 记账；主要区别是 WT 围绕 kernel group 和压缩权重组织数据，不经过 CDMA shared buffer 和 data CVT。

## 2. CNN 中的 weight 是什么

普通二维卷积可以写成：

```text
output[k, y, x]
  = sum(weight[k, c, ry, rx] * input[c, y+ry, x+rx])
```

其中：

- `k` 是输出 kernel/output channel；
- `c` 是输入 channel；
- `ry/rx` 是卷积核内部坐标；
- 一个 kernel 包含生成一个输出 channel 所需的全部权重。

同一个 kernel 会在输出 feature map 的许多 `(x,y)` 位置反复使用。因此 WT 先把一批 kernel 搬入 CBUF，CSC 再反复读取它们送到 CMAC，避免每个输出位置都访问外存。

NVDLA 按 kernel group 通告权重：

```text
INT8       : 一个普通 group 最多 32 个 kernel
INT16/FP16 : 一个普通 group 最多 16 个 kernel
```

RTL 对应：

```verilog
group_op = is_int8 ? reg2dp_weight_kernel[12:5]
                   : reg2dp_weight_kernel[12:4];
group = group_op + 1;
```

`reg2dp_weight_kernel` 是 kernel 数减一。INT8 每组 kernel 更多，是因为单个 INT8 权重只有 8 bit，相同计算/搬运宽度中可以容纳更多 kernel。

## 3. 非压缩和压缩模式

模式由以下配置决定：

```verilog
is_compressed = (reg2dp_weight_format == 1'b1);
```

### 3.1 非压缩模式

外存保存所有权重，包括值为零的权重：

```text
WT stream -> CBUF weight banks
```

本模式只有 WT 流真正工作，WMB 请求被直接标记完成，WGS 请求不启动。

每组应取得的 weight 大小可以直接由 `byte_per_kernel * 本组 kernel 数` 算出。

### 3.2 压缩模式

压缩模式包含三条逻辑流：

| 流 | 内容 | 最终去向 |
| --- | --- | --- |
| WT | 只保存非零的压缩 weight 数据 | CBUF weight 区 |
| WMB | 每个原始 weight 位置的非零 mask bit | CBUF bank15 |
| WGS | 每个 kernel group 压缩后实际有多少 weight byte | WT 内部 WGS FIFO |

例如原始权重为：

```text
[3, 0, 0, -2, 0, 5]
```

压缩表示可理解为：

```text
WT  = [3, -2, 5]
WMB = [1,  0, 0, 1, 0, 1]
```

仅凭 WT 数据无法知道 `-2` 原本位于第几个乘法位置，所以 CSC 还要读取 WMB。WGS 则告诉 WT 控制器“当前 kernel group 压缩后有多少字节”，用于判断本组何时取齐。

## 4. 主要接口

### 4.1 DMA 接口

```verilog
cdma_wt2mcif_rd_req_valid/ready/pd[78:0]
cdma_wt2cvif_rd_req_valid/ready/pd[78:0]

mcif2cdma_wt_rd_rsp_valid/ready/pd[513:0]
cvif2cdma_wt_rd_rsp_valid/ready/pd[513:0]
```

`reg2dp_weight_ram_type` 决定请求走 MCIF 还是 CVIF：

```text
0 -> CVIF
1 -> MCIF
```

WT 独占 CDMA 顶层的 weight DMA 接口，不经过 data 侧 `NV_NVDLA_CDMA_dma_mux`。

### 4.2 CBUF 写接口

```verilog
cdma2buf_wt_wr_en
cdma2buf_wt_wr_addr[11:0]
cdma2buf_wt_wr_hsel
cdma2buf_wt_wr_data[511:0]
```

CBUF 一个 entry 是 1024 bit，而 weight 写口每拍是 512 bit：

```text
hsel=0 -> 写 entry 低 512 bit
hsel=1 -> 写 entry 高 512 bit
```

### 4.3 与 CSC 的记账接口

CDMA 通知 CSC 新增可用权重：

```verilog
cdma2sc_wt_updt
cdma2sc_wt_kernels[13:0]
cdma2sc_wt_entries[11:0]
cdma2sc_wmb_entries[8:0]
```

CSC 消费后归还：

```verilog
sc2cdma_wt_updt
sc2cdma_wt_kernels[13:0]
sc2cdma_wt_entries[11:0]
sc2cdma_wmb_entries[8:0]
```

CBUF 本身没有 `ready` 和容量账本，所以 WT 必须根据这些更新自行限制预取。

## 5. 关键配置的真实值

多个寄存器采用 N-1 编码：

```verilog
byte_per_kernel = reg2dp_byte_per_kernel + 1;
data_bank       = reg2dp_data_bank + 1;
weight_bank     = reg2dp_weight_bank + 1;
kernel_num      = reg2dp_weight_kernel + 1;
```

`reg2dp_weight_bytes` 和 `reg2dp_wmb_bytes` 是 128B 粒度的总大小字段。三个地址分别为：

```text
reg2dp_weight_addr_high/low -> WT 基址
reg2dp_wmb_addr_high/low    -> WMB 基址
reg2dp_wgs_addr_high/low    -> WGS 基址
```

三者低地址都以 32B atom 对齐后送 DMA。

## 6. 主 FSM

状态定义：

```verilog
WT_STATE_IDLE = 2'b00;
WT_STATE_PEND = 2'b01;
WT_STATE_BUSY = 2'b10;
WT_STATE_DONE = 2'b11;
```

| 状态 | 含义 |
| --- | --- |
| `IDLE` | 等待当前配置组 `op_en` |
| `PEND` | CBUF bank 布局变化，等待与 CSC 完成旧账清理 |
| `BUSY` | 生成请求、接收 WT/WMB/WGS、写 CBUF、逐组通告 |
| `DONE` | weight 侧完成，等待 data 侧也完成后统一切层 |

主要跳转：

```text
IDLE + op_en + need_pending -> PEND
IDLE + op_en                -> BUSY
PEND + pending_req_end      -> BUSY
BUSY + fetch_done           -> DONE
DONE + status2dma_fsm_switch -> IDLE
```

复用的特殊路径：

```text
IDLE + op_en + weight_reuse + last_skip_weight_rls -> DONE
```

它表示上一层设置了 `skip_weight_rls`，旧 weight 没有被 CSC 释放；当前层又设置 `weight_reuse`，因此可以继续使用 CBUF 中的同一批 weight，不需要重新发 DMA 请求。

`fetch_done` 不是最后一个 DMA response 到达就立即产生。最后一个 kernel group 满足后，`status_done` 置位，RTL 再用 `status_done_cnt` 等待 8 个周期，让末尾 status/update 流水排空，然后进入 DONE。

## 7. pending 为什么存在

WT 的 pending 与 DMA backpressure 无关。它处理的是两层之间 CBUF bank 划分变化：

```verilog
need_pending = (last_data_bank   != reg2dp_data_bank) |
               (last_weight_bank != reg2dp_weight_bank);
```

weight 区起点依赖 data bank 数，终点又依赖 weight bank 数。任一配置变化，旧层的 weight entry、WMB entry、读写指针都不能直接套用到新布局。

握手过程：

```text
WT 进入 PEND
  -> cdma2sc_wt_pending_ack 拉高
  -> CSC 拉高 sc2cdma_wt_pending_req
  -> clear_all = pending_ack & pending_req
  -> 清 weight/WMB available 账本并重置写指针
  -> CSC 撤销 pending_req
  -> pending_req_end 检测下降沿
  -> WT 进入 BUSY
```

等待 request 下降沿，而不是只看到 request 拉高，是为了保证双方都完成了清账事务，不会在 CSC 仍认为“清账中”时开始新布局。

## 8. WT DMA 请求生成

外部请求包为：

```verilog
dma_rd_req_pd[63:0]  = dma_rd_req_addr;
dma_rd_req_pd[78:64] = dma_rd_req_size;
```

地址按 32B atom 对齐：

```verilog
dma_rd_req_addr = {dma_req_addr[58:0], 5'b0};
```

内部 `size` 表示实际请求的 32B atom 数，范围 1~8；送到外部的 size 是 N-1：

```verilog
size_out = size - 1;
```

单笔请求最多 8 atom，即 256B。第一笔请求还受基址在 256B 边界内的位置限制：

```verilog
wt_req_size_addr_limit = 8 - reg2dp_weight_addr_low[2:0];
```

这样一笔 DMA 请求不会跨越 256B 边界。后续地址按下一个 256B 对齐块推进。

`reg2dp_weight_bytes` 是 128B 粒度，因此换算成 32B atom 数时乘 4：

```verilog
wt_req_burst_cnt_w = {reg2dp_weight_bytes, 2'b0};
```

每次请求被流水接受后，从剩余 atom 数中减去当前请求 `size`，直至 `wt_req_done`。

## 9. WMB DMA 请求生成

WMB 地址生成与 WT 基本同构，但使用独立配置：

```text
基址 -> reg2dp_wmb_addr_high/low
总量 -> reg2dp_wmb_bytes
完成 -> wmb_req_done
```

同样满足：

- 32B atom 对齐；
- 单笔最多 8 atom/256B；
- 第一笔不跨 256B 边界；
- 外部 size 使用 N-1 编码。

非压缩模式下：

```verilog
wmb_req_done_w = (layer_st & ~is_compressed) ? 1'b1 : ...;
```

因此不会真的产生 WMB DMA 流量。

## 10. WGS 请求和 WGS FIFO

WGS 只在压缩模式使用。每个 kernel group 对应一个 32-bit group-size，表示该组压缩 WT 数据的字节数。

一笔 WGS DMA 请求固定读取一个 32B atom：

```verilog
wgs_req_size_d1     = 1;
wgs_req_size_out_d1 = 0;
```

一个 32B atom 可装 8 个 32-bit WGS：

```text
256-bit WGS response
  -> 8 * 32-bit group size
  -> 逐个写入 NV_NVDLA_CDMA_WT_wgs_fifo
```

RTL 将 `dma_rsp_data_p0[255:0]` 保存到 `wgs_local_data`，随后根据 `wgs_push_cnt[2:0]` 每拍右移 32 bit，依次产生 `wgs_push_data[31:0]`。

处理一个 kernel group 时，状态逻辑读取 FIFO 头 `wgs_pop_data`，把它累加到该组累计需要的 WT byte 数。当前组完成后 `status_update` 才弹出下一个 WGS。

WGS 只控制压缩 weight 的组边界，不写入 CBUF，也不直接交给 CSC。

## 11. 两级请求仲裁

三条逻辑请求最终共享一条 weight DMA 接口。

### 11.1 第一级：WMB 与 WT 的加权轮转

```text
WMB request --+
              +-> NV_NVDLA_CDMA_WT_wrr_arb -> WRR winner
WT request  --+
```

权重来自：

```verilog
reg2dp_arb_wmb
reg2dp_arb_weight
```

它们被扩展成 5 bit 送入仲裁器。加权轮转用于在两条大数据流同时活跃时分配 DMA 带宽，避免 WMB 或 WT 长期得不到服务。

### 11.2 第二级：WGS 固定高优先级

```text
WGS request ----+
                +-> NV_NVDLA_CDMA_WT_sp_arb -> DMA
WRR winner -----+
```

WGS 优先级高于 WT/WMB。原因不是 WGS 数据量大，而是它位于控制依赖链上：没有当前 group size，状态逻辑就不知道本组压缩 WT 需要取多少字节，整个按组通告会停住。

两级仲裁输出都带 `out_package` 和 `out_back_package`。如果下游因为 DMA `ready=0` 或请求信息 FIFO 满而反压，已仲出的包会暂存，`gnt_busy` 阻止新授权，恢复后先重放旧包，避免丢包和重排。

内部 68-bit 请求包为：

```text
{src[1:0], size[3:0], size_out[2:0], addr[58:0]}
```

来源编码：

```verilog
SRC_ID_WT  = 2'b00;
SRC_ID_WMB = 2'b01;
SRC_ID_WGS = 2'b10;
```

## 12. 请求信息 FIFO 和 response 分流

WT/WMB/WGS 共用 DMA response，回包自身没有“这是哪条内部流”的标签。因此每发出一笔请求，模块把以下信息写入 `NV_NVDLA_CDMA_WT_fifo`：

```verilog
dma_req_fifo_data = {dma_req_src, dma_req_size};
```

FIFO 头部提供：

```text
dma_rsp_src  -> 当前回包属于 WT/WMB/WGS
dma_rsp_size -> 当前请求应返回多少个 32B atom
```

DMA response 是：

```text
data[511:0] = p1[255:0] + p0[255:0]
mask[1:0]   = 两个 256-bit atom 分别是否有效
```

`dma_rsp_size_cnt` 累加 `mask[0] + mask[1]`。当前请求的 atom 全部返回后，`dma_rsp_fifo_ready` 弹出 FIFO，下一批 response 才使用下一笔请求的 `src/size`。

分流条件：

```verilog
wt_rsp_valid  = response_handshake & (dma_rsp_src == SRC_ID_WT);
wmb_rsp_valid = response_handshake & (dma_rsp_src == SRC_ID_WMB);
wgs_rsp_valid = response_handshake & (dma_rsp_src == SRC_ID_WGS);
```

该设计依赖 MCIF/CVIF 对同一客户端按请求顺序返回。模块也断言 MCIF 和 CVIF 不会同拍同时给 WT 返回数据。

还要注意一个 RTL 时序前提：`wt_rsp_valid/wmb_rsp_valid/wgs_rsp_valid` 直接使用 FIFO 头的 `dma_rsp_src`，没有再与 `dma_rsp_fifo_req`（FIFO 头有效）相与。因此 response 必须晚于请求握手和 FIFO 头建立。真实 MCIF/CVIF 往返延迟足够长；仿真 DMA slave 如果在请求后近乎零延迟回包，可能在 `src` 尚未有效时污染分流控制。

## 13. 为什么要有 256-bit local_data

CBUF weight 写口是 512 bit，但 DMA response 的 `mask` 允许一拍只有一个 256-bit atom 有效。WT 和 WMB 各有一个 256-bit 暂存寄存器：

```text
wt_local_data[255:0]
wmb_local_data[255:0]
```

以 WT 为例：

```text
本拍有两个有效 atom，且之前无残留
  -> {p1,p0} 直接形成 512 bit
  -> wt_cbuf_wr_vld_w=1

本拍只有一个有效 atom，且之前无残留
  -> 保存到 wt_local_data
  -> 暂不写 CBUF

之后又来一个有效 atom
  -> {new_atom, wt_local_data} 形成 512 bit
  -> 写 CBUF
```

RTL 用下面的数量判断完成拼接：

```verilog
wt_local_data_cnt = mask[0] + mask[1] + wt_local_data_vld;
wt_cbuf_wr_vld_w  = wt_rsp_valid & wt_local_data_cnt[1];
```

WMB 路径完全同构。这样无论 DMA burst 的首尾对齐和奇偶 atom 数怎样变化，写 CBUF 的数据流始终保持连续的 512-bit 半 entry 顺序。

## 14. FP16 weight 的处理

WT 不做类似 data CVT 的 scale/offset/truncate。INT8/INT16 weight 基本按位搬运；FP16 weight 保持 FP16 编码，但会检测 NaN/Inf。

一个 512-bit 写块包含 32 个 FP16 lane。每个 lane 检查：

```text
exponent 全 1，mantissa 非 0 -> NaN
exponent 全 1，mantissa 为 0 -> Inf
```

统计输出：

```verilog
dp2reg_nan_weight_num
dp2reg_inf_weight_num
```

计数器在新层开始时清零，溢出时饱和到全 1。

当 `reg2dp_nan_to_zero=1` 且处理精度为 FP16 时，`nan_pass=0`，RTL 使用 `wt_nan_mask` 把每个 NaN lane 的 16 bit 清零后再写 CBUF：

```verilog
wt_cbuf_wr_data_w = wt_cbuf_wr_data_ori_w & wt_nan_mask;
```

Inf 只统计，不被清零。这样做是因为 NaN 进入 CMAC 后会沿大量乘加传播，使整片输出变成 NaN；可选清零相当于把异常权重视作零权重。

## 15. CBUF weight 写指针

WT 使用 13-bit 半 entry 指针：

```text
idx[12:1] -> CBUF 12-bit entry 地址
idx[0]    -> hsel，选择低/高 512 bit
```

因此：

```verilog
cdma2buf_wt_wr_addr = wt_cbuf_wr_idx[12:1];
cdma2buf_wt_wr_hsel = wt_cbuf_wr_idx[0];
```

每次写 512 bit 后指针加一，所以访问顺序为：

```text
entry N low -> entry N high -> entry N+1 low -> entry N+1 high
```

真实 data bank 数是 `data_bank_w = reg2dp_data_bank + 1`，所以 weight 起点为：

```verilog
{data_bank_w, 9'b0}
```

也就是 data 区之后的第一个 bank。终点为：

```verilog
weight_bank_end = data_bank_w + weight_bank_w;
```

指针到达终点后回绕到 weight 起点，形成 weight bank 环形缓冲区。

例如：

```text
data_bank 配置值   = 3 -> 实际 data bank 数 = 4 -> bank0~3
weight_bank 配置值 = 1 -> 实际 weight bank 数 = 2 -> bank4~5

WT 写指针：bank4 -> bank5 -> 回到 bank4
```

## 16. WMB 在 CBUF 中的位置

WMB 使用另一条 13-bit 半 entry 指针：

```verilog
wmb_cbuf_wr_idx = {4'hf, offset[8:0]};
```

高 4 bit 恒为 `4'hf`，所以 WMB 固定写入 CBUF bank15。低 9 bit 覆盖该 bank 的：

```text
256 entry * 2 half/entry = 512 个 512-bit 半 entry
```

压缩模式下必须给 WMB 留出 bank15，因此配置断言要求：

```text
非压缩：data_bank_count + weight_bank_count <= 16
压缩  ：data_bank_count + weight_bank_count <= 15
```

非压缩时没有 WMB，普通 weight 区可以使用到 bank15；压缩时普通 WT 最多使用到 bank14，bank15 专供 WMB。

## 17. WT/WMB/flush 写口复用

三种来源共用唯一的 CBUF weight 写口：

```text
WT 512-bit write  ----+
WMB 512-bit write ----+-> cdma2buf_wt_wr_*
flush zero write  ----+
```

组合选择优先级是：

```text
WT > WMB > flush
```

正常运行要求三者不在同一拍请求，RTL 有 WT/WMB、WT/flush、WMB/flush 冲突断言。优先级用于形成确定的组合输出，并不意味着发生冲突后被压住的一方会自动重试。

## 18. 上电 CBUF flush

CBUF SRAM 没有逐 bit 复位。WT 使用 `nvdla_core_ng_clk` 在复位释放后将 CBUF 高半区清零：

```text
bank8~15
4096 个 512-bit half entry
全部写 0
```

地址生成：

```verilog
flush_addr = {1'b1, wt_cbuf_flush_idx[11:1]};
flush_hsel = wt_cbuf_flush_idx[0];
```

与 CVT data flush 的 bank0~7 合起来覆盖整个 512KB CBUF：

```text
CVT flush -> bank0~7
WT flush  -> bank8~15
```

完成后：

```verilog
dp2reg_wt_flush_done = wt_cbuf_flush_idx[12];
```

软件通常等待 data/weight 两侧 flush 都完成后再启动卷积层，避免正常 CBUF 写与 flush 冲突。

## 19. 三段容量账本

WT 和 WMB 各自维护三段“32B atom 数”账本：

| 账本 | 含义 |
| --- | --- |
| `*_data_onfly` | DMA 请求已发出，但数据还没有拼成 512 bit 写入 CBUF |
| `*_data_stored` | 已写入 CBUF，但尚未达到一个完整 kernel group、未通告 CSC |
| `*_data_avl` | 已通过 `cdma2sc_wt_updt` 通告 CSC，但还没有被 CSC 释放 |

weight 请求限流看三者总和：

```verilog
wt_req_sum = wt_data_onfly + wt_data_stored + wt_data_avl;
wt_req_overflow = wt_req_sum > weight_bank_count * 1024 atoms;
```

一个 CBUF bank 是 32KB：

```text
32KB / 32B atom = 1024 atom/bank
```

账本迁移过程：

```text
DMA 请求 size atom
  -> onfly += size

拼成一个 512-bit CBUF write
  -> onfly -= 2 atom
  -> stored += 2 atom

一个 kernel group 取齐并 status_update
  -> stored -= entries * 4 atom
  -> available += entries * 4 atom

CSC 消费并 sc2cdma_wt_updt
  -> available -= released_entries * 4 atom
```

因为一个完整 CBUF entry 是 128B，所以对应 4 个 32B atom。

WMB 使用同样的三段账本，但容量固定为 bank15 的 1024 atom。只有 pending `clear_all` 才能把旧布局下的 available 账本直接清零。

这三段不能只保留一个总计数：模块既要限制“已经预取但尚未返回”的数据，也要知道“已写但还不能通知 CSC”的尾组数据，还要保护“CSC 正在使用、绝不能覆盖”的数据。

## 20. kernel group 完成条件

WT 不是按“所有 DMA 请求发完”向 CSC 通告，而是逐 kernel group 比较累计应取量和实际写入量。

### 20.1 非压缩组

普通组所需 weight bytes：

```verilog
normal_bpg = INT8 ? byte_per_kernel * 32
                  : byte_per_kernel * 16;
```

`bpg` 可以理解为 bytes per group。

### 20.2 压缩组

压缩 WT 的实际 bytes 不能由原始 kernel 尺寸推导，因为每组非零比例不同：

```verilog
wt_required_bytes += wgs_pop_data;
```

WMB 仍然要描述原始权重位置，因此它的 required bits 根据未压缩逻辑 weight 数计算：

```text
INT8       : 每个 weight 1 byte，WMB bit 数 = 原始 byte 数
INT16/FP16 : 每个 weight 2 byte，WMB bit 数 = 原始 byte 数 / 2
```

### 20.3 fetched 计数单位

每次 512-bit CBUF 写入，`wt_fetched_cnt` 加一：

```text
1 count = 512 bit = 64 byte
```

WT 满足条件：

```verilog
wt_fetched_cnt * 64 >= wt_required_bytes
```

WMB 每次写入也是 512 bit，因此：

```text
wmb_fetched_cnt * 512 >= wmb_required_bits
```

两者还要求 `fetched_cnt[0]==0`，即以两个 64B half entry、一个完整 128B CBUF entry 为通告边界。

最终：

```verilog
非压缩 status_update = wt_satisfied;
压缩   status_update = wt_satisfied & wmb_satisfied;
```

压缩模式必须等 WT 和 WMB 都可用，因为 CSC 只拿到其中一方无法正确解释压缩权重。

## 21. 向 CSC 通告的增量

每次 `status_update`，WT 用当前 fetched 计数减去上一次 group 的快照，得到本组新增 CBUF entries：

```verilog
incr_wt_entries  = (wt_fetched_cnt  - pre_wt_fetched_cnt)  >> 1;
incr_wmb_entries = (wmb_fetched_cnt - pre_wmb_fetched_cnt) >> 1;
```

右移一位是因为 fetched count 的单位是 64B half entry，而 CSC entries 的单位是 128B 完整 entry。

普通组 kernel 增量：

```text
INT8       -> 32 kernels
INT16/FP16 -> 16 kernels
```

最后一组使用 `reg2dp_weight_kernel` 的低位计算实际剩余 kernel 数。

增量经过三级寄存流水后输出：

```verilog
cdma2sc_wt_updt       = incr_wt_updt_d3;
cdma2sc_wt_kernels    = incr_wt_kernels_d3;
cdma2sc_wt_entries    = incr_wt_entries_d3;
cdma2sc_wmb_entries   = incr_wmb_entries_d3;
```

## 22. 完整时序示例

以压缩层为例：

```text
1. op_en 生效，WT 检查 bank 配置是否需要 pending
2. 进入 BUSY，WT/WMB/WGS 三套地址生成器准备请求
3. WGS 以最高优先级先取得若干 group-size
4. WGS response 拆成 32-bit 数据，进入 WGS FIFO
5. WT/WMB 经加权轮转共享剩余 DMA 带宽
6. 每笔已发请求把 {src,size} 压入 response FIFO
7. response 返回时按 FIFO 头 src 分给 WT/WMB/WGS
8. WT/WMB 将 256-bit atom 连续拼成 512-bit half entry
9. WT 写 data 区后的 weight banks，WMB 写固定 bank15
10. 当前组累计 WT bytes 和 WMB bits 都满足后产生 status_update
11. 向 CSC 通告本组 kernels、weight entries、WMB entries
12. CSC 开始读取并解压该组，同时 WT 可以继续预取后续组
13. CSC 消费完后归还 entries，WT 的 available 账本减少
14. 最后一组完成并排空更新流水，FSM 进入 DONE
15. data 侧也 DONE 后，status 统一切换到下一层
```

因此“搬运下一组”和“计算上一组”可以重叠，CBUF 充当生产者 CDMA 与消费者 CSC/CMAC 之间的环形工作集。

## 23. 性能计数器

当 `reg2dp_dma_en=1` 时，WT 维护两个性能指标：

```verilog
dp2reg_wt_rd_stall
dp2reg_wt_rd_latency
```

`wt_rd_stall` 在内部请求 valid 但外部 DMA ready 不接受时递增，反映请求侧因内存接口繁忙而等待的周期数。

`wt_rd_latency` 先维护 outstanding request 数：请求握手时加一，当前请求的全部 response 返回、FIFO 弹出时减一；随后每拍把 outstanding 数累加到总 latency。它近似统计所有请求在途周期数的总和，而不是单笔请求的最大延迟。

## 24. 重要断言和配置约束

主要断言包括：

1. `data_bank`、`weight_bank` 各自不能配置成 16 个。
2. 非压缩模式 data+weight 实际 bank 数不能超过 16。
3. 压缩模式 data+weight 实际 bank 数不能超过 15，必须给 WMB 留 bank15。
4. `wmb_bytes` 必须与 kernel 数、每 kernel 逻辑 weight 数和精度匹配。
5. FSM 结束时 WT/WMB 请求生成器必须已经完成。
6. WT/WMB/WGS response 的 atom 数不能超过请求 size。
7. response FIFO 不能空弹或 size 对账错误。
8. WT、WMB、flush 不能同拍争用 CBUF weight 写口。
9. WGS FIFO 不能溢出。
10. onfly/stored/available 账本不能溢出或在 IDLE 残留。
11. 向 CSC 发 update 时 kernel 增量不能为零。

这些断言说明 WT 依靠预先配置和内部记账保证安全；检测到错误后没有硬件恢复或重试机制。

## 25. 阅读 RTL 的推荐顺序

该文件超过 13000 行，包含大量生成的寄存器、断言和 pipe 展开。建议按下面顺序阅读：

1. 文件开头端口，分清 DMA、CBUF、CSC、配置四类接口。
2. `CDMA weight fetching logic FSM`：先掌握 IDLE/PEND/BUSY/DONE。
3. `registers to calculate local values`：看 N-1 配置如何还原。
4. `generate address for weight data`：看 WT 的 size、地址和 done。
5. `generate address for WMB data`：只比较它与 WT 的不同点。
6. `generate address for WGS data`：理解一个 32B 请求装 8 个 group-size。
7. `CDMA WT read request arbiter`：看 WRR 后接 WGS 固定优先级。
8. `CDMA WT read request interface`：看 MCIF/CVIF 选路和请求信息 FIFO。
9. `CDMA read response connection`：看 FIFO 头如何给 response 标记来源。
10. `weight/WMB read data`：看 256 bit 怎样拼成 512 bit。
11. `WT and WMB write to convolution buffer`：看半 entry 指针和 bank 布局。
12. `WT/WMB data status monitor`：理解 onfly/stored/available 三段账本。
13. `status update logic`：最后看 kernel group 满足和 CSC update。

文件末尾的 `pipe_p1~p4` 是 ready/valid skid-buffer 展开，先理解接口作用即可，不必一开始逐行跟组合逻辑。

## 26. 容易误解的点

1. WT 不是只有一条 weight 流。压缩模式实际上有 WT、WMB、WGS 三条内部流。
2. WMB 和 WGS 不是一回事：WMB 描述每个 weight 位置是否非零并写入 CBUF；WGS 只描述每个组压缩后有多少 byte，留在 WT 内部。
3. WT 不经过 data `shared_buffer` 和 `CVT`，但 FP16 weight 仍有 NaN/Inf 检测与可选 NaN 清零。
4. DMA atom 是 32B，response 子片是 256 bit；CBUF weight 写是 512 bit；CBUF entry 是 1024 bit。这是四个不同粒度。
5. `cdma2buf_wt_wr_hsel` 不是 write enable，而是 512-bit 数据写 entry 低半还是高半。
6. weight 区起点不是固定 bank，它等于实际 data bank 数；压缩 WMB 才固定在 bank15。
7. 请求全部发完不等于本组可通知 CSC，必须等 response 返回、拼接并实际写入 CBUF。
8. `status_update` 以完整 128B entry 为边界，因此 fetched half-entry 计数必须为偶数。
9. pending 处理 CBUF 布局清账，不是 DMA response pending。
10. CBUF 无 ready，WT 的容量安全依赖 onfly+stored+available 三段账本和 CSC release。
