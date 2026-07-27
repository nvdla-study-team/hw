# CSB 链路协议（CSB Link）

CSB（Configuration Space Bus）是 NVDLA 唯一的配置总线：主机对 NVDLA 所有寄存器的读写都走
这一条链路。本文自外向内描述整条链路的每一跳协议，并给出 UT 平台的消费方式。

> 事实来源：vmod/ 源码实读（2026-07，nv_full 配置）。行号以当前 `developer` 分支为准。

## 1. 链路全景

```
外部主机 (APB)                    falcon 时钟域            |          core 时钟域
                                                          | (CDC)
 APB ──► NV_NVDLA_apb2csb ──► csb2nvdla 单口 ──► NV_NVDLA_csb_master ──► 17 路 csb2xx ──► 各单元 NV_NVDLA_<UNIT>_reg
          (协议翻译)           (valid/ready)      (异步FIFO + 地址译码       (req_pd[62:0] /      (寄存器终点)
                                                   + 响应OR汇聚 + dummy)     resp_pd[33:0])
```

| 跳 | 模块 | 代码 |
|---|---|---|
| APB → CSB 单口 | NV_NVDLA_apb2csb（可选外壳，103 行） | vmod/nvdla/apb2csb/NV_NVDLA_apb2csb.v |
| CSB 单口（falcon 域）→ 17 路（core 域） | NV_NVDLA_csb_master | vmod/nvdla/csb_master/NV_NVDLA_csb_master.v |
| 请求方向 CDC FIFO | NV_NVDLA_CSB_MASTER_falcon2csb_fifo | vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_falcon2csb_fifo.v |
| 响应方向 CDC FIFO | NV_NVDLA_CSB_MASTER_csb2falcon_fifo | vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_csb2falcon_fifo.v |
| 单元侧终点（两形态样本） | NV_NVDLA_CDP_reg / NV_NVDLA_BDMA_reg | vmod/nvdla/cdp/NV_NVDLA_CDP_reg.v、vmod/nvdla/bdma/NV_NVDLA_BDMA_reg.v |

csb2nvdla 单口就是 NVDLA 顶层的对外配置口（vmod/nvdla/top/NV_nvdla.v:24-32、:102-112）；
apb2csb 是挂在它前面的独立翻译壳，集成时可用可不用。

## 2. apb2csb：APB → CSB 翻译规则

文件仅 103 行，规则全部是明文 assign（vmod/nvdla/apb2csb/NV_NVDLA_apb2csb.v）：

| 规则 | 内容 | 代码行 |
|---|---|---|
| 地址翻译 | `csb2nvdla_addr = paddr[17:2]`——APB 字节地址取 [17:2] 变 16 位**字地址**（4B 粒度） | :93 |
| 写数据 | `csb2nvdla_wdat = pwdata[31:0]` | :94 |
| 读写方向 | `csb2nvdla_write = pwrite` | :95 |
| **恒 posted** | `csb2nvdla_nposted = 1'b0`——经 APB 进来的写永远是 posted 写，不会产生 wr_complete 响应 | :96 |
| valid 生成 | 写：`psel & penable & pwrite` 直通；读：同上取反 pwrite，且用 `rd_trans_low` 标志压掉重复发射（读已被接受、尚未回数据期间不再发 valid） | :78-79、:81-90、:92 |
| pready 生成 | `pready = ~(写未被 ready \| 读未回 valid)`——写等 csb2nvdla_ready，读等 nvdla2csb_valid 才结束 APB 传输 | :100 |
| 读数据 | `prdata = nvdla2csb_data` 直通 | :98 |

注意：apb2csb **不接** nvdla2csb_wr_complete（端口注释掉了，:55），与"恒 posted"自洽。

## 3. csb2nvdla 单口协议（falcon 域）

### 3.1 信号表

方向以 NVDLA（csb_master）为参照。端口声明见 vmod/nvdla/csb_master/NV_NVDLA_csb_master.v:117-135。

| 信号 | 方向 | 位宽 | 语义 |
|---|---|---|---|
| csb2nvdla_valid | in | 1 | 请求有效 |
| csb2nvdla_ready | out | 1 | 请求接受（valid/ready 握手，同拍成交） |
| csb2nvdla_addr | in | 16 | **字地址**（4B 粒度），覆盖 256KB 字节空间 |
| csb2nvdla_wdat | in | 32 | 写数据 |
| csb2nvdla_write | in | 1 | 1=写，0=读 |
| csb2nvdla_nposted | in | 1 | 1=非缓写（non-posted write），0=缓写（posted write）；读事务下无意义 |
| nvdla2csb_valid | out | 1 | 读响应有效（单拍脉冲） |
| nvdla2csb_data | out | 32 | 读数据（保持到下一次读响应，:546-555） |
| nvdla2csb_wr_complete | out | 1 | nposted 写完成（单拍脉冲，:565-571） |

### 3.2 事务语义

| 事务 | 响应 |
|---|---|
| 读（write=0） | 必回一拍 nvdla2csb_valid + nvdla2csb_data |
| nposted 写（write=1, nposted=1） | 必回一拍 nvdla2csb_wr_complete |
| posted 写（write=1, nposted=0） | **无任何响应** |

响应侧没有 ready——nvdla2csb_valid / wr_complete 是不可回压的脉冲，主机必须当拍采样。
响应通路上也没有错误信号出口：resp_pd 的 error 位在 falcon 侧被丢弃（见 6.2 节）。

## 4. csb_master 内部：CDC 结构与串行化约束

### 4.1 双时钟域与异步 FIFO

csb_master 跨 falcon（配置口）与 core（NVDLA 主体）两个异步时钟域，两个方向各一个异步 FIFO：

| 方向 | 实例 | 深度×宽度 | 同步器 | 代码 |
|---|---|---|---|---|
| 请求：falcon → core | u_fifo_csb2nvdla（falcon2csb_fifo） | 4×50（flopram_rwa_4x50，写指针 2 位） | p_STRICTSYNC3DOTM_C_PPP 3 级同步器 | 实例化 NV_NVDLA_csb_master.v:454-466；深度见 …falcon2csb_fifo.v:193、:221；同步器 :330-352、:403-425 |
| 响应：core → falcon | u_fifo_nvdla2csb（csb2falcon_fifo） | 2×34（flopram_rwa_2x34，写指针 1 位） | 同上 3 级 | 实例化 :470-482；深度见 …csb2falcon_fifo.v:167、:195；同步器 :304-315、:366-377 |

进入请求 FIFO 前，falcon 侧先把单口信号打成 50 位包：
`csb2nvdla_pd[49:0] = {nposted, write, wdat[31:0], addr[15:0]}`（NV_NVDLA_csb_master.v:452）。

FIFO core 侧读口 `core_req_prdy = 1'b1`（:468）——请求一到 core 域即无条件弹出，随后进各
目的地口的保持寄存器（见 7 节）。响应 FIFO 的 falcon 侧读口同样 `rd_ready=1'b1`（:478），
且 core 侧写口若被写满会触发断言 "Error! core response fifo block!"（:519）。

每跳 3 级同步器 + 各级寄存，一次读事务端到端（csb2nvdla_valid 进 → nvdla2csb_valid 出）
约 **10~20 拍**（视两域频率比，实测量级，非精确保证）。

### 4.2 为什么"带响应事务必须串行化"

响应汇聚是 **OR-mux、无仲裁**（见 9 节）：若两路目的地同拍回响应，34 位 pd 会按位或成
垃圾值。RTL 只有一条 `nv_assert_zero_one_hot` 断言兜底（:2303，报 "Error! Multiple
response!"），**没有任何硬件排队/仲裁**。加上响应 FIFO 仅 2 深、写满即断言（:519），
结论：**主机（以及 UT 的 driver）对读和 nposted 写必须发一笔、等一笔响应，不得流水；
只有 posted 写可以背靠背**。真实系统里 falcon 固件天然如此使用，硬件因此不设防。

## 5. 地址译码与 17 路映射

core 域把字地址还原成字节地址再译码：

- 还原：`core_byte_addr = {core_req_addr[15:0], 2'b0}`，18 位（NV_NVDLA_csb_master.v:608）；
- 掩码：`addr_mask = {6{1'b1}, 12{1'b0}} = 18'h3F000`（:621），即**取 byte_addr[17:12]，
  每个目的地一个 4KB 页**；
- 比较式样板：`select_cmac_a = ((core_byte_addr & addr_mask) == 32'h00007000)`（:642），
  其余 16 路同构；
- 全部不命中 → `select_dummy = ~(所有 select 之或)`（:1763-1780）。

17 路映射（nv_full 恒有；afbif 恒关：`select_afbif = 1'b0`，:625，其响应口也拴死
`afbif_resp_pvld = 1'b0`，:2371-2372）：

| 字节基址 | 字地址（csb2nvdla_addr） | 目的地 | | 字节基址 | 字地址 | 目的地 |
|---|---|---|---|---|---|---|
| 0x0_0000 | 0x0000 | glb | | 0x0_9000 | 0x2400 | cacc |
| 0x0_1000 | 0x0400 | gec | | 0x0_A000 | 0x2800 | sdp_rdma |
| 0x0_2000 | 0x0800 | mcif | | 0x0_B000 | 0x2C00 | sdp |
| 0x0_3000 | 0x0C00 | cvif | | 0x0_C000 | 0x3000 | pdp_rdma |
| 0x0_4000 | 0x1000 | bdma | | 0x0_D000 | 0x3400 | pdp |
| 0x0_5000 | 0x1400 | cdma | | 0x0_E000 | 0x3800 | cdp_rdma |
| 0x0_6000 | 0x1800 | csc | | 0x0_F000 | 0x3C00 | cdp |
| 0x0_7000 | 0x1C00 | cmac_a | | 0x1_0000 | 0x4000 | rbk |
| 0x0_8000 | 0x2000 | cmac_b | | ≥0x1_1000 | ≥0x4400 | **dummy**（内部承接，见 8 节） |

17 个页连续覆盖 0x0_0000~0x1_0FFF；字节地址 0x1_1000~0x3_FFFF（即字地址 ≥ 0x4400）
全部落 dummy。

## 6. pd 字段图

### 6.1 req_pd[62:0]（17 路 csb2xx 共用）

50 位内部包扩展成 63 位对外包：
`csb2xx_req_pd = {7'h0, tmp[49:16], 6'h0, tmp[15:0]}`（样板 NV_NVDLA_csb_master.v:700）。

| 位域 | 字段 | 语义 |
|---|---|---|
| [15:0] | addr | 字地址（目的地内按低 12 位字节偏移译码，见 10 节） |
| [21:16] | 保留 | 恒 0（预留 wrbe 等，未用） |
| [53:22] | wdat | 写数据 |
| [54] | write | 1=写 0=读（unpack 参考 :596-598：内部包 [48]=write、[49]=nposted） |
| [55] | nposted | 非缓写标志 |
| [62:56] | 保留 | 恒 0（预留 srcpriv/level 等，&Forget dangle 注释见 :592-595） |

### 6.2 resp_pd[33:0]（17 路 xx2csb 共用）

字段定义可从 dummy 侧打包与 falcon 侧解包互证（:1823-1833、:486-488）：

| 位域 | 字段 | 语义 |
|---|---|---|
| [31:0] | rdat | 读数据（写完成响应时无意义） |
| [32] | error | 错误标志——**falcon 侧无出口**：解包只用 [31:0] 和 [33]（:486-488），error 出口逻辑整段被注释（:557-564、:572-586），外部完全不可见 |
| [33] | type | 0=读响应（回 nvdla2csb_valid+data），1=写完成（回 nvdla2csb_wr_complete）（:487-488、:538-571） |

## 7. 目的地口 csb2xx 协议（core 域）与背压重握手

每路 csb2xx 是标准 valid/ready + 63 位 pd。因请求 FIFO 读口无条件弹出（:468），每路
出口有一级保持逻辑（以 cmac_a 为样板，其余 16 路同构）：

- 命中时置内部 pvld，目的地 ready 或空闲时清除（:652-655、:657-665）；
- pd 保持寄存器仅在出口空闲/正在成交时装载（`csb2xx_req_en`，:667-673、:690-699）——
  **valid 挂起期间 pd 保持稳定**，被目的地背压时 valid 持续拉高直到 ready，为标准重握手。

注意：保持深度只有 1 级。若目的地长时间不 ready、而主机又违反 4.2 节串行化约束继续
发往该路，后续请求会覆盖前一笔——这是"posted 写也不能无限背靠背怼一个背压目的地"的
根据（正常使用中单元 reg 终点从不背压，见 10 节）。

响应方向每路是"无 ready 的单拍 valid+pd"：xx2csb_resp_valid 打一拍寄存后进 OR 汇聚
（样板 :1908-1927）。

## 8. dummy 目的地实际行为

> **勘误（重要，团队旧认知常错）**：dummy 对任何访问**都不回 error**。
> `dummy_resp_error = 1'b0` 恒零、`dummy_resp_rdat = 32'h0` 恒零——见
> vmod/nvdla/csb_master/NV_NVDLA_csb_master.v:1834-1835（vmod 源码明文；生成产物
> outdir/nv_full/vmod/nvdla/csb_master/NV_NVDLA_csb_master.v:1647-1648 同文，已双向核对）。
> resp_pd 的 error 位本来在 falcon 侧就没有出口（6.2 节），所以"访问了不存在的地址"
> 对主机完全静默，只是读回 0。

dummy 实际行为（:1787-1857）：

| 访问 | dummy 行为 | 依据 |
|---|---|---|
| 读 | 下一拍回读响应，data=32'h0 | valid 条件 `pvld & (nposted \| read)`（:1837）、type=0（:1838）、rdat=0（:1834） |
| nposted 写 | 下一拍回 wr_complete | 同上，type=`~read & nposted`=1（:1838） |
| posted 写 | **无响应**，静默丢弃 | `nposted=0 且 read=0` 不满足 :1837 |

## 9. 响应汇聚：OR-mux，无仲裁

`core_resp_pd = (mask&pd_glb) | (mask&pd_gec) | … | (mask&pd_dummy)`，共 18 路（17 目的地
+ dummy；afbif 拴 0）按位或（NV_NVDLA_csb_master.v:2234-2252）；`core_resp_pvld` 为 19 项
valid 之或（:2254-2272）。多路同拍响应 → pd 混叠成垃圾，仅有仿真断言
`nv_assert_zero_one_hot #(0,19,0,"Error! Multiple response!")` 兜底（:2303，需 +define+ASSERT_ON）。
串行化含义见 4.2 节。

## 10. 单元侧 reg 终点：两种形态

csb2xx 到达单元后由 NV_NVDLA_<UNIT>_reg 终结。全 17 路共两种形态；单元内译码只看
addr 低 12 位字节偏移（每单元一个 4KB 页）。

### 10.1 CDP：ping-pong 型（乒乓寄存器组，带 producer/consumer 指针）

代表带双缓冲配置的运算引擎（cdma/csc/cacc/sdp/pdp/cdp 及各 rdma 同型）。
文件 vmod/nvdla/cdp/NV_NVDLA_CDP_reg.v，内部例化三个组：

| 组 | 实例 | 偏移范围 | 内容 |
|---|---|---|---|
| single | NV_NVDLA_CDP_REG_single（:307-347） | 字节偏移 < 0x048 | 共享寄存器：S_STATUS、S_POINTER（producer/consumer 指针）、LUT 访问口 |
| dual d0 | NV_NVDLA_CDP_REG_dual（:351-389） | 偏移 ≥ 0x048 | 第 0 组层参数（乒） |
| dual d1 | NV_NVDLA_CDP_REG_dual（:391-429） | 偏移 ≥ 0x048 | 第 1 组层参数（乓） |

关键机制（全部有明文代码）：

- **0x048 分界**：`select_s = offset[11:0] < 0x048`；`select_d0/d1 = offset ≥ 0x048 &
  producer==0/1`（:622-624）。
- **producer 指针决定 CSB 访问落哪组**：偏移 ≥0x048 的写与读都按软件写入的 producer
  指针选 d0/d1（写 :626-628，读 :638-640）。正在执行的组写保护：`d0_reg_wr_en = … &
  ~reg2dp_d0_op_en`（:627-628），op_en 挂起期间该组配置只读。
- **consumer 指针决定数据通路用哪组**：所有 reg2dp_* 层参数按 consumer 从 d0/d1 二选一
  （op_en :570，各参数 :878-1026），中断编号也用它（`reg2dp_interrupt_ptr = dp2reg_consumer`，:1035）。
- **consumer 在 dp2reg_done 时翻转**：`dp2reg_consumer <= ~dp2reg_consumer`，条件
  `dp2reg_done`（:436-449）；同时 done 按 consumer 清对应组 op_en（d0 :534-536，d1 :553-555）。
- **状态外读**：S_STATUS 两个 2 位字段由 op_en+consumer 组合出 idle/pending/running
  （:504-520）。

软件视角的乒乓流程：配 producer 指的组 → 写该组 D_OP_ENABLE → 翻 producer → 配另一组；
硬件按 consumer 顺序消费，每层 done 自动翻 consumer 并清本组 op_en。

### 10.2 BDMA：扁平型（单组，直接译码，无乒乓）

文件 vmod/nvdla/bdma/NV_NVDLA_BDMA_reg.v：每个寄存器一条独立 wren 比较
（`(reg_offset_wr == (32'h4014 & 32'hfff)) & reg_wr_en` 之类，:148-168），读走一个
`case (reg_offset_rd_int)`（:223-288），写侧再一个 case（:435-476），未知偏移仅在仿真
`$display` 告警。无 producer/consumer、无 dual 组。glb/mcif/cvif/gec/rbk 等同为扁平型。

两形态对 CSB 链路的共同点：**reg 终点从不背压**（csb2xx_req_prdy 恒 1），读写当拍完成、
下一拍回响应；差别只在单元内的地址译码与分组语义。

## 11. UT 平台如何消费本协议

verif/ut/ 的 csb_agent 按本协议做成**一个 agent、两个工作面**：

| 工作面 | 面向接口 | 时钟域 | 阶段2 角色 | 阶段3 扩展 |
|---|---|---|---|---|
| 单口 master 面 | csb2nvdla / nvdla2csb（3.1 节信号表） | falcon | driver + monitor：发读/写事务，**读与 nposted 写串行化**（发一笔等一笔响应，依据 4.2 节），posted 写可流水；响应超时报错 | 不变 |
| 扇出面 ×17 | csb2xx req/resp（6 节 pd 格式） | core | responder + monitor：按 5 节映射各占一路，校验路由与 pd 字段还原，回注 resp_pd（type/rdat/error 可控），req_prdy 背压可控（7 节重握手） | 加 driver 面，直接对单元 UT 的 reg 口发配置，复用同一 seq_item |

scoreboard 对照点：单口事务 ↔ 命中路的 req_pd 逐字段还原（含保留位恒 0）↔ 该路 resp ↔
单口响应；dummy 地址按 8 节预期（读 0 / wr_complete / 静默），且**不得**出现在任何扇出口。

## 12. 代码入口速查表

| 论断 | 位置 |
|---|---|
| APB 地址翻译 / 恒 posted / pready | vmod/nvdla/apb2csb/NV_NVDLA_apb2csb.v:93 / :96 / :100 |
| 顶层单口端口 | vmod/nvdla/top/NV_nvdla.v:24-32、:1208-1209、:1308 |
| falcon 侧 50 位打包 | vmod/nvdla/csb_master/NV_NVDLA_csb_master.v:452 |
| 请求 FIFO（4 深）/ 响应 FIFO（2 深） | 同上 :454-466 / :470-482；深度证据 …falcon2csb_fifo.v:193,:221、…csb2falcon_fifo.v:167,:195 |
| 3 级同步器 | …falcon2csb_fifo.v:330-352、…csb2falcon_fifo.v:304-315（p_STRICTSYNC3DOTM_C_PPP） |
| core 侧无条件弹出 / 响应 FIFO 满断言 | NV_NVDLA_csb_master.v:468 / :519 |
| 字→字节地址、掩码 18'h3F000、译码样板 | :608、:621、:642 |
| 出口保持/重握手样板（cmac_a） | :652-673、:690-700 |
| req_pd 63 位展开样板 | :700 |
| falcon 侧响应解包（type 判别、error 丢弃） | :486-488、:538-571、:557-564（注释块） |
| select_dummy / dummy 行为 / **error 恒 0** | :1763-1780 / :1787-1857 / :1834-1835（outdir 生成文件同文 :1647-1648） |
| 响应 OR-mux / zero_one_hot 断言 | :2234-2272 / :2303 |
| afbif 恒关 | :625、:2371-2372 |
| CDP 0x048 分界与 producer 选组 | vmod/nvdla/cdp/NV_NVDLA_CDP_reg.v:622-628、:638-640 |
| CDP consumer 翻转（dp2reg_done） | 同上 :436-449；op_en 清除 :534-536、:553-555 |
| CDP 数据通路按 consumer 取参 | 同上 :570、:878-1026、:1035 |
| BDMA 扁平译码 | vmod/nvdla/bdma/NV_NVDLA_BDMA_reg.v:148-168、:223-288、:435-476 |

## 13. UT 测试点 checklist

- [ ] **路由**：17 个 4KB 页各取若干偏移（页首/页尾/中间），请求只出现在对应一路扇出口。
- [ ] **req_pd 字段还原**：addr/wdat/write/nposted 逐字段与单口事务一致；[21:16]、[62:56] 保留位恒 0。
- [ ] **读响应**：responder 回注的 rdat 原值回到 nvdla2csb_data，且 nvdla2csb_valid 单拍。
- [ ] **nposted 写**：回 nvdla2csb_wr_complete 单拍，不出现 nvdla2csb_valid。
- [ ] **posted 写**：请求到达扇出口，单口侧无任何响应。
- [ ] **dummy 读**：word addr ≥ 0x4400 读回 data==32'h0（不是 error），任何扇出口无请求。
- [ ] **dummy nposted 写**：回 wr_complete；**dummy posted 写**：静默无响应。
- [ ] **响应 type 位**：读响应 type==0、写完成 type==1（monitor 在扇出面直接校验 resp_pd[33]）。
- [ ] **背压重握手**：扇出口 req_prdy 随机压低 1~8 拍，valid 保持、pd 稳定、不丢不重。
- [ ] **串行化约束下的压力**：读/nposted 写严格一发一收，posted 写背靠背穿插，全程无 zero_one_hot 断言（+define+ASSERT_ON 下跑）。
- [ ] **error 位不可见**：responder 回 error=1 的响应，单口侧行为与 error=0 完全一致（数据照常）。
