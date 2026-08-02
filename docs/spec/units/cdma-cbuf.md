# CDMA + CBUF（卷积取数 DMA 与卷积缓冲）

CDMA（Convolution DMA）是卷积流水线的取数引擎：从外部内存把 feature/pixel 数据与
weight 拉回片上，做可选的格式转换后写入 CBUF（Convolution Buffer）。CBUF 是 512KB
的分 bank SRAM 阵列，由 CSC（Convolution Sequence Controller）按卷积节拍读出送往
CMAC。本文合写这两个单元。

> 事实来源：vmod/ 源码实读（2026-08，nv_full 配置，`developer` 分支）。
> 注意：编写期间 vmod/ 正在同步加注释（纯注释改动），本文行号已按写稿时刻的文件
> 终态逐条核对；后续修订须重新核对（README 通则）。

## 1. 定位与数据流

### 1.1 在卷积流水线中的位置

```
DRAM/CVSRAM ──(mcif/cvif 读)──► CDMA ──(cdma2buf 写)──► CBUF ──(sc2buf 读)──► CSC ──► CMAC ──► CACC
                                  ▲                                            │
                                  └────────── cdma2sc/sc2cdma 状态-信用 ◄──────┘
```

两个单元同属物理分区 c（vmod/nvdla/top/NV_NVDLA_partition_c.v:1600 例化 cdma、:1669
例化 cbuf）。CDMA 是 CSB 地址空间 0x5000 块的寄存器终点；CBUF 纯被动，不出现在
CSB 扇出里。sc2buf 读口的消费方是 CSC 的 dl（data loader，读 dat）与 wl（weight
loader，读 wt/wmb）子模块（vmod/nvdla/csc/NV_NVDLA_CSC_dl.v、NV_NVDLA_CSC_wl.v）。

### 1.2 四条子通路与模式选择

CDMA 内部有 4 个 DMA 客户端，按层配置激活。数据侧三选一（dc/img/wg 互斥），
weight 侧每层恒开：

| 子通路 | 内容 | 激活条件（均为明文代码） | 依据 |
|---|---|---|---|
| DC | 直卷积 feature 数据 | `op_en & conv_mode==0 & datain_format==0` | vmod/nvdla/cdma/NV_NVDLA_CDMA_dc.v:2472、:2478、:2487（`is_hog` 恒 0，HoG 格式已废弃 :2467） |
| IMG | 图像 pixel 输入 | `op_en & conv_mode==0 & datain_format==1` | vmod/nvdla/cdma/NV_NVDLA_CDMA_IMG_ctrl.v:2329、:2335、:2343 |
| WG | Winograd feature 数据 | `op_en & conv_mode==1 & datain_format==0` | vmod/nvdla/cdma/NV_NVDLA_CDMA_wg.v:2429、:2437 |
| WT | weight（含压缩模式的 wmb/wgs） | `op_en`（每层都跑） | vmod/nvdla/cdma/NV_NVDLA_CDMA_wt.v:2433 |

conv_mode / datain_format 是 D_MISC_CFG / D_DATAIN_FORMAT 寄存器字段（3.4 节）。
dc/wg/img 互斥由 SLCG 门控信号互斥断言兜底（NV_NVDLA_cdma.v:1180，
"DC, WG and IMG slcg gate signal conflict!"）。

### 1.3 为什么 cdma 与 cbuf 合写一篇

- CBUF **没有 CSB 口、没有任何自有寄存器**：端口只有写口×2、读口×3 加 pwrbus
  （vmod/nvdla/cbuf/NV_NVDLA_cbuf.v:12-36 完整端口表）；bank 划分完全由 CDMA 的
  D_BANK 寄存器（data_bank/weight_bank）决定，CBUF 自身不感知配置。
- CBUF 是纯被动 RAM 阵列：写口无 ready、写必须成功；读口固定 6 拍返回、无反压
  （2.4 节）。**写协议语义由 cdma 定义，读协议语义由 csc 消费**，单独成篇没有可
  独立描述的行为面。
- 空间/合法性约束（哪个 bank 属 data、哪个属 weight、bank15 归 wmb）是 CDMA 配置
  与 CBUF 断言共同表达的一个整体（4.4 节断言清单）。

### 1.4 CDMA-CBUF 端到端数据流

这一节先不按 RTL 文件拆开，而是跟随一层卷积的数据，从外存一直走到 CSC。后续
第 2～4 节再分别展开接口、寄存器和内部机制。

#### 1.4.1 软件先准备什么

一层启动前，软件/编译器需要确定并配置：

- 输入 feature/image 的外存布局、基址、尺寸、stride 和输入精度；
- weight 的 kernel 排列、基址、每 kernel 字节数和 kernel 总数；
- 是否使用 Winograd、image input 或普通 direct convolution 数据路径；
- CBUF 中 data bank 与 weight bank 的数量；
- 输入精度到处理精度之间的 `offset/scale/truncate`；
- 压缩权重模式下的 WT、WMB、WGS 三个外存区域。

压缩权重不是 `NV_NVDLA_CDMA_wt` 运行时产生的。软件已经把原始稠密权重：

```text
[3, 0, 0, -2, 0, 5, 0, 0]
```

预先编排为：

```text
WT  = [3, -2, 5]                非零权重数值
WMB = [1, 0, 0, 1, 0, 1, 0, 0] 原始位置是否非零
WGS = 当前kernel group压缩后的WT字节数
```

这里的“软件准备输入布局”不表示输入一定由 CPU 搬运；输入也可能是上一硬件层写回的
结果。关键是生产者和 CDMA 必须遵循同一 tensor/weight 内存格式。

复位释放后，CDMA 先用 dat/wt 两个写口并行清零整个 CBUF，软件应等待
`S_CBUF_FLUSH_STATUS.flush_done=1`，再配置 D 组寄存器并置 `D_OP_ENABLE.op_en`。

#### 1.4.2 一层启动后的两条并行主线

一层开始后，CDMA 同时运行两条相对独立的预取主线：

```text
Data主线：   DC / IMG / WG 三选一 -> shared_buffer -> CVT -> CBUF data区
Weight主线： WT（压缩时含WMB/WGS）             -> CBUF weight区/WMB区
```

两条主线拥有独立的外部 DMA 读接口：`cdma_dat2*` 和 `cdma_wt2*`，因此 Data 与
Weight 可以同时向 MCIF/CVIF 发请求、同时接收响应、写不同 CBUF bank。它们不是
“先把 Data 全搬完，再搬 Weight”。

Data 主线内部则是三选一：

```text
普通feature map + direct convolution -> DC
原始pixel/image输入                -> IMG
Winograd模式的feature/tile组织      -> WG
```

同一层不会同时运行 DC、IMG、WG。`dma_mux` 依赖这个互斥条件，把三套内部端口 OR/mux
成一个对外 Data DMA 端口；它不是在三路之间做动态公平仲裁。

整体关系如下：

```text
                           +-> DC  --+
DRAM/CVSRAM -> Data DMA ---+-> IMG --+-> shared_buffer -> CVT -> CBUF Data banks --+
                           +-> WG  --+                                           |
                                                                                 +-> CSC -> CMAC
DRAM/CVSRAM -> Weight DMA -> WT/WMB pack ----------> CBUF WT banks / bank15 -----+
                           `-> WGS FIFO -> group完成判断
```

#### 1.4.3 Data 主线：外存到 shared_buffer

DC/IMG/WG 根据 tensor 尺寸、stride、surface/tile 和当前 CBUF 空闲量生成 DMA 请求。
外部请求的基本颗粒是 32B atom：

```text
request pd = {size[14:0], addr[63:0]}
addr       = 32B对齐地址
size       = atom数 - 1
```

MCIF/CVIF 返回：

```text
response pd = {mask[1:0], data[511:0]}

mask[0] -> 低256bit atom有效
mask[1] -> 高256bit atom有效
```

有效的 256-bit atom 先写入 8KB `NV_NVDLA_CDMA_shared_buffer`。它是 DMA response
与下游格式整理之间的临时行缓冲，用来吸收返回抖动，并让 DC/IMG/WG 按 CBUF entry、
channel surface 或 tile 需要的次序重新读取。它不是最终 CBUF，也不被 CSC 访问。

三种 Data 客户端从 shared buffer 读出后的职责不同：

| 路径 | shared buffer 之后主要做什么 | 送入 CVT 的宽度 |
|---|---|---:|
| DC | 按普通 feature surface/entry 计数读取，两个 256-bit 端口拼成半 entry | 512 bit |
| WG | 按 Winograd 扩展尺寸和 tile/line 规则读取、组织半 entry | 512 bit |
| IMG | 解包 packed/planar pixel，处理 YUV/RGB 分量位置，生成 data/mean/pad mask | 1024 bit |

DC 中最直接的数据拼接是：

```verilog
cbuf_wr_data_d3 <= {dc2sbuf_p1_rd_data, dc2sbuf_p0_rd_data};
```

也就是两个 256-bit atom 形成一个 512-bit 半 entry。IMG 的 `IMG_pack` 比 DC 多一层
像素格式重排，但三路最终都进入同一个 `NV_NVDLA_CDMA_cvt`，不会直接写 CBUF。

#### 1.4.4 CVT：逐元素数值预处理和 CBUF 打包

CVT 先选择当前有效的 DC/WG/IMG 输入，然后对 activation 做可选的逐元素预处理。
整数输入且 `cvt_en=1` 时，64 个并行 HLS cell 执行：

```text
y = SAT_proc_precision(((x - offset_or_mean) * scale) >> truncate)
```

- `offset_or_mean`：普通 feature 使用 `D_CVT_OFFSET`；IMG mean 拍使用对应 pixel mean，
  二者是二选一；
- `scale`：把输入整数映射到本层 CMAC 使用的量化尺度；
- `truncate`：算术右移，去除定点乘数的小数位并限制幅度；
- `SAT`：按 INT8/INT16 目标范围饱和，避免高位截断回绕。

精度变化对应的数据宽度变化为：

```text
INT8  -> INT16/FP16：expand，一个元素由8bit变16bit
INT16 -> INT8：      shrink，一个元素由16bit变8bit
同位宽：             normal
```

FP16 输入只能输出 FP16，cell 内原样传递 FP16 bit pattern；顶层另外做 NaN/Inf 统计和
可选 NaN-to-zero。FP16 输入不会先转成整数再执行上述定点公式。`cvt_en=0` 时走 bypass，
且输入精度必须等于处理精度。

CVT 末级把有效结果和 padding 值组合成 CBUF 写口格式：

```text
cdma2buf_dat_wr_data[1023:0]  一个128B entry的数据总线
cdma2buf_dat_wr_hsel[1:0]     low/high 512bit分别是否写入
cdma2buf_dat_wr_addr[11:0]    {bank, bank内entry}
```

CVT 的“重排”只包含精度宽度变化、半 entry 攒包和 CBUF entry 打包。它不会根据
`R/S` 展开所有滑窗，也不会决定某个 activation 与哪个 kernel 相乘；这一步在 CSC。

#### 1.4.5 Weight 主线：非压缩和压缩模式

Weight 主线不经过 Data `dma_mux`、shared buffer 或 CVT。它有自己的 DMA 端口、请求
信息 FIFO、response 拼接寄存器和 CBUF 写指针。

非压缩模式只有 WT：

```text
外存稠密WT
 -> Weight DMA按32B atom读取
 -> 连续两个atom拼成512bit半entry
 -> FP16时检测NaN/Inf并可选NaN-to-zero
 -> 写CBUF weight banks
```

压缩模式同时管理三条内部流：

| 流 | 内容 | response 后的变化 | 最终去向 |
|---|---|---|---|
| WT | 已删除零的非零 weight 数值 | 256-bit atom 连续拼成 512-bit | CBUF weight banks |
| WMB | 每个原始 weight 位置的非零 bitmap | 256-bit atom 连续拼成 512-bit | CBUF bank15 |
| WGS | 每个 kernel group 压缩后的 WT byte 数 | 一个 256-bit atom 拆成 8 个 32-bit size | WT 内部 WGS FIFO |

三套请求生成器可以同时提出请求，但对外只有一条 Weight DMA request，因此内部先让
WT/WMB 做加权轮转，再让 WGS 以固定高优先级参与第二级选择。WGS 优先是因为 CDMA
必须先知道当前 group 需要多少压缩 WT byte，才能判断这一组何时取齐。

每发出一笔 WT/WMB/WGS 请求，模块把 `{src,size}` 压入 response-info FIFO；回包按
FIFO 头的 `src` 分流。压缩模式下当前 kernel group 必须同时满足：

```text
已写CBUF的WT byte >= WGS给出的累计WT门槛
并且
已写CBUF的WMB bit >= 当前group对应的原始权重位置数
```

只有 `wt_satisfied & wmb_satisfied` 才向 CSC 通告这一组可用。WGS 不进入 CBUF，
也不参与 CMAC 计算；它只是 CDMA_wt 的变长流边界信息。

#### 1.4.6 CBUF 中最终存放什么

本配置的 CBUF 是 16 bank × 32KB = 512KB。每 bank 有 256 个 128B entry；一个 entry
由低、高两个 512-bit column 组成：

```text
addr[11:8] = bank
addr[7:0]  = bank内entry
entry      = {column1[511:0], column0[511:0]} = 1024bit
```

bank 分区不是 CBUF 自己配置的，而是 CDMA/软件共同遵守的空间合同：

```text
低编号bank                              高编号bank
+----------------------+----------------------+-------------+
| Data banks           | Weight banks         | WMB bank     |
| bank0...              | 紧跟Data区之后       | bank15      |
+----------------------+----------------------+-------------+
```

例如压缩模式配置 8 个 data bank、7 个 weight bank：

```text
bank0  ~ bank7  : activation/Data
bank8  ~ bank14 : 非零WT数值
bank15          : WMB bitmap
```

非压缩模式没有 WMB，bank15 可以作为普通 weight bank。WGS 在 CDMA_wt 内部 FIFO，
任何模式下都不占 CBUF bank。

Data 与 Weight 写口可以同拍工作，只要不访问同一 bank。CBUF 写口没有 ready，不能
临时拒绝 CDMA，所以 CDMA 必须在发请求前根据账本保证有空间。

#### 1.4.7 CSC 怎样从 CBUF 取走数据

CDMA 写完一批可消费数据后，不直接把数据推给 CMAC，而是通过 update 接口通知 CSC：

```text
Data update  : 新增多少 entries、slices
Weight update: 新增多少 kernels、WT entries、WMB entries
```

CSC 的 data loader 和 weight loader 再主动向 CBUF 发读请求：

```text
sc2buf_dat_rd_* -> activation entry
sc2buf_wt_rd_*  -> weight value entry
sc2buf_wmb_rd_* -> compressed weight bitmap entry
```

CBUF 三个读口都在请求后固定 6 拍返回 1024 bit，无 ready/反压。CSC 根据卷积的
`H/W/C/R/S`、stride、padding 和 kernel group 进度：

- 选择当前输出位置所需的 activation 窗口；
- 沿 C/R/S 维组织 Data 与 Weight；
- 压缩模式下结合 WMB 消费非零 WT；
- 将配对后的 Data/Weight 按 CMAC lane 时序送入乘法阵列；
- 在相邻窗口间复用 CBUF 中的 activation，在不同输出通道间复用同一 Data。

因此 CBUF 保存的是可重复读取的 feature/weight 数据块，不是 CDMA 提前复制好的全部
滑窗。真正“按 CMAC 计算顺序重组”的模块是 CSC。

#### 1.4.8 空间记账、归还与层完成

CBUF 本身只是被动 SRAM，不知道某个 entry 是否仍被使用。CDMA 与 CSC 用增量账本
避免覆盖尚未消费的数据：

```text
CDMA写入落地 -> cdma2sc_*_updt：增加可用entries/slices/kernels
CSC消费完成  -> sc2cdma_*_updt：归还entries/slices/kernels
```

Data 侧 `NV_NVDLA_CDMA_status` 根据：

```text
free_entries = data_bank_count * 256 - valid_entries
```

限制 DC/IMG/WG 继续预取。Weight 侧在 `NV_NVDLA_CDMA_wt` 内分别维护 WT/WMB 的
requested、stored、available 账本。update 经过足够流水延迟后才送 CSC，保证 CSC
看见“可用”时数据已经真正写进 CBUF RAM。

跨层是否清账取决于 reuse/bank 布局。需要清空旧账时，CSC 发 pending request，CDMA
进入 pending 并 ack，重置旧布局下的指针和 available 计数；允许 reuse 时则保留仍可
复用的数据。

一层结束也不是某一条 DMA 收到最后一个 response 就立刻完成。Data 和 Weight 各自在
自己的末尾写入/update 流水排空后产生对应 done 和单拍中断；整个 CDMA 层的寄存器组
切换则必须等待两侧都完成：

```text
Data侧：当前DC/IMG/WG完成并排空写入/update流水
Weight侧：所有kernel group满足并排空写入/update流水
Data done -> dat done中断
Weight done -> wt done中断
Data done && Weight done
    -> status切层
    -> 清当前consumer组op_en
    -> consumer翻转到下一乒乓寄存器组
```

#### 1.4.9 一张表记住所有格式变化

| 位置 | Data 主线 | Weight 主线 |
|---|---|---|
| 外存 | feature/image/tile 布局 | dense WT，或软件生成的 WT/WMB/WGS |
| DMA 请求粒度 | 32B atom | 32B atom |
| DMA response | 512-bit data + 2-bit atom mask | 512-bit data + 2-bit atom mask |
| 临时缓存 | shared_buffer：256-bit/entry | WT/WMB 本地 256-bit 拼接寄存器；WGS FIFO |
| 路径整理 | DC/WG 输出512bit；IMG pack输出1024bit | WT/WMB 拼成512bit；WGS拆成32bit |
| 数值处理 | CVT：整数减/乘/移位/饱和，或 bypass/FP16处理 | 不经CVT；FP16仅做异常检测/可选NaN清零 |
| 写 CBUF | 1024-bit data + 2-bit half enable | 512-bit WT/WMB + 1-bit column select |
| CBUF位置 | 动态配置的低编号 data banks | WT紧跟data区；压缩WMB固定bank15；WGS不进入 |
| 谁按卷积顺序读取 | CSC data loader | CSC weight loader |

用一句话概括整条链路：

> 软件定义外存和 CBUF 格式；CDMA 负责按容量预取、做必要的数据格式/数值预处理并
> 写入 CBUF；CBUF 负责片上保存和固定延迟读出；CSC 才负责按卷积窗口、通道、kernel
> 和 CMAC lane 的顺序组织计算数据。

## 2. 接口信号表

方向以 CDMA/CBUF 为参照。CDMA 端口声明见 vmod/nvdla/cdma/NV_NVDLA_cdma.v:113-199，
CBUF 见 vmod/nvdla/cbuf/NV_NVDLA_cbuf.v:41-72。

### 2.1 CSB 配置口

| 信号 | 方向 | 位宽 | 说明 | 代码 |
|---|---|---|---|---|
| csb2cdma_req_pvld / prdy | in / out | 1 | 请求握手；**prdy 恒 1，从不背压** | NV_NVDLA_cdma.v:153-154；prdy=1 见 NV_NVDLA_CDMA_regfile.v:1127 |
| csb2cdma_req_pd | in | 63 | 请求包，字段切分见 [csb-link.md 6.1 节](../common/csb-link.md)，此处不复述 | NV_NVDLA_cdma.v:155；regfile 解包 :1119-1125 |
| cdma2csb_resp_valid / pd | out | 1 / 34 | 响应包（[33]=type，[32]=error 恒 0，[31:0]=rdat），读与 nposted 写下一拍必回，posted 写无响应 | NV_NVDLA_cdma.v:126-127；regfile :1171-1173（valid 条件）、:1138-1152（打包，error 拴 0） |

字地址还原字节偏移：`reg_offset = {req_addr, 2'b0}`（regfile:1131），单元内只看低 12 位。

### 2.2 DMA 读 4 路（dat/wt × mcif/cvif）

**CDMA 是纯读客户端**：4 路都只有 rd_req/rd_rsp 两个通道——没有写通道
（wr_req/wr_rsp_complete），也没有 rd_cdt_lat_fifo_pop 信用口（cdma.v:113-199 端口
表中无任何 `cdma*wr*` 或 `*pop*` 信号）。4 路同构，req 79 位 / rsp 514 位的包形状
同 [dma-if.md](../common/dma-if.md)；**但均不参与 latency-FIFO credit 机制**
（勘误详见 dma-if.md 4 节引用块；mcif 侧 tieoff 证据
vmod/nvdla/nocif/NV_NVDLA_MCIF_READ_ig.v:321-329、:334-342，cvif 侧
NV_NVDLA_CVIF_READ_ig.v:321-329、:334-342）。

| 通道 | 信号（以 dat×mcif 为样板） | 位宽 | 代码（NV_NVDLA_cdma.v） |
|---|---|---|---|
| dat→mcif 请求 | cdma_dat2mcif_rd_req_valid/ready/pd | 1/1/79 | :139-141 |
| dat→cvif 请求 | cdma_dat2cvif_rd_req_valid/ready/pd | 1/1/79 | :133-135 |
| wt→mcif 请求 | cdma_wt2mcif_rd_req_valid/ready/pd | 1/1/79 | :149-151 |
| wt→cvif 请求 | cdma_wt2cvif_rd_req_valid/ready/pd | 1/1/79 | :143-145 |
| mcif→dat 响应 | mcif2cdma_dat_rd_rsp_valid/ready/pd | 1/1/514 | :173-175 |
| cvif→dat 响应 | cvif2cdma_dat_rd_rsp_valid/ready/pd | 1/1/514 | :157-159 |
| mcif→wt 响应 | mcif2cdma_wt_rd_rsp_valid/ready/pd | 1/1/514 | :177-179 |
| cvif→wt 响应 | cvif2cdma_wt_rd_rsp_valid/ready/pd | 1/1/514 | :161-163 |

请求包 `pd[78:0] = {size[14:0], addr[63:0]}`（打包样板
NV_NVDLA_CDMA_dc.v:7911-7912）：

- **addr 恒 32B 对齐**：`dma_rd_req_addr = {req_addr_d1[58:0], 5'b0}`（dc.v:7915），
  地址以 32B 原子（atom）为单位生成；
- **size 是 0-based 的 32B 块数**：`req_atm_size_out = req_atm_size - 1`
  （dc.v:6343），dc 每笔 1~8 个原子（≤256B）；
- mc/cv 选路按 `reg2dp_datain_ram_type` / `reg2dp_weight_ram_type` 静态决定
  （dc.v:7917 `dma_rd_req_type = reg2dp_datain_ram_type`）。

响应包 `pd[513:0] = {mask[1:0], data[511:0]}`。

> **勘误（响应 mask 只有两种取值，推翻 dma-if.md 旧文"2'b01/2'b10"）**：
> **mask ∈ {2'b11, 2'b01}，2'b10 永不出现；首块永远落首拍低 256b，与 addr[5]
> 是否 64B 对齐无关。** 生成侧：mcif/cvif 出口按"是否奇数尾块"二选一——
> `dma0_mask = dma0_is_last_odd ? 2'b01 : 2'b11`
> （vmod/nvdla/nocif/NV_NVDLA_MCIF_READ_eg.v:1095）；AXI 侧的首尾去半与
> swizzle 重排（swizzle = 起始 32B 偏移奇偶，`out_swizzle = stt_offset[0]`，
> NV_NVDLA_MCIF_READ_IG_bpt.v:387）都发生在写入两个 256b 重排 FIFO **之前**
> （eg.v:1051-1057 数据/写使能按 swizzle 交叉入队），客户端出口已按请求块序
> 紧凑重排。消费侧与之自洽：dc 按 `mask[0]+mask[1]` popcount 计块
> （NV_NVDLA_CDMA_dc.v:8015）、mask[0]→低 256b 写 sbuf p0、mask[1]→高 256b 写
> p1 且地址顺序递增（:8995、:9004；被注释掉的备选 p1_wr_addr 逻辑 :9042-9049
> 说明 2'b10 情形曾被考虑后放弃）；wt 同样假设紧凑（NV_NVDLA_CDMA_wt.v:6377
> popcount、:6762 `mask[1] ? p1 : p0` 取尾块）。**对 UT：mask=2'b10 属非法
> 输入，DUT 消费逻辑不支持（会静默错位，不报错）**，dma_slave_agent 不得生成；
> 奇数块数请求的响应最后一拍给 2'b01，其余拍恒 2'b11。

CDMA 用 rd_rsp_ready 反压响应（样板 dc.v:7918 `dma_rd_rsp_rdy = ~is_blocking`），
配合 shared_buffer（4.2 节）自行兜住在途数据——这是它不需要 credit 的结构原因。

> **UT 约定（未初始化内存）**：dma_slave_responder 对未预载地址回确定性 pattern
> `default_byte(addr) = addr[7:0] ^ addr[15:8] ^ addr[23:16] ^ 8'h5A`
> （verif/ut/common/dma/dma_slave_responder.svh:65）。refmodel 可独立复算；
> 测试若不显式预载内存镜像，即以此公式为数据事实源。

### 2.3 cdma2buf 写口（dat / wt 两套）

| 信号 | 方向 | 位宽 | 说明 | 代码 |
|---|---|---|---|---|
| cdma2buf_dat_wr_en | CDMA→CBUF | 1 | dat 写有效（无 ready，必须成功） | cdma.v:116 / cbuf.v:46 |
| cdma2buf_dat_wr_addr | → | 12 | [11:8]=bank，[7:0]=bank 内 entry | cdma.v:117 / cbuf.v:47；bank 切分 cbuf.v:887 |
| cdma2buf_dat_wr_hsel | → | 2 | **半 entry 写使能**：bit0=低 512b（列 c0），bit1=高 512b（列 c1）；hsel==0 非法（断言 cbuf.v:6330） | cdma.v:118 / cbuf.v:48；语义 cbuf.v:860-862 |
| cdma2buf_dat_wr_data | → | 1024 | 一个 entry（128B）数据 | cdma.v:119 / cbuf.v:49 |
| cdma2buf_wt_wr_en | → | 1 | wt 写有效 | cdma.v:121 / cbuf.v:51 |
| cdma2buf_wt_wr_addr | → | 12 | 同上切分 | cdma.v:122 / cbuf.v:52 |
| cdma2buf_wt_wr_hsel | → | 1 | **列选择**：0=写列 c0（低半 entry），1=写列 c1（高半 entry） | cdma.v:123 / cbuf.v:53；语义 cbuf.v:868-869 |
| cdma2buf_wt_wr_data | → | 512 | 半 entry（64B）数据 | cdma.v:124 / cbuf.v:54 |

> 注意 dat 与 wt 的 hsel 语义**不同**：dat 是 2 位独立使能（可同拍写整 entry，也可
> 只写半个），wt 是 1 位二选一（一拍只写半 entry，凑两拍成一个 entry）。dat 口由
> cvt 驱动（NV_NVDLA_CDMA_cvt.v:11008-11011），wt 口由 wt 子模块直接驱动、不经 cvt
> （cdma.v:538 u_wt 实例直连）。

写到 RAM 阵列有内部 2 级重定时（sel 译码 d1 → we/wa/wdat d2 → RAM），文件头注释标
"Input write latency: 4 cycle (1 cycle for raw ram access)"（cbuf.v:847-851）——对
写方不可见，仅影响写后读的时序余量（hazard 断言见 4.4）。

### 2.4 sc2buf 读口（dat / wt / wmb 三通道）

| 通道 | 请求（CSC→CBUF） | 返回（CBUF→CSC） | 代码 |
|---|---|---|---|
| dat | sc2buf_dat_rd_en + addr[11:0] | sc2buf_dat_rd_valid + data[1023:0] | cbuf.v:56-60 |
| wt | sc2buf_wt_rd_en + addr[11:0] | sc2buf_wt_rd_valid + data[1023:0] | cbuf.v:62-66 |
| wmb | sc2buf_wmb_rd_en + addr[7:0] | sc2buf_wmb_rd_valid + data[1023:0] | cbuf.v:68-72 |

协议要点（对 UT 是核心时序合同）：

- **固定 6 拍延迟、无反压**：valid 就是 en 打 6 拍（延迟链尾部
  cbuf.v:6208-6248，输出 assign :6290-6297）；三通道各有一条
  `nv_assert_at_time_interval #(0,6,1,...)` 断言钉死 en→valid 恰 6 拍
  （dat :6945、wt :6992、wmb :7039）。
- 读一次返回**整 entry 1024b**：bank 内两列同拍读出（选择样板 cbuf.v:3505-3514），
  数据低 512b=列 c0、高 512b=列 c1（:6250-6259）。
- **wmb 通道固定读 bank15**：地址只有 8 位（entry 号），en 直接命中 b15 两列
  （:3984-3990，entry 地址接入 :4512-4526）；读口接入见 :3485-3492。
- en 拉高期间可背靠背流水（每拍一个新地址），数据按发起顺序 6 拍后逐拍返回。

### 2.5 cdma2sc / sc2cdma 状态-信用面

CBUF 本身无握手，空间/数据的安全性靠这组 CDMA↔CSC 的记账接口维护：CDMA 写完通告
"新增了多少"，CSC 用完归还"释放了多少"。

| 信号 | 方向 | 位宽 | 语义 | 代码 |
|---|---|---|---|---|
| cdma2sc_dat_updt / entries / slices | CDMA→CSC | 1/12/12 | 单拍脉冲+**增量**：新写入 CBUF 的 dat entry 数与 slice（行）数（对账公式见 4.5 节） | cdma.v:165-167；生成于 status（NV_NVDLA_CDMA_status.v:983、:2148——updt 是 update_dma 延迟 9 拍，对齐 cbuf 写入落地） |
| sc2cdma_dat_updt / entries / slices | CSC→CDMA | 1/12/12 | 单拍脉冲+增量：CSC 已消费完、归还的 entry/slice 数 | cdma.v:169-171；status.v:541（entries_sub）、:547-560 |
| cdma2sc_wt_updt / kernels / entries / wmb_entries | CDMA→CSC | 1/14/12/9 | weight 侧通告（增量）：新增 kernel 数、wt entry 数、wmb entry 数（kernels 高 8 位恒 0，wt.v:11130；wmb_entries 单位 entry、9 位可表达满 bank 256） | cdma.v:187-190；NV_NVDLA_CDMA_wt.v:11126-11129 |
| sc2cdma_wt_updt / kernels / entries / wmb_entries | CSC→CDMA | 1/14/12/9 | weight 侧归还 | cdma.v:192-195；wt.v:8306（归还入账样板） |
| sc2cdma_dat_pending_req / **cdma2sc_dat_pending_ack** | in / out | 1/1 | 层间清账握手：CSC 请求暂停，CDMA 进 pending 态应答并把 valid_entries/slices/wr_idx 清零 | cdma.v:183、:129；status.v:502（ack 条件）、:554、:642（清零）、:973、:977 |
| sc2cdma_wt_pending_req / **cdma2sc_wt_pending_ack** | in / out | 1/1 | 同上，weight 侧 | cdma.v:185、:131；wt.v:2507 |

> **勘误/补注（2026-08-02，阶段 3.2 csc_cmac_cacc UT 实测发现）**：
> **sc2cdma_wt_kernels 是归还方向的死字段**——CSC 侧硬拴 0
> （vmod/nvdla/csc/NV_NVDLA_CSC_wl.v:3753 `assign sc2cdma_wt_kernels = 14'b0;`），
> CDMA 侧上游自注 "sc2cdma_wt_kernels are useless"（NV_NVDLA_CDMA_wt.v:8190），
> 归还入账只消费 entries。两侧自洽，属上游有意废弃，不是 bug；**跨单元的 weight
> 归还账实际只靠 entries 一本**，kernels 账本仅在 cdma2sc（通告）方向有效。
> 对 UT：cdma_sc 类 stub/refmodel 不应对 sc2cdma_wt_kernels 建立非零预期或守恒
> 校验（对偶记录见 csc-cmac-cacc.md §5.13）。

### 2.6 中断

| 信号 | 位宽 | 语义 | 代码 |
|---|---|---|---|
| cdma_dat2glb_done_intr_pd | 2 | dat 侧层完成脉冲：**bit0=组 0（consumer=0 时 done），bit1=组 1**；单拍（done 上升沿检测） | cdma.v:137；NV_NVDLA_CDMA_status.v:321-322（`~done_d1 & done` 边沿 + consumer 选 bit）、:365（输出） |
| cdma_wt2glb_done_intr_pd | 2 | weight 侧层完成脉冲，bit 语义同上 | cdma.v:147；status.v:311-312、:364 |

dat 与 wt 是两个独立中断源（GLB 侧各有 mask/status 位）；一层的 dp2reg_done（乒乓
翻转）要等两者都 done（4.5 节）。

### 2.7 杂项

| 信号 | 方向 | 位宽 | 说明 | 代码 |
|---|---|---|---|---|
| pwrbus_ram_pd | in | 32 | RAM 电源控制总线，透传给 cbuf/shared_buffer/各 fifo 的 RAM 宏 | cdma.v:181 / cbuf.v:44 |
| dla_clk_ovr_on_sync / global_clk_ovr_on_sync | in | 1/1 | 时钟门控 override（同步后），进各 SLCG 实例 | cdma.v:197-198 |
| tmc2slcg_disable_clock_gating | in | 1 | 测试模式关门控 | cdma.v:199 |

CDMA 内部 8 个 SLCG 门控域（slcg_op_en[7:0]：wt=0、dc=1、wg=2、img=3、dma_mux=4、
cvt=5、cvt-HLS=6、shared_buffer=7，按 cdma.v 各 u_slcg_* 实例的 slcg_en_src_0 接线）。

## 3. 寄存器组

### 3.1 地址块与 S/D 划分

- 字节块 **0x5000**（CSB 译码第 5 页，CSB_TGT_CDMA=5，可对照
  verif/ut/common/base/ut_types.svh:21；链路见 csb-link.md 5 节）。
- 单元内偏移 < 0x010 走 single 组，≥ 0x010 走 dual 组（ping-pong 双组）：
  `select_s = offset < 0x010`、`select_d0/d1 = offset ≥ 0x010 & producer==0/1`
  （NV_NVDLA_CDMA_regfile.v:925-927）。

> 注意：CDMA 的 S/D 分界是 **0x010**，与 CDP 的 0x048 不同（CDP 的 single 组还带
> LUT 口，见 csb-link.md 10.1 节）——"各引擎分界都是 0x048"是错误记忆。

ping-pong 机制与 CDP 同型：

- producer 决定 CSB 访问落哪组，**op_en 置位期间该组写保护**：
  `d0_reg_wr_en = wr_en & select_d0 & ~d0_op_en`（regfile:932-933；违规写有断言
  :976、:1023）；
- consumer 决定数据通路取哪组参数：`op_en_ori = consumer ? d1_op_en : d0_op_en`
  （:865；op_en 再打 3 拍出 reg2dp_op_en，:871-882）；
- **dp2reg_done 时 consumer 翻转**并清对应组 op_en（翻转 :725 + 时序块，d0 清除
  :829-831，d1 清除 :848-850）；
- S_STATUS 两个 2 位字段：0=idle（该组 op_en 未置）、**1=running（consumer 正指向
  本组）、2=pending（op_en 已置但 consumer 在另一组）**（:799-810：status_0 在
  consumer==1 时为 2，即组 0 在硬件消费组 1 期间是 pending）。

### 3.2 S 组（0x5000-0x500c，单份共享）

| 字节偏移 | 寄存器 | 字段（bit 布局） | 复位值 | 代码（NV_NVDLA_CDMA_single_reg.v） |
|---|---|---|---|---|
| 0x5000 | S_STATUS | status_1[17:16]、status_0[1:0]（只读） | 0 | 译码 :78，布局 :83 |
| 0x5004 | S_POINTER | consumer[16]（只读）、producer[0]（可写） | 0 | 译码 :77，布局 :82，写 :139 |
| 0x5008 | S_ARBITER | arb_wmb[19:16]、arb_weight[3:0] | wmb=0x3、weight=0xF | 译码 :75，复位 :119-120 |
| 0x500c | S_CBUF_FLUSH_STATUS | flush_done[0]（只读） | 0（flush 完成后置 1，见 4.4 节复位 flush） | 译码 :76，布局 :81；flush_done = dat & wt 双完成（regfile.v:1752） |

### 3.3 D 组全表（0x5010-0x50e8，双份乒乓）

全部 55 个寄存器的译码表在 vmod/nvdla/cdma/NV_NVDLA_CDMA_dual_reg.v:336-390（wren
比较式），读值字段拼装 :392-446。RW 属性：除 4 个统计计数器与 perf 计数器为只读
外均可写（写只读寄存器仅仿真告警）。

| 偏移 | 寄存器 | 内容概要（字段=bit 布局，摘自 :392-446） |
|---|---|---|
| 0x5010 | D_OP_ENABLE | op_en[0] |
| 0x5014 | D_MISC_CFG | conv_mode[0]、in_precision[9:8]、proc_precision[13:12]、data_reuse[16]、weight_reuse[20]、skip_data_rls[24]、skip_weight_rls[28] |
| 0x5018 | D_DATAIN_FORMAT | datain_format[0]、pixel_format[13:8]、pixel_mapping[16]、pixel_sign_override[20] |
| 0x501c | D_DATAIN_SIZE_0 | width[12:0]、height[28:16] |
| 0x5020 | D_DATAIN_SIZE_1 | channel[12:0] |
| 0x5024 | D_DATAIN_SIZE_EXT_0 | width_ext[12:0]、height_ext[28:16]（WG 用） |
| 0x5028 | D_PIXEL_OFFSET | x[4:0]、y[18:16] |
| 0x502c | D_DAIN_RAM_TYPE | datain_ram_type[0]（1=MC/0=CV） |
| 0x5030/0x5034 | D_DAIN_ADDR_HIGH/LOW_0 | 64 位地址；low[31:5] 有效、恒 32B 对齐 |
| 0x5038/0x503c | D_DAIN_ADDR_HIGH/LOW_1 | 第二平面地址（IMG YUV 半平面） |
| 0x5040 | D_LINE_STRIDE | line_stride[31:5]（32B 粒度） |
| 0x5044 | D_LINE_UV_STRIDE | uv_line_stride[31:5] |
| 0x5048 | D_SURF_STRIDE | surf_stride[31:5] |
| 0x504c | D_DAIN_MAP | line_packed[0]、surf_packed[16] |
| 0x5050 | D_RESERVED_X_CFG | rsv_per_line[9:0]、rsv_per_uv_line[25:16] |
| 0x5054 | D_RESERVED_Y_CFG | rsv_height[15:13]、rsv_y_index[20:16]（布局见 :431） |
| 0x5058 | D_BATCH_NUMBER | batches[4:0] |
| 0x505c | D_BATCH_STRIDE | batch_stride[31:5] |
| 0x5060 | D_ENTRY_PER_SLICE | entries[11:0]——一个 slice 占多少 entry（**0-based**，实际 = 值+1，见 4.5 节） |
| 0x5064 | D_FETCH_GRAIN | grains[11:0]——攒多少 slice 通告一次 CSC（**0-based**；line_packed=0 时被忽略、恒按 1，见 4.5 节） |
| 0x5068 | D_WEIGHT_FORMAT | weight_format[0]（0=非压缩/1=压缩） |
| 0x506c | D_WEIGHT_SIZE_0 | byte_per_kernel[17:0] |
| 0x5070 | D_WEIGHT_SIZE_1 | weight_kernel[12:0]（kernel 数-1） |
| 0x5074 | D_WEIGHT_RAM_TYPE | weight_ram_type[0] |
| 0x5078/0x507c | D_WEIGHT_ADDR_HIGH/LOW | weight 基址（low 32B 对齐） |
| 0x5080 | D_WEIGHT_BYTES | weight_bytes[31:7]（128B 粒度） |
| 0x5084/0x5088 | D_WGS_ADDR_HIGH/LOW | 压缩模式 weight group size 表基址 |
| 0x508c/0x5090 | D_WMB_ADDR_HIGH/LOW | 压缩模式 weight mask bit 基址 |
| 0x5094 | D_WMB_BYTES | wmb_bytes[27:7] |
| 0x5098 | D_MEAN_FORMAT | mean_format[0] |
| 0x509c | D_MEAN_GLOBAL_0 | mean_ry[15:0]、mean_gu[31:16] |
| 0x50a0 | D_MEAN_GLOBAL_1 | mean_bv[15:0]、mean_ax[31:16] |
| 0x50a4 | D_CVT_CFG | cvt_en[0]、cvt_truncate[9:4] |
| 0x50a8 | D_CVT_OFFSET | cvt_offset[15:0] |
| 0x50ac | D_CVT_SCALE | cvt_scale[15:0] |
| 0x50b0 | D_CONV_STRIDE | conv_x_stride[2:0]、conv_y_stride[18:16] |
| 0x50b4 | D_ZERO_PADDING | pad_left[4:0]、pad_right[13:8]、pad_top[20:16]、pad_bottom[29:24] |
| 0x50b8 | D_ZERO_PADDING_VALUE | pad_value[15:0] |
| 0x50bc | **D_BANK** | **data_bank[3:0]、weight_bank[19:16]**（均为 bank 数-1；布局 :392）——CBUF 空间划分唯一来源 |
| 0x50c0 | D_NAN_FLUSH_TO_ZERO | nan_to_zero[0] |
| 0x50c4/0x50c8 | D_NAN_INPUT_DATA/WEIGHT_NUM | NaN 输入计数（只读） |
| 0x50cc/0x50d0 | D_INF_INPUT_DATA/WEIGHT_NUM | Inf 输入计数（只读） |
| 0x50d4 | D_PERF_ENABLE | dma_en[0] |
| 0x50d8/0x50e0 | D_PERF_DAT_READ_STALL/LATENCY | dat 读性能计数（只读） |
| 0x50dc/0x50e4 | D_PERF_WT_READ_STALL/LATENCY | wt 读性能计数（只读） |
| 0x50e8 | D_CYA | cya[31:0]（chicken bits） |

### 3.4 重点字段语义（数据通路消费点）

| 字段 | 消费点 |
|---|---|
| conv_mode / datain_format | 1.2 节四通路选择（dc.v:2472-2487 等三处） |
| data_bank / weight_bank | status 记账容量 `real_bank = data_bank+1`（status.v:483）、free_entries 基数（:598）；weight 区起止（wt.v:3108-3125，见 4.4 节布局） |
| entries（D_ENTRY_PER_SLICE） | `data_entries = 寄存器值 + 1`（dc.v:3296-3300，0-based）；容量断言 dc.v:2644 |
| grains（D_FETCH_GRAIN） | `fetch_grain = line_packed ? 寄存器值+1 : 1`（dc.v:3312-3318——**非 line_packed 时忽略寄存器、恒按 1 slice 通告**） |
| batches（D_BATCH_NUMBER） | `entry_per_batch = data_entries × (batches+1)`（dc.v:4480-4486） |
| cvt_en / offset / scale / truncate | cvt 换算（4.3 节） |
| arb_weight / arb_wmb（S 组） | wt 内 weight/wmb 加权轮询仲裁权重（4.6 节） |

### 3.5 与 Ordt / 生成产物的对照方法

> **勘误（对照方法与团队印象不符）**：`spec/manual/` 下**没有** CDMA（或任何 NVDLA
> 单元）的寄存器描述——该目录只是 Ordt 工具链演示（test.rdl → regs_v.v/regs_ral.sv，
> 见 spec/manual/README.md；生成产物 outdir/nv_full/spec/manual/regs_ral.sv 中无
> CDMA 内容，已实测检索）。CDMA 寄存器的**权威来源就是 arreggen 生成的
> NV_NVDLA_CDMA_single_reg.v / dual_reg.v 本身**；交叉核对请对照生成产物
> outdir/nv_full/vmod/nvdla/cdma/NV_NVDLA_CDMA_dual_reg.v（生成文件，与 vmod 同文）
> 以及官方 http://nvdla.org/hw/v1/ias/programming_guide.html 的寄存器手册。

## 4. 机制点

### 4.1 dma_mux：dat 三客户端合一出口——是选择器不是仲裁器

dc/wg/img 三路 dat 读请求经 NV_NVDLA_CDMA_dma_mux 合成对外一路 cdma_dat2*
（例化 cdma.v:897）。实现上**没有仲裁逻辑**：

- 请求侧 valid 直接 OR、pd 按 valid 掩码 OR（NV_NVDLA_CDMA_dma_mux.v:297、:307、
  :320），随后过一级 skid buffer + 一级 pipe（:336-397，共 2 拍缓冲）；
- ready 只回给当拍拉 valid 的那路（:506）；
- 响应按"请求被接受时寄存的 sel"路由回源（sel 寄存 :529，响应分发 :1645）；
- 正确性前提是 **dc/wg/img 同层互斥**（1.2 节激活条件保证），破坏前提由
  `zero_one_hot` 断言兜底（MCIF 侧 :1384、CVIF 侧 :1431）。

wt 通路不经 dma_mux，自己独占 cdma_wt2* 一对口。

### 4.2 shared_buffer：dc/wg/img 分时复用的行缓冲

- 16 片 nv_ram_rws_16x256（NV_NVDLA_CDMA_shared_buffer.v:2180-2371），总容量
  16×16×256b = 8KB；
- 每客户端两套端口 p0/p1（各 256b 宽），8 位地址切分 [7:4]=片选、[3:0]=片内 entry
  （写 :533、读 :2376、:3427）；
- 三客户端的写使能/写数据对每片 RAM 做 OR-mux（:1223、:1837）——又一个"靠互斥不靠
  仲裁"的复用，同片读写冲突有断言（:4943）；
- 用途：DMA 响应先落行缓冲攒齐一个 slice/interleave 单元，再成批送 cvt 打包成
  entry；DC 通路里 p0 收响应低 256b（mask[0]）、p1 收高 256b（mask[1]）
  （dc.v:8995、:9004）。这也是 CDMA 能承接"无 credit 的读响应"的落点（2.2 节）。

### 4.3 cvt：mean/scale/truncate 换算与 bypass

- 64 个 16 位 MAC 换算单元（NV_NVDLA_CDMA_CVT_cell 例化
  NV_NVDLA_CDMA_cvt.v:6407-7856），算式为 `(x − 均值/offset) × scale >> truncate`；
- 配置在层启动时锁存并复制到每 cell：scale :1101、truncate :1162、offset :1284、
  cvt_en :1223；
- 操作数二选一：IMG 通路带 per-pixel mean 数据时用 mean（img2cvt_mn_wr_data，
  :2049、:4769 起 64 个同构 mux），否则用 D_CVT_OFFSET；
- **cvt_en=0 时整体 bypass**：输出 mux `cfg_cvt_en[5] ? cell_out : bypass`
  （:10082；bypass 半 entry 对齐处理 :10073-10074）；
- bypass/换算之后统一做 pad 字节替换（IMG 的 pad_mask 位置填 D_ZERO_PADDING_VALUE，
  :10087 起逐字节 mux）；
- 最终寄存一拍出 cdma2buf_dat 写口（:11008-11011）。wt 数据不做换算、不经此模块。

### 4.4 cbuf 组织、entry 数据摆放与断言合同

**物理组织**：16 bank × 2 列（column）× nv_ram_rws_256x512（cbuf.v:3098-3481，共
32 片）。一列 512b 宽、256 深；一个 entry = 同 bank 两列同地址拼 1024b（128B）；
bank = 256 entry = 32KB；全阵列 **512KB**。地址恒为 {bank[3:0], entry[7:0]}。

**空间划分**（由 CDMA D_BANK 配置 + 断言表达，CBUF 无硬件强制）：

- **data 区**：bank[0 .. data_bank]，共 data_bank+1 个 bank；
- **weight 区紧跟 data 区连续放置**：bank[data_bank+1 .. data_bank+weight_bank+1]。
  wt 写指针复位/层起点为 `{data_bank+1, 9'b0}`（半 entry 单位，wt.v:6734）、到
  `{weight_bank_end, 9'b0}` 回绕（:6724；`weight_bank_end = (data_bank+1)+(weight_bank+1)`，
  :3108-3125）。配置合法性断言：非压缩 data+weight ≤ 16 bank（wt.v:2827）、压缩
  ≤ 15（:2874，bank15 让给 wmb）；
- **wmb 恒 bank15**：wmb 写指针高 4 位拴死 4'hF（wt.v:6940-6941、:7035），bank 内
  9 位半 entry 计数即 256 entry（32KB）整 bank；与 wmb 读口只连 bank15 的物理结构
  （2.4 节）对偶。

**entry 内数据摆放（DC 通路，refmodel 对账依据）**：

- 基本颗粒是 **32B atom = channel 方向连续元素块**：int8 装 32 个通道元素、int16
  装 16 个（每元素 2B 小端）。surface（C' 面）数 = `ceil(C/32)`（int8）或
  `ceil(C/16)`（int16）（`data_surface_inc`，dc.v:3288-3294）；
- **entry = 4 个 atom 按 channel-surface 升序拼接**（同精度模式）：同一 (w,h) 位置
  的 surface c、c+1、c+2、c+3 依次占 entry 字节 [31:0]、[63:32]、[95:64]、[127:96]。
  组装以 64B 半 entry 为节拍：每 2 个 atom 填一半，hsel 取通道计数 bit1
  （`cbuf_wr_hsel_w`，dc.v:11460-11461 normal 项）；
- **surface 不足 4 时按 W 方向打包**多个像素位置进一个 entry：1 surface → 4 个 W
  位置/entry（div4）、2 surface → 2 个/entry（div2）（判定 :11392-11408，entry
  索引步进 :11417-11420）；行尾/通道尾残余字节由 cvt 的 nz_mask 依 ext64/ext128
  指示置 0（:11484-11497）；
- **精度换算模式**（in_precision vs proc_precision，dc.v:3227-3241）：
  - normal（同精度）：如上，int8 128 元素/entry、int16 64 元素/entry；
  - expand（int8 输入→int16 处理）：每个输入 atom 经 cvt 扩位后占 64B 半 entry
    （hsel=通道计数 bit0），entry = 2 个输入 atom = 64 个 int16 元素；
  - shrink（int16 输入→int8 处理）：4 个输入 atom 缩位后占 64B 半 entry
    （hsel=通道计数 bit2），entry = 8 个输入 atom = 128 个 int8 元素；
  - 取数分组粒度与之配套：`req_ch_mode` = shrink 4 / 其他 2 / packed_1x1 1
    （:5912-5914）。
- IMG 通路由 `IMG_pack` 负责 packed/planar pixel 解包、YUV/RGB 分量位置整理，并生成
  data/mean/pad mask 后送 CVT；整体边界见 1.4.3～1.4.4。具体逐格式 bit lane 规则应在
  IMG 模块级 spec 中单独展开，不能把它理解成提前展开卷积滑窗。
- **weight 区摆放**：wt/wgs 数据是线性字节流（压缩流或 `byte_per_kernel×kernel`
  裸流），按到达顺序填 64B 半 entry、hsel=半 entry 计数 bit0（wt.v:7390-7404），
  低半在前；wmb 流同规则填 bank15。

> **补注（2026-08-02，权重流的消费面格式——阶段 3.2 UT 实测踩坑教训）**：上一条
> "线性字节流"描述的是 **CDMA 搬运面**（bpk×K 裸流按到达序填半 entry），没有错；
> 但这条字节流本身的**软件编排格式**（即 CSC 消费面约定）是：**外层按 64 通道一轮
> （C 轮），轮内是 kernel-slot 的 128B beat 序列**——
> - int16：beat j = kernel j 在本轮的 64 通道 × 2B；
> - int8：beat j = kernel 2j 与 kernel 2j+1 各自本轮 64B 的前后半拼接；K 为奇数时
>   末 beat 高 64B 补 0；
> - `D_WEIGHT_BYTES` = 此流的总字节数（寄存器字段本身按 128B 粒度存放，即 >>7 值；
>   CSC 侧直接把该值当 entry 数消费，NV_NVDLA_CSC_wl.v:1899 last_weight_entries）。
>
> **TB/测试直造 cbuf 权重镜像时必须按消费面格式生成**，不能按"kernel 连续裸流"的
> 直觉排布——csc_cmac_cacc UT（Wave 2）实测按裸流直觉造数导致全错，按上述格式
> 修正后 9/9 绿（对偶记录见 csc-cmac-cacc.md §4.3）。CDMA 整链（外存→cbuf）之所以
> 自然满足该格式，是因为软件在外存中就按此编排（1.4.1 节"软件先准备什么"）。

**复位 flush（DV 实测已证实，代码依据如下）**：复位释放后 CDMA 自动把整个 CBUF
清零一遍，**与 D_BANK 配置无关**（flush 计数器是纯自由计数，不看任何寄存器）：

- dat 侧（cvt 内）：13 位计数器自 0 数到 4095 共 **4096 拍**（cvt.v:10927-10950），
  每拍经 cdma2buf_dat 口写一个**半 entry**：addr = idx[12:1]（覆盖 bank0-7 的全部
  2048 entry），hsel = {idx[0], ~idx[0]} 低/高半交替（:10240、:10249）；写数据取
  自输出数据寄存器的复位值，恒 0（:10254-10255，flush 期间 reg_en 不置位）；
- wt 侧（wt 内）：同构 13 位计数 4096 拍（wt.v:7296-7319），addr =
  {1'b1, idx[11:1]}（**覆盖 bank8-15** 的全部 2048 entry），hsel = idx[0]，
  数据明文 512'b0（:7392、:7404、:7413-7415）；
- 两侧合计恰好把 16 bank × 256 entry 的每个半 entry 各写一次全 0；
  S_CBUF_FLUSH_STATUS.flush_done = dat 完成 & wt 完成（cvt.v:10939、wt.v:7308、
  regfile.v:1752）。软件应在配层前轮询 flush_done=1。

**断言合同**（+define+ASSERT_ON 下有效，是 UT 的负面测试清单）：

| # | 断言（均 nv_assert_never，除注明外） | 行号（cbuf.v） |
|---|---|---|
| 1 | dat 写 hsel==0（无效写） | :6330 |
| 2 | dat 写 bank15 | :6378 |
| 3 | wt 写 bank0 | :6425 |
| 4 | dat 写与 wt 写同拍同 bank | :6472 |
| 5 | dat 读 bank15 | :6520 |
| 6 | wt 读 bank0 | :6567 |
| 7 | dat 读与 wt 读同拍同 bank | :6614 |
| 8 | wt 读与 wmb 读同拍且 wt 读的是 bank15 | :6661 |
| 9 | dat 读写同拍同地址 | :6709 |
| 10 | wt 读写同拍同地址 | :6756 |
| 11 | wmb 读与 wt 写 bank15 同拍撞地址 | :6803 |
| 12 | dat 写与 wt 读同拍同 bank | :6850 |
| 13 | wt 写与 dat 读同拍同 bank | :6897 |
| 14-16 | en→valid 恰 6 拍（at_time_interval，dat/wt/wmb） | :6945 / :6992 / :7039 |
| 17-20 | eccgen 通路不许回压/失配（内部自检） | :7087-:7228 |

> **疑似 RTL 笔误（仅断言，不影响功能逻辑）**：#11（:6803）的地址比较写的是
> `cdma2buf_wt_wr_addr[7:0] == sc2buf_wt_rd_addr`——右侧应为 `sc2buf_wmb_rd_addr`
> （且 8 位对 12 位位宽不匹配）。按现文该断言比较的是 wmb 读使能与 **wt 读地址**，
> 检测面变形。文档如实记录，不改 RTL；UT 不应依赖该条断言的精确性。

**同拍多口能力**：dat 写、wt 写、dat 读、wt 读、wmb 读五个口可同拍活动，只要落在
不同 bank（wmb 恒 bank15，故与 wt 读 bank15 冲突即 #8）。

### 4.5 entry/slice 记账与层切换（status）

NV_NVDLA_CDMA_status（例化 cdma.v:1105）维护 dat 侧 CBUF 占用账本：

- `real_bank = reg2dp_data_bank + 1`（status.v:483）；
- `valid_entries += 本层 DMA 通告(entries_add) − CSC 归还(entries_sub)`
  （:532、:541、:554）；`free_entries = {real_bank,8'b0} − valid_entries`
  （:598，即 real_bank×256 − valid_entries）；valid_slices 同构；
- 写指针 `wr_idx` 在 data 区内环回（增量+回绕 :607-:642）；
- 各 DMA 在 free_entries 不足时停发请求；注意**单层 dat 足迹超配置 bank 容量是
  显式非法配置**（dc.v:2644 nv_assert_never "data bank is not big enough"，T5
  开发中实测触发）——**层内不存在停等-归还推进**，停等只发生在跨层挤占场景
  （前层数据未释放，本层配置合法但空间被占，T5 即此场景）；

**通告（updt）对账公式（DC 通路，refmodel 依据）**——updt 携带的是**增量**，
status 侧累加，不是绝对值：

- 每攒满一个 grain 发一次 updt（dc.v:13320-13330 载入、:13838-13840 输出，经
  d0-d3 四级流水）；
- `slices 增量 = min(fetch_grain, 本层剩余行数)`（首/尾 grain 取余：
  dc.v:4147-4153、:9614-9620）；其中
  `fetch_grain = line_packed ? (D_FETCH_GRAIN+1) : 1`（:3312-3318）；
- `entries 增量 = slices 增量 × entry_per_batch`，
  `entry_per_batch = (D_ENTRY_PER_SLICE+1) × (D_BATCH_NUMBER+1)`
  （entry_required :4910-4916、entry_per_batch :4480-4486、data_entries=寄存器+1
  :3296-3300）；
- 整层校验式：Σ(entries 增量) = 总 slice 数 × (entries+1) × (batches+1)，
  Σ(slices 增量) = datain_height+1；
- **dat 与 wt 双双 done 才切层**：`fsm_switch_w = op_en & ~switch & wt_done &
  dat_done`（:299，dat_done 为 dc/wg/img done 之或 :287），`dp2reg_done =
  fsm_switch`（:363）驱动 regfile 翻 consumer/清 op_en（3.1 节）；
- 层切换清账：sc2cdma_dat_pending_req 置位期间 CDMA 应答 pending_ack 并把
  valid_entries/valid_slices/wr_idx 清零（:502、:554、:642、:973、:977）——data_reuse
  跨层保留数据时不走此路径；
- cdma2sc_dat_updt 输出侧延迟 9 拍（:983 入、:2148 出），保证 CSC 看到 updt 时
  数据已实际写进 cbuf RAM（覆盖 cvt/cbuf 内部流水深度）。

weight 侧账本在 wt 模块内部（kernels/entries/wmb_entries 三本，通告 :11126-11129，
归还入账样板 :8306），不经 status；wmb_entries 单位是 bank15 内 entry 数（9 位，
满 bank 256）。

### 4.6 weight 通路仲裁

压缩模式下 wt 要同时取 weight、wmb（mask bit）、wgs（group size）三种流，内部用
加权轮询（WRR）+ 固定优先级两级仲裁合成一路 DMA 请求：NV_NVDLA_CDMA_WT_wrr_arb
（wt.v:5789 例化，权重来自 S_ARBITER 的 arb_weight/arb_wmb，复位 15:3）与
NV_NVDLA_CDMA_WT_sp_arb（:5908）。非压缩模式只有 weight 一路，仲裁退化为直通。

> **实现不对称（DV 波形实证，2026-08-01）**：wt/wmb/wgs 的响应消费**没有**请求
> 信息 FIFO 头有效门控——`wt_rsp_valid = 响应握手 & (dma_rsp_src==SRC_ID_WT)`
> 直接采样 src（wt.v，wmb/wgs 同构；对比 dc 侧有 `is_rsp_ch0 =
> dma_rsp_fifo_req & (dma_rsp_ch_idx==0)` 的 FIFO 头门控）。隐性时序契约：
> **响应不得快于请求握手后约 6 拍**，否则请求信息 FIFO 尚未读出、src=X 污染
> wt FSM（UT 波形实证：响应提前 7ns 消费即 cur_state 全 X）。真实 mcif/cvif
> 往返远大于此，系统内不可达；属 dc/wt 实现不对称而非功能 bug。UT 的
> dma_slave 以 `rd_rsp_first_min=6` 默认约束遵守该契约。

## 5. 代码入口表

vmod/nvdla/cdma/ 共 25 个 .v 文件 + vmod/nvdla/cbuf/ 1 个，按功能族分组：

| 功能族 | 文件（vmod/nvdla/cdma/） | 说明 |
|---|---|---|
| 顶层 | NV_NVDLA_cdma.v | 端口 :113-199；9 个功能实例 + 8 个 SLCG 实例（u_regfile :417、u_wt :522、u_dc :606、u_wg :696、u_img :791、u_dma_mux :897、u_cvt :969、u_shared_buffer :1043、u_status :1105） |
| 寄存器 | NV_NVDLA_CDMA_regfile.v、NV_NVDLA_CDMA_single_reg.v、NV_NVDLA_CDMA_dual_reg.v | CSB 终点、S 组、D 组×2（3 节） |
| DC | NV_NVDLA_CDMA_dc.v、NV_NVDLA_CDMA_DC_fifo.v | 直卷积 feature 取数；req/rsp 対账 fifo |
| IMG | NV_NVDLA_CDMA_img.v、NV_NVDLA_CDMA_IMG_ctrl.v、NV_NVDLA_CDMA_IMG_sg.v、NV_NVDLA_CDMA_IMG_pack.v、NV_NVDLA_CDMA_IMG_fifo.v、NV_NVDLA_CDMA_IMG_sg2pack_fifo.v | 图像输入：ctrl 状态机、sg 请求生成、pack 重排打包 |
| WG | NV_NVDLA_CDMA_wg.v、NV_NVDLA_CDMA_WG_fifo.v | Winograd 取数 |
| WT | NV_NVDLA_CDMA_wt.v、NV_NVDLA_CDMA_WT_fifo.v、NV_NVDLA_CDMA_WT_wgs_fifo.v、NV_NVDLA_CDMA_WT_wrr_arb.v、NV_NVDLA_CDMA_WT_sp_arb.v | weight/wmb/wgs 取数与两级仲裁 |
| CVT | NV_NVDLA_CDMA_cvt.v、NV_NVDLA_CDMA_CVT_cell.v | 64 cell 换算阵列（4.3 节） |
| 公共 | NV_NVDLA_CDMA_dma_mux.v、NV_NVDLA_CDMA_shared_buffer.v、NV_NVDLA_CDMA_status.v、NV_NVDLA_CDMA_slcg.v | 4.1/4.2/4.5 节；SLCG 门控单元 |
| CBUF | vmod/nvdla/cbuf/NV_NVDLA_cbuf.v | 单文件 RAM 阵列（4.4 节） |
| 集成 | vmod/nvdla/top/NV_NVDLA_partition_c.v | cdma :1600、cbuf :1669 例化 |

关键论断 file:line 速查（正文已逐条给出，此处只列高频引用）：

| 论断 | 位置 |
|---|---|
| 四通路激活条件 | dc.v:2472-2487 / IMG_ctrl.v:2329-2343 / wg.v:2429-2437 / wt.v:2433 |
| 读请求打包与对齐/0-based size | dc.v:7911-7916、:6343 |
| cdma 无 credit（tieoff=0） | nocif/NV_NVDLA_MCIF_READ_ig.v:321-329、:334-342；CVIF 同 :321-342；bpt 关断逻辑 …_IG_bpt.v:228、:236、:337 |
| 响应 mask 只有 2'b11/2'b01 | nocif/NV_NVDLA_MCIF_READ_eg.v:1095（生成）、dc.v:8015/:8995/:9004（消费） |
| cbuf 写口 hsel 语义 | cbuf.v:860-862（dat）、:868-869（wt） |
| cbuf 读 6 拍/无反压 | cbuf.v:6290-6297、断言 :6945/:6992/:7039 |
| wmb 固定 bank15（读/写） | cbuf.v:3984-3990 / wt.v:6940-6941 |
| weight 区起点/回绕 | wt.v:6734、:6724、:3108-3125 |
| 复位 flush（dat/wt 各 4096 拍全 0） | cvt.v:10927-10950、:10240、:10249 / wt.v:7296-7319、:7392、:7415；flush_done regfile.v:1752 |
| S/D 分界 0x010 与写保护 | regfile.v:925-927、:932-933 |
| D 组偏移全表 | dual_reg.v:336-390（字段 :392-446） |
| 双 done 切层 / free_entries 公式 | status.v:299、:598 |
| updt 增量公式（grain×entry_per_batch） | dc.v:4910-4916、:4480-4486、:3296-3318 |
| dat updt 延迟 9 拍 | status.v:983、:2148 |

## 6. UT 测试点 checklist（初版，2026-08-01）

测试映射：**T0** 寄存器面冒烟（DV 已跑绿）、**T1** DC/int16/bypass 主冒烟（四重
校验：cbuf 镜像 / updt 对账 / done+中断 / 寄存器状态）、**T2** int8+奇数尾块、
**T3** 响应扰动随机、**T4** 压缩权重、**T5** buffer-full 释放、**T6** ping-pong
双层。已核销项打 `[x]` 并注明归属。

> 2026-08-01 Wave 2 后：**44 条已核销 32 条**（回归 8/8 绿：T0/T1/T2/T3×3/T5/T6）。
> 未核销集中在 T4 压缩权重、cvt 专项与 6.6 负面激励（大部留 Wave 3）。

### 6.1 寄存器面

- [x] 复位值：S_ARBITER=0xF/0x3、S_POINTER=0、D 组全 0（3.2/3.3 节）——T0 已核销
- [x] D 组 0x5010-0x50e8 全寄存器 mask 化写读（写全 1 读回字段掩码）——T0 已核销
- [x] producer 影子：S_POINTER.producer 写读、consumer 只读——T0 已核销
- [x] 0x5000-0x50e8 全偏移扫描（含只读寄存器写仅告警不生效）——T0 已核销
- [x] csb2cdma_req_prdy 恒 1（regfile:1127）——T0 已核销
- [x] 复位后轮询 S_CBUF_FLUSH_STATUS.flush_done 置 1（dat+wt 双 flush 完成，regfile:1752）——T0 已核销
- [x] S_STATUS 三态编码：0=idle / 1=running（consumer 指向本组）/ 2=pending（regfile:799-810）——T6 已核销
- [x] done 后 consumer 自动翻转 + 本组 op_en 自动清（regfile:725、:829-850）——T6 已核销（consumer 翻两次回 0）
- [x] 第二组配置独立生效（d0 运行中编 d1，双层参数不串）——T6 已核销

### 6.2 DMA 读接口

- [x] req 字段还原：{size[14:0], addr[63:0]}、addr 32B 对齐、size 0-based（dc.v:7911-7916）——T1 已核销
- [x] 响应 mask 全程只见 2'b11/2'b01；奇数块请求最后一拍 2'b01（2.2 节勘误）——T2 已核销
- [x] ram_type 静态选路：datain/weight ram_type 各自独立走 mc/cv，不串——T1/T3 已核销（CV 双路由 T3 随机层覆盖）
- [x] 无 credit 行为确认：整层收不到任何 pop 事件（dma_slave 计数器恒 0）——T1 已核销
- [x] rd_rsp 首拍延迟/beat 间隔随机扰动下数据不丢不重、按请求序——T3×3 seeds 已核销
- [x] req_ready 背压扰动下 valid/pd 稳定重握手——T3 已核销（30% 背压）
- [x] dc 单客户端活跃期间 dma_mux 响应全部路由回 dc（wg/img 口静默）——T1 已核销

### 6.3 cbuf 写口与镜像

- [x] dat hsel 合法组合（2'b11 整 entry / 2'b01 / 2'b10 半 entry）按 refmodel 预期出现——T1/T2 已核销
- [x] wt hsel 0/1 交替、64B 半 entry 顺序填充（wt.v:7390-7404）——T1 已核销（非压缩）
- [x] **cbuf 镜像校验**：整层写入后 data 区镜像与 refmodel 逐字节一致（entry 布局按 4.4 节：atom 拼接 + W 打包 + 尾部置零）——T1（int16 normal）/T2（int8）已核销
- [x] 复位 flush 后全 4096 entry 镜像为 0（4.4 节）——已核销（各测试 scoreboard 吸收计数恒 8192 半 entry、数据全 0）
- [x] weight 区起始 bank = data_bank+1、写满回绕（wt.v:6734、:6724）——T1/T5 已核销（T5 实证跨层环形指针不复位）
- [ ] wmb 只落 bank15、entry 数与 wmb_bytes 一致（wt.v:6940-6941）——T4
- [x] sc2buf 三通道读回：en→valid 恰 6 拍、流水背靠背、数据低 c0 高 c1、与写入镜像一致——T1/T2/T3/T5 已核销（500+ 次读回全 match；wmb 通道待 T4）

### 6.4 记账与层控制

- [x] updt 增量对账：每次 dat updt 的 entries == slices × (D_ENTRY_PER_SLICE+1) × (batches+1)（4.5 节公式）——T1 已核销
- [x] 整层守恒：Σslices == datain_height+1；Σentries == 总 slice × entry_per_batch——T1 已核销
- [x] line_packed=0 时每次通告恒 1 slice（忽略 D_FETCH_GRAIN，dc.v:3316-3317）——T3 已核销（line_packed 两态随机覆盖）
- [x] updt 脉冲相对最后一拍 cbuf 写的 9 拍延迟（status.v:983/:2148）——T1 已核销（monitor 时序检查）
- [x] buffer-full：free_entries 耗尽时请求停发；sc2cdma 归还后恢复取数（status.v:598）——T5 已核销（停等期 req 冻结 32 笔实测）
- [ ] wt 三本账（kernels/entries/wmb_entries）增量守恒——部分核销（kernels/entries 由 T1/T3 覆盖，含 K=40 尾组；wmb_entries 待 T4）
- [x] dat done + wt done 双条件才 dp2reg_done；单侧 done 不切层（status.v:299）——T1 已核销
- [x] 中断：dat/wt 各自单拍脉冲、bit==当层 consumer 组号（status.v:311-322）——T1/T6 已核销（bit0/bit1 各恰 1 次）
- [x] pending req/ack 清账：ack 期间 valid_entries/slices/wr_idx 归零（status.v:502-642）——已核销（stub auto 服务，每层实跑）

### 6.5 cvt

- [x] cvt_en=0 bypass：写入数据 == 内存源数据逐字节透传（cvt.v:10082）——T1/T2/T3/T5/T6 已核销
- [ ] cvt_en=1：(x−offset)×scale≫truncate 算术与 refmodel 位精确一致——专项（T2 扩展）
- [ ] shrink/expand 精度换算模式下 entry 布局（4.4 节 expand/shrink 规则）——专项
- [ ] NaN/Inf 计数与 nan_to_zero（fp16）——暂缓（int 先行）

### 6.6 负面断言激励（+define+ASSERT_ON，独立小测，预期断言触发）

- [ ] dat 写 hsel==0（cbuf.v:6330）
- [ ] dat 写 bank15（:6378）/ wt 写 bank0（:6425）
- [ ] dat 写与 wt 写同拍同 bank（:6472）
- [ ] 读写同拍同地址 hazard（dat :6709 / wt :6756）
- [ ] op_en 置位期写当前 producer 组 D 寄存器（regfile:976/:1023）
- [ ] D_BANK 配置超限：非压缩 data+weight>16 / 压缩 >15（wt.v:2827/:2874）
- [x] data bank 容量 < entries×height（dc.v:2644）——T5 开发中实测触发（"data bank is not big enough"），合同确认见 4.5 节
- [ ] mask=2'b10 注入（预期消费错位、无断言——仅隔离 bench 观察，不进回归）
