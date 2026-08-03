# NVDLA v1 学习与验证路线图

> 原则：先总后分；每阶段有出口条件；子模块按**数据流顺序**学（数据怎么走就怎么学）。
> **只学 RTL，不学上游验证平台/脚本**；UT 与 ST 全部自建（UVM），上游 verif/ 目录只作数据来源与波形观察工具。
> 每个模块（阶段 3 起）走固定循环：梳理 spec（docs/spec/units/<unit>.md）→ 对照 spec 读代码 → 搭 UT（verif/ut/<unit>/）→ 测试点核销。

## 阶段 1：总架构

出口条件：能徒手画出 5 分区结构图，并讲清一次 layer 执行的完整时序（CSB 配置 → 使能 → 引擎执行 → glb 中断）。

1. docs/architecture.md + http://nvdla.org/hwarch.html（重点：conv pipeline 章节 + 各引擎小节）
2. vmod/nvdla/top/NV_nvdla.v：分区例化、三类外部接口（CSB 配置 / DBB+CVSRAM AXI / 中断）
3. 跑 trace 抓波形对照（建议 sanity3 与 pdp_max_pooling_int16，比 sanity0 内容多）：
   在 verif/sim/ 下 `make run DUMP=1 DUMPER=VERDI TESTDIR=... $OVR`（覆盖串见 verif/CLAUDE.md）

## 阶段 2：公共基础 + UT 平台骨架

出口条件：UT 平台三大复用组件（CSB driver、DMA stub 内存、valid/ready monitor）搭出骨架并冒烟通过。

1. CSB 链路：vmod/nvdla/apb2csb/ → vmod/nvdla/csb_master/ → 单元内 csb2xx 分发（req pvld/prdy + resp valid）
2. DMA 接口约定：任选一个引擎的 rdma 看 xx2mcif rd/wr req/rsp 用法（只学协议，mcif 内部留到阶段 5）
3. 浏览级：vmod/vlibs/（assertion、FIFO、同步器）、vmod/rams/（model vs synth）
4. **UT 平台骨架先行**：verif/ut/common/ 搭 CSB driver + DMA stub + monitor，拿 csb_master（纯 CSB、无 DMA）当 DUT 冒烟——避免到 cdma 时"平台没调通 + DUT 最难"两面作战

产出（2026-07-27 完成）：
- 协议 spec：docs/spec/common/csb-link.md、docs/spec/common/dma-if.md（spec 目录约定见 docs/spec/README.md）
- 中文注释：阶段2核心集 10 个 vmod 源文件（apb2csb、csb_master 3 件、CDP reg 三件套、CDP rdma/ig/eg 关键段），tmake 重建 + sanity0 验证无害
- UVM 平台：verif/ut/（csb_agent 双工作面、dma_slave_agent、intr/base 复用层 + csb_master UT），用法见 verif/ut/README.md；smoke + random×3 种子全绿

## 阶段 3：卷积主流水线（数据入口开始，按数据流）

先读 conv 整体 FS（分块/复用策略、weight 压缩、winograd），再进代码。

| 顺序 | 模块组 | 数据流位置 | UT 产物 |
|---|---|---|---|
| 3.1 | cdma + cbuf | 外存 → 取数 → 卷积缓存（取数与缓存强耦合，拆开无意义） | 第一个引擎级 UT |
| 3.2 | csc + cmac + cacc | 发数节拍 → 乘加 → 累加（不可拆） | 子流水线 UT |
| 3.3 | 端到端对照 | conv_8x8_fc_int16、googlenet_conv2_3x3_int16 trace 过波形 | — |

## 阶段 4：后处理链与独立引擎（继续沿数据流）

| 顺序 | 模块 | 数据流位置 | UT 产物 |
|---|---|---|---|
| 4.1 | sdp | 承接 cacc 输出：bias/BN/激活/eltwise（3 条 RDMA + cacc 直连） | UT |
| 4.2 | pdp | sdp 之后可在线级联的池化，也可独立走内存 | UT |
| 4.3 | cdp | 内存→内存的 LRN（LUT 机制与 sdp 同概念） | UT |
| 4.4 | rubik、bdma | 独立数据搬运 | 各半个循环 |

## 阶段 5：基础设施收尾

- mcif/cvif 内部（仲裁、latency FIFO）——精读团队补丁 cd176e6（bready 反压），现成的真实 bug 教材
- glb（中断聚合）、car（时钟复位）、retiming 与分区物理结构（为综合铺垫）

## 阶段 6：ST 环境

1. 全量 trace 回归全绿（make regress，先 MINIREGRESS=1）
2. 自写 trace 生成器：随机层参数 → CSB 序列 + 内存镜像，golden 可借 cmod/ 各单元 C-model 生成
3. 网络级测试扩展

## 进度记录

| 日期 | 完成内容 |
|---|---|
| 2026-07-22 | harness 搭建；构建/仿真链路实测跑通（sanity0 PASSED）；路线图定稿 |
| 2026-07-27 | 阶段 2 完成（DV/DE/DOC 三角色并行）：docs/spec/ 两份公共协议 spec；vmod 核心集 299 行中文注释（重建 diff 仅注释、sanity0 PASSED）；verif/ut/ UVM 平台 + csb_master 冒烟/随机全绿。实测新发现：csb_master 跨扇出口不保序、扇出口仅 1 级保持寄存器、写命令包 [77]=require_ack |
| 2026-08-01 | 阶段 3.1 进行中（Wave 1 完成、Wave 2 推进）：docs/spec/units/cdma-cbuf.md 草稿 + §6 checklist 初版（T0 六项核销）；dma-if.md 两条勘误（cdma 无 credit、响应 mask 仅 2'b11/2'b01）；cdma/cbuf 5 文件中文注释；verif/ut/cdma_cbuf 骨架 + T0 寄存器面全绿。实证发现：复位 flush 全 0（dat/wt 各 4096 拍、与 D_BANK 无关）、updt 增量公式与 9 拍延迟、dma_mux 非仲裁、fetch_grain 受 line_packed 门控、spec/manual 无 CDMA 定义 |
| 2026-08-03 | **阶段 4 环境搭建完成（3.3 按团队决定跳过）**：sdp/pdp/cdp 三 UT 并行落地（common 先冻结：sdp_if src_cb + sdp_source_stub + sdp2pdp 四件套）。每 UT=环境+骨架 scoreboard+T0 寄存器面冒烟，`make regress`（T0×2 seed）三路全绿，六 UT 老回归抽查无破坏。三份验证方案书（环境搭建阶段版）docs/spec/units/{sdp,pdp,cdp}.md：§1/§4 全实、§2 reg2dp 全字段总表（sdp≈140/pdp 67/cdp 61）、§3 仅 T0。实测坑归档 §4.6：SDP/CDP 读 0x00c LUT 指针自增、PDP_RDMA KERNEL_CFG 非法 kw/ksw 当拍断言、ram_type 复位=CV。**下一步：三 UT 测试点分解 + 数据通路 Wave** |
| 2026-08-02 | **阶段 3.2 主体完成**（DOC+DV 双线，三轮同步）：docs/spec/units/csc-cmac-cacc.md 验证方案书（新文档类型；61 feature / 55 reg2dp 零遗漏 / 51 测试点全量状态）；verif/ut/csc_cmac_cacc 回归 **9/9 全绿**（T0×2/T1/T2/T3×3/T5/T6，老回归无破坏）。实测定案：cacc2sdp beat 序（光栅序，int8 恒 2 beat/像素）、跨层 cbuf 指针环形合同、refmodel 支持面（R=S=1、C 64 对齐、K int16≤16/int8≤32、clip 全域）；新发现 sc2cdma_wt_kernels 死字段（回写 cdma-cbuf.md §2.5 勘误）、权重消费面 kernel-slot 格式（§4.4 补注）、wl bank 纯组合断言。核销 28 全/16 部分/7 未做，Wave 3 待办清单见方案书 §3.8。**下一步：阶段 3.3 端到端 trace 对照**（conv_8x8_fc_int16、googlenet_conv2_3x3_int16，与两个 UT 的 refmodel 口径互证） |
