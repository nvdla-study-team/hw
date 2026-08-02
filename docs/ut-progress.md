# RTL 学习与 UT 进度看板

本文记录涉及 RTL 的学习入口、UT 覆盖状态和下一步补强项。路线图见
`docs/learning-plan.md`，协议细节见 `docs/spec/`。

## 当前结论

| 项 | 状态 | 证据 |
|---|---|---|
| CSB 公共链路 spec | 基本完成 | `docs/spec/common/csb-link.md` 已覆盖 APB/csb2nvdla/csb_master/fanout/reg 终点行为 |
| DMA 客户端接口 spec | 基本完成（含两条勘误） | `docs/spec/common/dma-if.md`；阶段3.1 补：cdma 4 路无 credit 勘误（4 节）、mask 仅 2'b11/2'b01 勘误（3.2 节） |
| 阶段 2 RTL 注释 | 完成 | apb2csb、csb_master、CDP reg/RDMA/IG/EG 关键中文注释 |
| 阶段 3.1 RTL 注释 | 进行中 | Wave 1：cdma 顶层/regfile/status/dma_mux + cbuf 5 文件；Wave 2（进行中）：dc/wt/cvt/shared_buffer |
| `csb_master` UT | 可回归 | `make regress` smoke + random x3 seeds 全绿 |
| **cdma_cbuf UT** | 骨架完成，T0 绿 | `verif/ut/cdma_cbuf/`；T0 寄存器面冒烟已回归（复位值/mask 化写读/producer 影子/全偏移扫描/prdy 恒 1/flush_done 轮询） |
| 单元级 spec | cdma-cbuf 草稿完成 | `docs/spec/units/cdma-cbuf.md`（接口/寄存器/机制/checklist 初版 + 7 项 refmodel 依据） |
| DMA slave agent | 功能增强中 | 新增未初始化 pattern `default_byte()`（可复算哈希）；mask 生成收窄为 2'b11/2'b01 |

## 阶段 3.1 Wave 1 小结（2026-08-01）

三线产出：

- **DOC**：`docs/spec/units/cdma-cbuf.md` 草稿（四要素前三项 + 机制章 + §6 checklist
  初版）；`docs/spec/common/dma-if.md` 两条勘误（cdma 无 credit、mask 紧凑语义）。
- **DE**：5 个 vmod 文件中文注释（NV_NVDLA_cdma.v、CDMA_regfile.v、CDMA_status.v、
  CDMA_dma_mux.v、NV_NVDLA_cbuf.v），纯注释改动；Wave 2 续注 dc/wt/cvt/shared_buffer。
- **DV**：`verif/ut/cdma_cbuf/` UT 骨架 + T0 寄存器面全绿；新公共组件
  `verif/ut/common/cbuf/`（cbuf 行为镜像/读 BFM）、`verif/ut/common/cdma_sc/`
  （cdma2sc/sc2cdma 状态-信用面 agent）；`dma_slave_responder` 增强
  （default_byte pattern、mask 合法化）。

本轮实证发现（均已写入对应 spec，含 file:line）：

| 发现 | 归档位置 |
|---|---|
| 读响应 mask 只有 2'b11/2'b01，2'b10 永不出现；首块恒落首拍低 256b（swizzle 在重排 FIFO 前完成） | dma-if.md 3.2 勘误；cdma-cbuf.md 2.2 |
| cdma 4 路读客户端无 credit/pop（bpt tieoff depth=0 关闭扣发） | dma-if.md 4 节勘误；cdma-cbuf.md 2.2 |
| dma_mux 是选择器不是仲裁器（valid OR + 层级互斥前提 + zero_one_hot 兜底） | cdma-cbuf.md 4.1 |
| cdma2sc_dat_updt 相对写入落地延迟 9 拍 | cdma-cbuf.md 2.5/4.5 |
| S_STATUS 编码 1=running（consumer 指向本组）/2=pending——某并发注释曾写反，已纠 | cdma-cbuf.md 3.1 |
| 复位 flush：dat 4096 拍写 bank0-7、wt 4096 拍写 bank8-15，全 0、与 D_BANK 无关 | cdma-cbuf.md 4.4 |
| D_ENTRY_PER_SLICE/D_FETCH_GRAIN 均 0-based；line_packed=0 时 fetch_grain 恒 1（忽略寄存器） | cdma-cbuf.md 3.4/4.5 |
| spec/manual/ 无 CDMA 寄存器定义（仅 Ordt 演示），权威在 arreggen 生成的 reg RTL | cdma-cbuf.md 3.5 |
| cbuf.v wmb 读写 hazard 断言疑似笔误（比较对象/位宽错） | cdma-cbuf.md 4.4 |

## 本轮实测

目录：`verif/ut/csb_master`（阶段 2）、`verif/ut/cdma_cbuf`（阶段 3.1 T0）

阶段 2 基线（`make regress`）：

| 测试 | seed | 结果 | 覆盖摘要 |
|---|---:|---|---|
| `csb_master_smoke_test` | 1 | PASS | 75 笔 master 请求；17 路 fanout 每路 3 笔；dummy 24 笔 |
| `csb_master_random_test` | 1 | PASS | 300 笔随机；dummy 220 笔；17 路 fanout 均命中 |
| `csb_master_random_test` | 2 | PASS | 300 笔随机；dummy 222 笔；17 路 fanout 均命中 |
| `csb_master_random_test` | 3 | PASS | 300 笔随机；dummy 225 笔；17 路 fanout 均命中 |

`common.mk` 的 PASS 判定同时检查 `UVM_FATAL==0`、`UVM_ERROR==0`、无 DUT 内建
`^ERROR :` 行，并要求日志出现 `UT RESULT: PASSED`。

阶段 3.1 T0：cdma_cbuf 寄存器面冒烟绿（核销项见
`docs/spec/units/cdma-cbuf.md` §6.1）；T1-T6 排期见同文 §6 测试映射。

## RTL 学习入口

### 1. CSB 链路

先按请求路径读：

1. `vmod/nvdla/apb2csb/NV_NVDLA_apb2csb.v`
   - 看 APB 到 csb2nvdla 的地址翻译、posted/nposted 约定、pready 行为。
2. `vmod/nvdla/csb_master/NV_NVDLA_csb_master.v`
   - 看 falcon/core CDC FIFO、17 路地址译码、dummy 行为、响应 OR-mux。
3. `vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_falcon2csb_fifo.v`
   - 看 falcon 到 core 的异步 FIFO 和 3 级同步器。
4. `vmod/nvdla/csb_master/NV_NVDLA_CSB_MASTER_csb2falcon_fifo.v`
   - 看 core 到 falcon 的响应 FIFO。
5. 任一单元 reg 终点，例如 `vmod/nvdla/cdp/NV_NVDLA_CDP_reg.v`
   - 看 `csb2cdp_req_pd` 解包、single/dual 寄存器、producer/consumer ping-pong。

重点问题：

- `csb_master` 只保证同一目的地口内顺序；跨目的地口可能乱序完成。
- 17 路 fanout 出口只有一级保持寄存器；同口 posted 写在长期背压下需要激励侧规避覆盖风险。
- dummy 地址不进任何真实 fanout；读回 0，nposted 写回 complete，posted 写静默。

### 2. DMA 客户端接口

建议从 CDP RDMA 读起，因为它的读请求、响应、latency FIFO、ram_type 选路相对集中：

1. `vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v`
   - 看读请求 `{size, addr}` 打包和 mcif/cvif 选路。
2. `vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_eg.v`
   - 看读响应 mask、credit pop、mc/cv 响应互斥。
3. 后续到写通道时再读 `vmod/nvdla/cdp/NV_NVDLA_CDP_wdma.v`
   - 看写 cmd/data 复用、`require_ack`、complete 对账。

重点问题：

- 读请求无 ID，slave 必须按请求顺序返回响应。
- `ram_type` 约定是 `1=MCIF`、`0=CVIF`。
- latency FIFO 的 credit pop 是客户端告诉 nocif 响应位被释放——**但 cdma 4 路例外
  （无 pop，见 dma-if.md 4 节勘误）**。

### 3. CDMA + CBUF（阶段 3.1）

按 `docs/spec/units/cdma-cbuf.md` 章节顺序读：

1. `vmod/nvdla/cdma/NV_NVDLA_cdma.v`（顶层接线与 9 实例）→ spec §2/§5
2. `NV_NVDLA_CDMA_regfile.v` + single/dual_reg（乒乓与 0x010 分界）→ §3
3. `NV_NVDLA_CDMA_dc.v`（取数状态机、entry 组装、updt 公式）→ §4.4/§4.5
4. `NV_NVDLA_CDMA_status.v`（记账/切层/中断）→ §4.5
5. `vmod/nvdla/cbuf/NV_NVDLA_cbuf.v`（bank 阵列与断言合同）→ §4.4

## CSB UT 覆盖核销

| `csb-link.md` 测试点 | 当前状态 | 说明 |
|---|---|---|
| 路由 | 覆盖 | smoke 逐路命中，random 也覆盖 17 路；scoreboard 按 `csb_target_of()` 独立预测 |
| `req_pd` 字段还原 | 覆盖 | scoreboard 校验 addr/wdat/write/nposted 与保留位 |
| 读响应 | 覆盖 | fanout responder 回读，scoreboard 和 smoke seq 双重比对 |
| nposted 写 | 覆盖 | fanout type=1，master 侧 `wr_complete` |
| posted 写 | 覆盖 | scoreboard 对 unexpected master response 报错 |
| dummy 读 | 覆盖 | `csb_dummy_seq` 覆盖，scoreboard 期望 0 |
| dummy nposted/posted 写 | 覆盖 | `csb_dummy_seq` 覆盖 complete/静默行为 |
| 响应 type 位 | 覆盖 | scoreboard 校验读 type=0、写完成 type=1 |
| 背压重握手 | 部分覆盖 | random 配置 `rdy_gap_pct=30`、gap 1..8；缺少显式 valid/pd stable assertion |
| 串行化约束下压力 | 覆盖 | driver 对读/nposted 串行化，posted 写可穿插；regress 启用 `ASSERT_ON` 检查无 DUT ERROR |
| error 位不可见 | 未覆盖 | responder 当前固定 `error=0`，还没有 error 注入测试 |

## 下一步补强顺序

1. ~~cdma_cbuf T1 主冒烟 → T2-T6~~ **已完成（2026-08-01）**：回归 8/8 绿
   （T0/T1/T2/T3×3/T5/T6），spec §6 checklist 44 条核销 32 条；T4 压缩权重待做。
2. ~~refmodel 与 spec 互证~~ **已完成（2026-08-01）**：DOC spec 与 DV refmodel
   独立推导比对一致（entry 三形态打包/权重线性布局/记账增量+9 拍）。两条 RTL
   发现记录在 cdma-cbuf.md：wt 响应消费无 FIFO 头门控（隐性 ≥6 拍契约，波形
   实证，§4.6）、cbuf wmb hazard 断言比错地址（§4.4）。
3. 负面断言激励小测集（cdma-cbuf.md §6.6，+define+ASSERT_ON）。
4. 给 `csb_fanout_responder` 加 `resp_error_pct`，补 csb error 位不可见测试。
5. dma_slave_responder 按 mask 勘误收窄生成路径的回归（不再产生 2'b10）。
6. 阶段 3.2 前写 `docs/spec/units/csc.md` 第一版（sc2buf 消费侧 + sc2mac）。
