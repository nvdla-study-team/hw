# NV_NVDLA_CMAC_reg

## 1. 模块定位

`NV_NVDLA_CMAC_reg` 是 CMAC 的 CSB 寄存器前端和双组配置管理器。它实例化一份 single register 与两份 dual register，在 producer/consumer 机制下允许软件配置下一层、硬件执行当前层。

模块端口使用 `csb2cmac_a_*`/`cmac_a2csb_*` 命名；同一 RTL 也可在 CMAC-B 实例中接到对应的 B 侧 CSB 目标。

## 2. 寄存器组织

| 地址偏移 | 寄存器 | 类型 | 关键字段 |
| --- | --- | --- | --- |
| `0x7000` | `S_STATUS` | 只读 | 两组状态 |
| `0x7004` | `S_POINTER` | 读写/只读 | producer、consumer |
| `0x7008` | `D_OP_ENABLE` | 双组 | `op_en` |
| `0x700c` | `D_MISC_CFG` | 双组 | `conv_mode`、`proc_precision` |

地址比较使用低 12 bit，因此 A/B 的顶层 CSB 路由负责选择目标，模块内部看到同一套寄存器偏移。

## 3. 架构图

```mermaid
flowchart LR
    CSB["CSB request"] --> REQ["请求锁存/地址译码"]
    REQ --> S["REG_single\nstatus + pointer"]
    REQ --> D0["REG_dual D0"]
    REQ --> D1["REG_dual D1"]
    S --> P["producer"]
    DONE["dp2reg_done"] --> C["consumer 翻转"]
    P --> SEL["写选择"]
    C --> SEL2["运行组选择"]
    D0 --> SEL2
    D1 --> SEL2
    SEL2 --> CFG["reg2dp 配置 + op_en"]
    CFG --> PIPE["slcg_op_en 延迟链"]
    REQ --> RSP["CSB read response"]
```

## 4. Ping-pong 生命周期

```mermaid
sequenceDiagram
    participant SW as 软件/CSB
    participant REG as CMAC_reg
    participant DP as CMAC core
    SW->>REG: producer 选择空闲组
    SW->>REG: 写 D_MISC_CFG
    SW->>REG: 写 D_OP_ENABLE=1
    REG->>DP: consumer 组配置 + op_en
    DP->>REG: dp2reg_done
    REG->>REG: 清当前 op_en，consumer 翻转
    REG->>DP: 若另一组已使能则继续运行
```

正在运行的 consumer 组禁止被软件重写；软件只应修改 producer 指向的空闲组。状态编码为：`0=IDLE`、`1=BUSY`、`2=PENDING`。当前 consumer 且已使能的组为 BUSY，另一已使能组为 PENDING。

## 5. 时钟使能与完成处理

- `reg2dp_op_en` 经过多级同步/延迟后送往数据通路配置控制。
- 11-bit `slcg_op_en` 由操作使能复制并流水化，用于覆盖 CMAC 各阶段的时钟需求。
- `dp2reg_done` 到来时清除当前 dual 组的 `op_en`，并翻转 consumer。
- 若另一组已经由软件置为 enable，可在组切换后衔接下一 layer。

## 6. 阅读要点

- single register 是全局状态；dual register 才是每个 layer 的 shadow 配置。
- `producer` 由软件控制，`consumer` 由硬件完成事件控制，两者不能混用。
- CSB 应答、寄存器读写和 data-path 配置输出属于不同流水边界。

