# DMA 客户端协议（xx2mcif / xx2cvif DMA Interface）

NVDLA 各引擎（bdma、cdma、sdp_rdma、pdp_rdma、cdp_rdma、各 wdma、rbk…）访问外部内存都
不直接出 AXI，而是以统一的"DMA 客户端"形状挂到两个内存接口汇聚器上：**mcif**（外部
DRAM 路径，nocif/NV_NVDLA_mcif.v）与 **cvif**（SRAM/CV 路径，nv_full 双口都有）。本文定义
这一客户端协议。

> 位宽随引擎参数化（地址恒 64 位，size 位数与数据宽度随引擎吞吐不同）。本文以 **cdp 实例**
> 为样本：rd_req 79 位 / rd_rsp 514 位 / wr_req 515 位。其他引擎形状相同、仅位宽不同。
> 事实来源：vmod/ 源码实读（2026-07，nv_full）。

## 1. 定位与通道总览

每个客户端最多四个通道 × 两个目的地（mc/cv 各一套同构端口）：

| 通道 | 方向（客户端视角） | 握手 | 内容 |
|---|---|---|---|
| rd_req | out | valid/ready | 读命令 {addr, size} |
| rd_rsp | in | valid/ready | 读数据 {data, mask} |
| rd_cdt_lat_fifo_pop | out | 单比特脉冲，无握手 | latency FIFO 信用归还（见 4 节） |
| wr_req | out | valid/ready | 写命令/写数据复用一个通道（[514]=id 区分，见 5 节） |
| wr_rsp_complete | in | 单比特脉冲，无握手 | 写完成应答（仅 require_ack=1 的命令有，见 5.2 节） |

寄存器组说明：不适用（本文是纯接口协议；各客户端由谁发起、地址从哪来属单元 spec）。

## 2. 接口信号表（CDP 实例）

读侧位于 cdp_rdma（vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v:59-65 端口声明），写侧位于
cdp wdma（vmod/nvdla/cdp/NV_NVDLA_CDP_wdma.v:49-59）。mc 一套如下，cv 完全同构（前缀
cdp2cvif/cvif2cdp）：

| 信号 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| cdp2mcif_rd_req_valid / _ready | out / in | 1 | 读请求握手 |
| cdp2mcif_rd_req_pd | out | 79 | {size[14:0], addr[63:0]}，见 3.1 |
| mcif2cdp_rd_rsp_valid / _ready | in / out | 1 | 读响应握手（**客户端可回压**） |
| mcif2cdp_rd_rsp_pd | in | 514 | {mask[1:0], data[511:0]}，见 3.2 |
| cdp2mcif_rd_cdt_lat_fifo_pop | out | 1 | 信用归还脉冲 |
| cdp2mcif_wr_req_valid / _ready | out / in | 1 | 写请求握手 |
| cdp2mcif_wr_req_pd | out | 515 | [514]=id 的 cmd/data 双变体（端口注释 `pkt_id_width=1 pkt_widths=78,514`，NV_NVDLA_CDP_wdma.v:51） |
| mcif2cdp_wr_rsp_complete | in | 1 | 写完成脉冲 |

## 3. 读通道

### 3.1 读请求 rd_req_pd[78:0]

打包处为明文 assign，上方留有 `PKT_PACK_WIRE( dma_read_cmd , dma_req_ , dma_rd_req_pd )`
注释（vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v:908-910）：

| 位域 | 字段 | 语义 |
|---|---|---|
| [63:0] | addr | 字节地址（cdp 要求 32B 对齐；[5]==0 判 64B 对齐，:835） |
| [78:64] | size | 传输长度，单位 32B（256-bit）块，**0-based**：实际块数 = size+1（ig 内 req_size 取值 0~7 即 1~8 块，:804-815；注释 "64.cnt = 64.size + 1"，:833） |

一笔请求即一次突发；cdp 每笔最多 8×32B=256B。请求被接受（valid&ready）即视为发射，
无请求级 ID——**同一客户端的读数据按请求序返回**。

### 3.2 读响应 rd_rsp_pd[513:0]

响应按 512-bit（64B）beat 返回，每 beat 一次握手：

| 位域 | 字段 | 语义 |
|---|---|---|
| [511:0] | data | 数据，一拍 64B |
| [513:512] | mask | 半拍有效标志：bit0=低 256-bit 有效，bit1=高 256-bit 有效。首/尾块非 64B 对齐或奇数块时出现 2'b01/2'b10（cdp 侧解包与按 mask 分流 :338-357，vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_eg.v） |

客户端可用 rd_rsp_ready 回压（cdp 把响应先落进本地 latency FIFO，写口 prdy 就是
rd_rsp_ready 的源头，eg.v:325-335）。

## 4. credit（latency FIFO 信用）机制

防死锁设计：mcif 在**发射读请求前**就确认客户端有地方收数据，避免 AXI 读数据无处安放
堵死总线。记账双方：

**客户端侧（cdp 样本）**——消费一拍响应就归还一个信用：

- 信用脉冲源头：`dma_rd_cdt_lat_fifo_pop = lat_rd_pvld & lat_rd_prdy`，即本地 latency FIFO
  被读出（消费）一拍（vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_eg.v:343）；
- 打一拍寄存后按目的地分发：`cdp2mcif_..._pop <= pop & (dma_rd_rsp_type==1'b1)`、
  `cdp2cvif_..._pop <= pop & (type==1'b0)`（eg.v:305-318）；
- `dma_rd_rsp_type = reg2dp_src_ram_type`（eg.v:320）：**1=MC（外部 DRAM），0=CV（SRAM）**。

**mcif 侧**——每客户端一个 bpt（backpressure tracker）记账（vmod/nvdla/nocif/NV_NVDLA_MCIF_READ_IG_bpt.v）：

- 每接受一笔请求，占用 `slot_needed` 个 512-bit 槽位（由 size 折算，≈(size+1)/2 向上取整，:219-226、:236）；
- 每收到一个 pop 脉冲，释放 1 个槽位（:233）；
- 剩余槽位不足本笔所需时**扣住请求不发**：`req_enable = slot_needed <= lat_fifo_free_slot`（:336-337）；
- 各客户端 latency FIFO 深度以 tieoff 参数告知 mcif：cdp=61（NV_NVDLA_MCIF_READ_ig.v:264，
  sdp=80 :238、pdp=61 :251、rbk=80 :277…）。

对 UT 的含义：**pop 是"客户端从自家 latency FIFO 消费了一拍"的事后通告，不是握手**；
从设备侧只需直通计数（发出的 beat 数 − 收到的 pop 数 ≤ 客户端 FIFO 深度），用于校验
客户端不多还、不少还。

## 5. 写通道

### 5.1 wr_req_pd[514:0]：cmd/data 双变体

一个通道复用命令与数据，按最高位 id 区分（打包 mux：vmod/nvdla/cdp/NV_NVDLA_CDP_wdma.v:1835-1851）：

| [514] id | 变体 | 位域 | 字段 |
|---|---|---|---|
| **0** | 命令 cmd | [63:0] | addr，字节地址（:1662） |
| | | [76:64] | size，单位 256-bit 块、0-based（:1663） |
| | | **[77]** | **require_ack**——本命令是否要求写完成应答（:1664）；cdp 只在整 cube 最后一笔置 1：`require_ack = is_cube_last`（:1659） |
| | | [513:78] | 补 0（:1842） |
| **1** | 数据 data | [511:0] | data（:1671） |
| | | [513:512] | mask，同读响应半拍语义；cdp 奇数 beat 收尾时给 2'b01（:1668、:1672） |

时序模式：先发 1 拍 cmd（id=0），随后连发该命令覆盖的所有 data beat（id=1），再发下一
个 cmd。`dma_wr_req_vld = cmd_vld | dat_vld`（:1835），同一 valid/ready 握手。

### 5.2 require_ack 与 wr_rsp_complete

- mcif/cvif 仅对 **require_ack=1** 的命令、在其全部数据真正写完（AXI B 通道返回）后，
  回一拍 wr_rsp_complete 脉冲（无握手）；
- require_ack=0 的命令静默完成——所以 complete 脉冲数 ≠ 命令数，UT 记分只能按
  require_ack=1 的命令数对账；
- cdp 用它做"整层数据落地"确认：eg 侧对 mc/cv 两路 complete 分别寄存并与 ack 队列
  顶端目的地比对（NV_NVDLA_CDP_wdma.v:2399-2449），配套断言要求"不该 pending 时不得
  出现 complete"（:2524、:2569）。

> 注意：任务常把 cmd 变体简写成 {addr,size}。**[77] require_ack 是协议的一部分**，
> 从设备（dma_slave_agent）必须解析它决定是否回 complete，否则客户端会永远等不到
> 层完成（cdp 的 done 依赖最后一笔的 ack）。

## 6. mcif / cvif 双目的地选路

客户端为 mc/cv 各出一套完整端口，按**寄存器配置的地址空间类型**静态选路（一层内不变）：

| 侧 | 选路信号 | 代码 |
|---|---|---|
| 读请求 | `dma_rd_req_ram_type = reg2dp_src_ram_type`；1→mcif、0→cvif 分发 valid/ready（NV_NVDLA_CDP_RDMA_ig.v:913、:1166-1169、:1196-1206） | |
| 读响应/信用 | `dma_rd_rsp_type = reg2dp_src_ram_type`（eg.v:320、:305-318）；两路响应 OR 合并进同一 latency FIFO，断言保证不同拍（"mcif and cvif should never return data both"，eg.v:255-257、:287） | |
| 写请求 | `dma_wr_req_type = reg2dp_dst_ram_type`（NV_NVDLA_CDP_wdma.v:2100、:2132-2142） | |
| 写完成 | mc/cv 两路 complete 分别进 ack 队列对账（wdma:2146-2149、:2399-2449） | |

即：ram_type **1 = MC（外部 DRAM，走 mcif），0 = CV（SRAM，走 cvif）**；读源与写目的
可以各自独立选（src_ram_type / dst_ram_type 是两个寄存器字段）。

## 7. UT 平台如何消费本协议：dma_slave_agent 规格

verif/ut/ 的 dma_slave_agent 做**反应式内存从设备**（reactive memory slave），一个参数化
类覆盖所有引擎与 mc/cv 两个目的地：

| 要素 | 规格 |
|---|---|
| 参数化 | `#(RD_REQ_W=79, RD_RSP_W=514, WR_REQ_W=515)`（cdp 默认值；地址恒 [63:0]，size 位宽 = RD_REQ_W-64） |
| 读行为 | 收 rd_req → 按 addr/size 从内部关联数组内存取数 → 按 3.2 拆成 512-bit beat 回注（首尾按对齐给 mask）；未初始化地址回确定性 pattern |
| 写行为 | 解析 [514] id：cmd 记 addr/size/require_ack，data 按 mask 写内存；require_ack=1 的命令在最后一 beat 后延迟 N 拍回 wr_rsp_complete 脉冲 |
| credit 直通计数 | 统计（已发响应 beat − 已收 pop），校验 0 ≤ 计数 ≤ 客户端 latency FIFO 深度（cdp=61，见 4 节）；阶段2 只计数告警，不建模 bpt 扣发 |
| 延迟/背压旋钮 | rd_rsp 首拍延迟、beat 间隔、req_ready 背压概率与拍数、complete 延迟，全部 cfg 可控（默认 0 延迟直通） |
| monitor | req/rsp/complete/pop 四类事件各出 analysis port，字段还原后交 scoreboard |

阶段2 只要求该 agent 编译通过、可实例化；阶段3 起挂到各 rdma/wdma 单元 UT 上做真正的
内存端。

## 8. 代码入口速查表

| 论断 | 位置 |
|---|---|
| 读请求打包 {size,addr}（PKT_PACK_WIRE 注释处） | vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v:908-910 |
| size 0-based、1~8 块 | 同上 :804-815、:833 |
| 读请求 mc/cv 分发 | 同上 :913、:1166-1169、:1196-1206 |
| 读响应 514 位端口 / 解包 / mask 分流 | vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_eg.v:220-233、:338-357 |
| mc/cv 响应 OR 合并 + 互斥断言 | 同上 :255-257、:287 |
| latency FIFO 与 rd_rsp_ready 源头 | 同上 :325-335 |
| **credit 脉冲源头与分发** | 同上 :343（源头）、:305-318（分发）、:320（type） |
| mcif 侧 bpt 记账（占用/释放/扣发） | vmod/nvdla/nocif/NV_NVDLA_MCIF_READ_IG_bpt.v:219-236、:233、:336-337 |
| 各客户端 latency FIFO 深度 tieoff（cdp=61） | vmod/nvdla/nocif/NV_NVDLA_MCIF_READ_ig.v:238-277 |
| 写通道 515 位端口（pkt_widths=78,514） | vmod/nvdla/cdp/NV_NVDLA_CDP_wdma.v:49-59 |
| cmd 字段（addr/size/**require_ack**） | 同上 :1656-1664（require_ack=is_cube_last :1659） |
| data 字段与 mask | 同上 :1666-1672 |
| **cmd/data 复用 mux 与 [514] id** | 同上 :1835-1851（id 赋值 :1850） |
| 写 mc/cv 选路与 complete 对账 | 同上 :2100、:2132-2149、:2399-2449 |

## 9. UT 测试点 checklist

- [ ] **读请求字段**：addr[63:0]/size[14:0] 还原正确；size+1 块数与随后响应 beat 数吻合。
- [ ] **读数据按序**：多笔未完成请求下，响应数据严格按请求序返回（协议无 ID）。
- [ ] **mask 语义**：非 64B 对齐首块 / 奇数块尾拍出现 2'b10/2'b01 时客户端取数正确（对 slave 是生成正确、对客户端 UT 是消费正确）。
- [ ] **响应背压**：rd_rsp_ready 压低时 slave 保持 valid/pd 稳定重握手。
- [ ] **credit 守恒**：整层结束后 pop 总数 == 响应 beat 总数；任意时刻在途 beat 数 ≤ 客户端 latency FIFO 深度（cdp=61）。
- [ ] **credit 目的地**：pop 只出现在与 ram_type 一致的一侧（mc/cv 不串）。
- [ ] **写序列合法性**：id=0 命令后跟满 size+1 块对应的 data beat，才允许下一命令；data 不得先于任何 cmd。
- [ ] **require_ack**：仅对 [77]=1 的命令回一拍 complete；complete 计数 == require_ack 命令计数。
- [ ] **写数据落地**：按 mask 写入的内存镜像与参考模型逐字节一致。
- [ ] **双目的地互斥**：同一层内请求只走 ram_type 指定的一侧；mc/cv 同拍回读数据触发 DUT 断言（+define+ASSERT_ON），UT 环境不得制造该场景。
