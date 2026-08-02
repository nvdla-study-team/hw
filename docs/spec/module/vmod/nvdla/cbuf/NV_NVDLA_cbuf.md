# NV_NVDLA_cbuf

源码：`vmod/nvdla/cbuf/NV_NVDLA_cbuf.v`

## 1. 模块定位

`NV_NVDLA_cbuf` 是 NVDLA 卷积核心前面的片上卷积缓冲区（Convolution Buffer）。

它位于 CDMA 和 CSC 之间：

```text
外部 DRAM/SRAM
  -> CDMA 搬运并整理 activation / weight / WMB
  -> CBUF 暂存
  -> CSC 按卷积计算顺序读取并重排
  -> CMAC 做乘加
```

写入者是 CDMA：

```text
CDMA data/CVT -> cdma2buf_dat_wr_* -> CBUF
CDMA weight   -> cdma2buf_wt_wr_*  -> CBUF
```

读取者是 CSC（RTL 信号前缀 `sc2buf` 中的 `sc` 指 CSC）：

```text
CSC -> sc2buf_dat_rd_* -> activation data
CSC -> sc2buf_wt_rd_*  -> weight data
CSC -> sc2buf_wmb_rd_* -> weight mask bits
```

CBUF 自己不理解卷积窗口、channel、kernel 或 feature map 坐标，也不负责判断“当前有多少有效数据”。这些调度和记账由 CDMA、CSC 完成。CBUF 本质上是一个带固定端口和固定时序的 512KB banked SRAM 阵列。

## 2. 为什么 CNN 需要 CBUF

卷积的基本计算是：

```text
output[n, k, y, x]
  = sum(input[n, c, y+ry, x+rx] * weight[k, c, ry, rx])
```

同一个输入 activation 会被相邻卷积窗口以及多个 output kernel 重复使用；同一组 weight 也会在输出 feature map 的许多 `(x, y)` 位置重复使用。如果每次乘加都重新访问外部内存，带宽、延迟和功耗都无法支撑 CMAC 的并行吞吐。

因此数据先由 CDMA 成批搬到 CBUF，CSC 再按照 CMAC 需要的顺序反复读取：

```text
外存：容量大、访问慢、功耗高
  -> 一次 DMA 搬运
CBUF：容量较小、带宽高、靠近计算单元
  -> 多次复用
CMAC：持续取得 activation 和 weight 做乘加
```

CBUF 的作用是保存“当前卷积层正在使用的一部分 activation 和 weight”，把外存的 burst 访问与 CMAC 的规则、连续取数解耦。

## 3. 物理组织

模块实例化 32 个 RAM：

```text
16 bank * 2 column/bank
```

每个 RAM 是：

```verilog
nv_ram_rws_256x512
```

即深度 256、宽度 512 bit：

```text
单个 RAM = 256 * 512 bit = 16KB
一个 bank = 2 column * 16KB = 32KB
整个 CBUF = 16 bank * 32KB = 512KB
```

同一 bank、同一行地址的两个 column 合成一个逻辑 entry：

```text
column 0 = entry[511:0]
column 1 = entry[1023:512]

一个 entry = 1024 bit = 128 byte
```

所以总 entry 数为：

```text
16 bank * 256 entry/bank = 4096 entry
4096 * 128B = 512KB
```

从 CNN 数据类型看，一个完整 entry 可容纳：

```text
INT8       : 128 个数
INT16/FP16 : 64 个数
```

这只是容量换算。entry 中每个数具体对应哪个 channel、pixel 或 kernel，由 CDMA 的写地址组织和 CSC 的读地址组织决定，不由本模块解析。

## 4. 地址结构和 bank 分区

data/weight 的地址都是 12 bit：

```text
addr[11:8] = bank 编号，范围 0~15
addr[7:0]  = bank 内 entry 编号，范围 0~255
```

CBUF 的 bank 在每层运行时被逻辑划分为 data 区和 weight 区。实际分配数量由上层寄存器配置，并由 CDMA/CSC 的地址生成器执行；CBUF 中没有保存 `data_bank` 或 `weight_bank` 配置的控制器。

本模块在端口解码中硬编码了两个边界：

```text
data 端口只访问 bank 0~14
weight 端口只访问 bank 1~15
WMB 读口固定访问 bank 15
```

因此 bank 0 至少留给 data，bank 15 可供 weight/WMB 使用。中间 bank 1~14 究竟属于 data 还是 weight，由当前层的 bank 分配以及上游地址决定；CBUF 只用冲突断言检查上游没有把两种流量送到同一 bank。

WMB 是 weight compression 使用的 Weight Mask Bits。压缩权重只保存非零 weight，WMB 告诉解压/调度逻辑哪些原始位置有权重、哪些位置应视为零。这样稀疏卷积可以减少权重外存流量，但 CSC 必须同时读取 weight 和 WMB 才能恢复正确位置关系。

## 5. 接口总览

| 方向 | 接口 | 地址 | 数据宽度 | 作用 |
| --- | --- | ---: | ---: | --- |
| CDMA -> CBUF | `cdma2buf_dat_wr_*` | 12 bit | 1024 bit | 写 activation/data |
| CDMA -> CBUF | `cdma2buf_wt_wr_*` | 12 bit | 512 bit | 写 weight 或 WMB |
| CSC -> CBUF | `sc2buf_dat_rd_*` | 12 bit | 1024 bit | 读 activation/data |
| CSC -> CBUF | `sc2buf_wt_rd_*` | 12 bit | 1024 bit | 读 weight |
| CSC -> CBUF | `sc2buf_wmb_rd_*` | 8 bit | 1024 bit | 从固定 bank 15 读 WMB |

所有请求口都没有 `ready`。这意味着 CBUF 不会对 CDMA/CSC 反压，也不会在冲突时排队；上游必须在发出请求以前保证 bank、地址和时序合法。

## 6. data 写路径 p0

data 写入来自 CDMA CVT 的最终输出：

```verilog
cdma2buf_dat_wr_en
cdma2buf_dat_wr_addr[11:0]
cdma2buf_dat_wr_hsel[1:0]
cdma2buf_dat_wr_data[1023:0]
```

1024-bit 数据被拆成两个 512-bit column：

```verilog
cbuf_p0_wr_lo_data = cdma2buf_dat_wr_data[511:0];
cbuf_p0_wr_hi_data = cdma2buf_dat_wr_data[1023:512];

cbuf_p0_wr_lo_en = cdma2buf_dat_wr_en & cdma2buf_dat_wr_hsel[0];
cbuf_p0_wr_hi_en = cdma2buf_dat_wr_en & cdma2buf_dat_wr_hsel[1];
```

`hsel` 是 half select/half enable：

```text
hsel = 2'b01 -> 只写低 512 bit，也就是 column 0
hsel = 2'b10 -> 只写高 512 bit，也就是 column 1
hsel = 2'b11 -> 两个 column 同拍都写，形成完整 1024-bit entry
hsel = 2'b00 -> 非法，RTL 有断言
```

为什么需要半 entry 写使能：DC/WG 到 CVT 的自然数据块有时只有 512 bit，尚未形成完整 1024-bit entry；IMG 或已经拼齐的数据则可以一次写满。两个 column 独立写使能可以避免为了更新一半数据而先读出另一半再回写。

地址的 `addr[11:8]` 被 one-hot 解码到 bank 0~14，`addr[7:0]` 送到该 bank 两个 RAM 的写地址。

## 7. weight/WMB 写路径 p1

weight 写入接口为：

```verilog
cdma2buf_wt_wr_en
cdma2buf_wt_wr_addr[11:0]
cdma2buf_wt_wr_hsel
cdma2buf_wt_wr_data[511:0]
```

它每拍只有 512 bit，所以 `hsel` 不再是两位 enable，而是一位 column 选择：

```verilog
cbuf_p1_wr_lo_en = cdma2buf_wt_wr_en & ~cdma2buf_wt_wr_hsel;
cbuf_p1_wr_hi_en = cdma2buf_wt_wr_en &  cdma2buf_wt_wr_hsel;
```

对应关系是：

```text
hsel = 0 -> 写 column 0，即 entry[511:0]
hsel = 1 -> 写 column 1，即 entry[1023:512]
```

因此一个完整的 1024-bit weight entry 通常由两个 512-bit 写请求拼成。weight 数据与压缩权重的 WMB 都使用这条物理写口；写到哪个 bank、地址如何推进由 CDMA weight engine 决定。

weight 写端口只对 bank 1~15 进行解码，bank 0 写入属于非法操作并有断言检查。

## 8. 两条写口怎样进入同一组 RAM

data p0 和 weight p1 并不是各自拥有一份存储。两条写口先分别完成 bank/column 解码，再把对应的写使能、地址、数据汇合到 32 个 RAM 的私有写口。

概念上，以 `bank 3, column 0` 为例：

```text
p0 选择 bank3/c0 --+
                    +-> cbuf_we/wa/wdat_b3c0 -> RAM bank3 column0
p1 选择 bank3/c0 --+
```

这里没有仲裁。合法运行时 data bank 和 weight bank 已被分开，所以两条写口不会同拍选择同一 bank。RTL 使用 OR/mask 合并信号，并用断言检查 `data write bank != weight write bank`。

写路径经过输入寄存、bank 选择寄存、RAM 前 retiming 寄存后写入 SRAM。源码把该路径标为 4-cycle write latency（包含 RAM 自身访问）；写接口没有完成响应，所以上游依靠预先约定的固定流水而不是等待 ack。

## 9. 三条读路径

CSC 有三条独立的逻辑读请求：

```text
p0 = data read
p1 = weight read
p2 = WMB read
```

data 和 weight 使用完整 12-bit 地址：

```verilog
cbuf_p0_rd_bank = sc2buf_dat_rd_addr[11:8];
cbuf_p1_rd_bank = sc2buf_wt_rd_addr[11:8];
```

选中一个 bank 后，该 bank 的两个 column 会同时读取：

```text
bank X column0[addr[7:0]] -> 512 bit
bank X column1[addr[7:0]] -> 512 bit
                           -> 拼成 1024-bit read data
```

WMB 地址只有 8 bit：

```verilog
cbuf_p2_rd_addr = sc2buf_wmb_rd_addr[7:0];
```

p2 没有 bank 字段，因为它固定选择 bank 15 的 column 0 和 column 1。这样 CSC 只需给出 WMB 在 bank15 内的 entry 编号。

三条读口也共享 32 个物理 RAM 的读口。不同 bank 可以并行读取；如果两个逻辑读口同拍访问同一 bank，单个 RAM 只有一个物理读地址，CBUF 无法同时满足，所以这种请求被定义为非法。

## 10. 固定 6 拍读流水

读请求是 fire-and-forget 协议：发出 `rd_en` 后没有 `ready`，数据固定在 6 拍后与 `rd_valid` 一起返回。

主要流水为：

```text
cycle 0: CSC 给出 rd_en + rd_addr，完成 bank one-hot 解码
         |
         v
stage d1/d2/d3: 请求、地址和 bank select 做跨 RAM 阵列 retiming
         |
         v
RAM read: 选中 bank 的 column0/column1 返回数据
         |
         v
stage d4: 按延迟后的 bank select 选择 RAM 输出并拼成 1024 bit
         |
         v
stage d5/d6: 输出 retiming
         |
         v
cycle 6: sc2buf_*_rd_valid = 1，sc2buf_*_rd_data 有效
```

RTL 用三条 `nv_assert_at_time_interval #(0,6,...)` 分别检查 data、weight、WMB 的 `rd_en -> rd_valid` 恰好为 6 拍。

输出数据寄存器只在对应 valid 流水到达时更新；空闲拍保持旧值。因此下游不能只观察 `rd_data` 是否变化，必须只在 `rd_valid=1` 时采样。

固定延迟的意义是让 CSC 能提前六拍发出 CBUF 请求，并把返回的 activation、weight、WMB 与后续解压、重排和 CMAC 控制流水精确对齐。CBUF 不提供乱序返回，也不带 request ID。

## 11. 并行能力和冲突规则

每个 `nv_ram_rws_256x512` 有一条读口和一条写口，所以不同 bank 天然并行，同一 bank 也可在物理上进行一次读和一次写；但同一 entry 的读写结果可能不确定，RTL 明确禁止。

主要接口约束如下：

1. data 写时 `hsel` 不能是 `2'b00`。
2. data 写/读不能访问 bank 15。
3. weight 写/读不能访问 bank 0。
4. data 写和 weight 写不能同拍访问相同 bank。
5. data 读和 weight 读不能同拍访问相同 bank。
6. weight 读 bank15 时不能同时发起 WMB 读。
7. 同类 data、weight、WMB 不能同拍读写同一 entry。
8. data 写与 weight 读、weight 写与 data 读不能访问相同 bank。

这些规则没有对应的恢复逻辑：断言失败表示 CDMA/CSC 的 bank 分配或调度已经出错，不表示 CBUF 会自动 stall 后重试。

## 12. 从一组数据看完整数据流

以一块 activation 为例：

```text
1. CDMA 从外存取得 activation
2. DC/WG/IMG 按各自模式重排，CVT 做必要的格式处理
3. CVT 给出 cdma2buf_dat_wr_en/addr/hsel/data
4. CBUF 用 addr[11:8] 选择 data bank
5. 用 hsel 选择写 column0、column1 或两者
6. 数据留在 CBUF，等待 CNN 计算复用
7. CSC 根据当前卷积窗口和 channel 调度发出 sc2buf_dat_rd_en/addr
8. CBUF 同时读取两个 column，六拍后返回 1024-bit data
9. CSC 将数据重排并广播到 CMAC，与对应 weight 做乘加
```

weight 路径类似，但 CDMA 每拍写 512 bit，两个写拍可以拼成一个 entry；CSC 读取时仍一次得到 1024 bit。启用 weight compression 时，CSC 还会并行安排 WMB 读取，用 mask 解释压缩 weight 的有效位置。

这里“写入”和“读取”可以针对不同 bank/entry 流水重叠，所以系统不需要等整层数据全部搬完才开始卷积。CDMA 负责生产，CSC 负责消费，双方通过各自的 entry/slice 更新与信用记账避免覆盖尚未消费的数据；这些容量管理信号不进入 CBUF 本体。

## 13. 阅读 RTL 的方法

这个文件有 7000 多行，绝大部分是 16 bank × 2 column 的展开代码。建议按下面顺序阅读：

1. 端口定义：确认两条写口和三条读口。
2. `Input write stage1`：看 `hsel` 如何拆成两个 column enable。
3. 只看 `bank0/column0` 和 `bank1/column0` 的写解码，其他 bank 同构。
4. `Instance RAMs`：确认 32 个 `nv_ram_rws_256x512` 的物理组织。
5. `Input read stage1`：看 p0/p1 bank 解码以及 p2 固定 bank15。
6. `Input read stage4`：看两个 512-bit column 如何选出并拼接。
7. `Connect to output signals`：确认 6-cycle valid/data 输出契约。
8. 文件末尾断言：反推上游必须满足的 bank 分区和冲突规则。

不要逐行阅读 16 份重复的 bank 解码。先看懂一个 data bank、一个 weight bank 和固定 bank15 的 WMB 路径，就已经理解了模块主体。

## 14. 容易误解的点

1. CBUF 不是 CDMA 内部 8KB `shared_buffer`。shared buffer 用于 DMA response 临时落地和重排；CBUF 是 512KB 的卷积工作集存储，直接供 CSC 读取。
2. CBUF 不做卷积，也不做数据格式转换。CVT 在写 CBUF 之前处理格式，CSC/CMAC 在读 CBUF 之后组织并计算。
3. `hsel` 在两个写口含义不同：data 口是 2-bit 半 entry enable，weight 口是 1-bit column select。
4. 三条读接口不代表每个 bank 有三条物理读口；它们共享每个 RAM 唯一的读口，不能撞 bank。
5. CBUF 没有 `ready`、FIFO 或仲裁器，冲突必须由上游提前避免。
6. data/weight 的有效 entry 数、读写指针和 bank 配额不保存在这里，而在 CDMA/CSC 的状态与地址生成逻辑中维护。
7. `pwrbus_ram_pd` 传给所有 RAM，用于 SRAM 电源控制，不参与正常数据寻址。
8. WMB 读写同 entry 的断言文本与表达式附近存在生成代码痕迹；理解功能时应以“p2 固定读取 bank15、地址来自 `sc2buf_wmb_rd_addr`”的数据通路为准。
