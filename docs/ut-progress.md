# RTL 学习与 UT 进度看板

本文记录阶段 2 涉及 RTL 的学习入口、UT 覆盖状态和下一步补强项。路线图见
`docs/learning-plan.md`，协议细节见 `docs/spec/`。

## 当前结论

| 项 | 状态 | 证据 |
|---|---|---|
| CSB 公共链路 spec | 基本完成 | `docs/spec/common/csb-link.md` 已覆盖 APB/csb2nvdla/csb_master/fanout/reg 终点行为 |
| DMA 客户端接口 spec | 基本完成 | `docs/spec/common/dma-if.md` 已覆盖 xx2mcif/xx2cvif 读写请求、响应、credit、ram_type |
| 阶段 2 RTL 注释 | 基本完成 | 最近提交补了 apb2csb、csb_master、CDP reg/RDMA/IG/EG 关键中文注释 |
| `csb_master` UT | 可回归 | `make regress` 已跑通 smoke + random x3 seeds |
| UT 复用层 | 可作为阶段 3 起点 | CSB master 面、fanout reactive 面、DMA slave 骨架、intr monitor 骨架已存在 |
| DMA slave agent | 骨架完成，功能未完整 | 目前能编译/实例化；完整 mask、写 burst、credit 深度约束还未实现 |
| 单元级 spec | 未开始 | `docs/spec/units/` 仍只有 `.gitkeep` |

## 本轮实测

目录：`verif/ut/csb_master`

命令：

```bash
make regress
```

结果：

| 测试 | seed | 结果 | 覆盖摘要 |
|---|---:|---|---|
| `csb_master_smoke_test` | 1 | PASS | 75 笔 master 请求；17 路 fanout 每路 3 笔；dummy 24 笔 |
| `csb_master_random_test` | 1 | PASS | 300 笔随机；dummy 220 笔；17 路 fanout 均命中 |
| `csb_master_random_test` | 2 | PASS | 300 笔随机；dummy 222 笔；17 路 fanout 均命中 |
| `csb_master_random_test` | 3 | PASS | 300 笔随机；dummy 225 笔；17 路 fanout 均命中 |

`common.mk` 的 PASS 判定同时检查 `UVM_FATAL==0`、`UVM_ERROR==0`、无 DUT 内建
`^ERROR :` 行，并要求日志出现 `UT RESULT: PASSED`。

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
- latency FIFO 的 credit pop 是客户端告诉 nocif 响应位被释放，UT 不能只看数据正确。

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

1. 给 `csb_fanout_if` 或 monitor 增加 valid && !ready 时 `req_pd` 稳定性检查。
2. 给 `csb_fanout_responder` 加可配置 `resp_error_pct`，新增 `csb_master_error_invisible_test`。
3. 把 `docs/spec/common/csb-link.md` checklist 中已覆盖项改成已核销，并链接本文件。
4. 进入阶段 3 前，先写 `docs/spec/units/cdp.md` 或 `docs/spec/units/cdma.md` 的第一版。
5. 扩展 `csb_fanout_agent` 为 active master 面，用来直接驱单元 reg 口。
6. 将 `dma_slave_responder` 从骨架升级到可查错模型：完整 size 计数、mask、写 burst、credit 深度约束。

建议先选 CDP 作为阶段 3 的过渡对象：它已经有阶段 2 注释和 DMA spec 入口，复杂度低于
CDMA+CBUF，但能同时练到 CSB reg、RDMA 和中断。
