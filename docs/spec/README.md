# docs/spec/ — 模块与协议 Spec 目录

本目录存放团队自写的 NVDLA（nv_full 配置）功能规格（specification, spec），供 RTL 学习与
verif/ut/ 单元验证（Unit Test, UT）共同消费。**所有论断以 vmod/ 源码实读为准**；凡与官方文档
（http://nvdla.org/hwarch.html ）或团队记忆不符处，以代码为准并在文中标注勘误。

## 目录结构与分工

| 子目录 | 内容 | 时机 |
|---|---|---|
| `common/` | 跨模块公共协议：多个单元共享的总线/握手/打包约定，一份协议一篇 | 阶段2 起 |
| `units/` | 每个功能单元一份 `<unit>.md`（如 `sdp.md`、`cdp.md`），描述该单元的对外接口、寄存器组、内部数据通路要点 | 阶段3 起（现为 `.gitkeep` 占位） |

当前已有：

| 文件 | 主题 |
|---|---|
| [common/csb-link.md](common/csb-link.md) | CSB（Configuration Space Bus）链路：外部 APB → apb2csb → csb2nvdla 单口 → csb_master（CDC + 译码）→ 17 路 csb2xx → 单元内 reg 终点 |
| [common/dma-if.md](common/dma-if.md) | xx2mcif / xx2cvif DMA 客户端协议：读/写请求、latency FIFO 信用（credit）、双目的地选路 |

单元 spec 与公共协议 spec 的分界：**凡是两个以上单元以相同形状出现的接口，写进 common/，
units/ 里只引用不复述**（例如各引擎的 csb2xx 口、xx2mcif 口都指向 common/ 两篇）。

## units/ 下的两种文档类型

除四要素 spec 外，units/ 另设**验证方案书**（verification plan）文档类型，用于多单元
联合 UT（如 `csc-cmac-cacc.md`）：一次验证跨越多个单元时，先于逐单元 spec 产出一份
面向验证的整体方案。验证方案书固定四部分结构：**① DUT 架构与代码列表 ② feature
功能特性清单 ③ 测试点 ④ 验证框架**，题头显式标注"文档类型：验证方案书"以与四要素
spec 区分；file:line 引用规则与行文约定与 spec 相同。

## Spec 编写模板（四要素，缺一不可）

每篇 spec 必须包含以下四个部分，标题措辞可调整，内容不可省略：

1. **接口信号表** —— 信号名 / 方向 / 位宽 / 语义，按通道分组；打包信号（pd）给出逐字段位图。
2. **寄存器组说明（如适用）** —— 寄存器组划分（single/dual、ping-pong 指针等）、地址范围、
   与 `spec/manual/`（Ordt 输入）及 `outdir/nv_full/` 生成产物的对照方法。纯协议类 spec
   （无寄存器）可注明"不适用"。
3. **代码入口 file:line 表** —— 每个关键论断对应的源码位置。引用规则：
   - 一律给仓库相对路径 + 行号，如 `vmod/nvdla/apb2csb/NV_NVDLA_apb2csb.v:93`；
   - 以 vmod/ 下源文件为准；只有当事实仅存在于生成产物中（宏/eperl 展开结果）时才引用
     `outdir/nv_full/...`，并注明"生成文件"；
   - 行号随代码演进会漂移，修订 spec 时须重新核对。
4. **UT 测试点 checklist** —— 面向 verif/ut/ 的可勾选测试点清单，每条测试点应能追溯到
   本文某一节的协议论断。

## 行文约定

- 中文行文，术语首次出现给英文原名（如 非缓写 posted / 缓写 nposted）。
- 表格优先于长段落；波形/时序描述给"拍"级语义即可，不画逐拍波形图。
- 勘误（与官方文档、常见认知或团队旧笔记不符处）用醒目引用块标出，并给出代码依据。
- 文档过期比没有更糟：接口/行为改动合入后，同一 PR 内更新对应 spec。
