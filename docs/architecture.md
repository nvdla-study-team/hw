# NVDLA v1（nv_full）架构地图

> 供 agent 会话快速定位，人也可读。随代码演进更新——过期的地图比没有更糟。

## 构建流水线（理解本仓库的第一件事）

```
vmod/**/*.v|*.vlib ──vcp(宏展开)──► *.vcp ──eperl(插件展开)──► outdir/nv_full/vmod/**/*.v
                       ▲                        ▲
        outdir/nv_full/spec/defs/project.h   vmod/plugins/{assert,flop,pipe,retime}.pm
        （由 spec/defs/nv_full.spec 生成）
```

- 驱动器：tools/bin/tmake（perl），按 tools/etc/build.config 里的 sandbox 依赖图逐个 `make -C <sandbox>`
- 规则实现：tools/make/vmod_common.make
- **仿真与综合消费的是 outdir/，不是 vmod/**

## 顶层与物理分区

NV_nvdla（vmod/nvdla/top/NV_nvdla.v）= 5 种分区、6 个实例：

| 分区 | 实例 | 内容 |
|---|---|---|
| partition_c | u_partition_c | cdma（取数）、cbuf（卷积缓存）、csc（序列控制） |
| partition_m | u_partition_ma、u_partition_mb | cmac —— MAC 阵列的两半 |
| partition_a | u_partition_a | cacc（卷积累加器） |
| partition_p | u_partition_p | sdp（单点后处理） |
| partition_o | u_partition_o | csb_master、glb、mcif/cvif、pdp、cdp、rubik、bdma |

NV_NVDLA_RT_*（top/ 与 retiming/）是分区间纯打拍 retiming 级，无逻辑。综合按分区分别跑（约束见 syn/cons/）。

## 单元地图（vmod/nvdla/<unit>/）

| 单元 | 职责 |
|---|---|
| cdma | 卷积权重/特征 DMA 取数 |
| cbuf | 卷积 SRAM 缓冲（bank 化） |
| csc | 卷积序列控制器，向 MAC 发数 |
| cmac | MAC 阵列（乘加） |
| cacc | 部分和累加、结果回写 sdp |
| sdp | bias/BN/激活/逐元素后处理 |
| pdp | 池化（独立引擎） |
| cdp | LRN 跨通道归一化（独立引擎） |
| rubik | 数据重排 reshape/split/merge（独立引擎） |
| bdma | 桥 DMA，DRAM↔CVSRAM 搬运 |
| glb | 中断聚合 |
| csb_master | CSB 配置总线主控，寄存器访问分发 |
| nocif | mcif/cvif：把各单元 DMA 请求仲裁到外部 DRAM（DBB AXI）/ CVSRAM |
| car | 时钟与复位 |
| apb2csb | APB → CSB 协议桥 |

RAM：vmod/rams/model 为仿真行为模型，vmod/rams/synth 为综合包装；库单元在 vmod/vlibs。

## 数据流

卷积主流水线：`cdma → cbuf → csc → cmac(ma,mb) → cacc → sdp →（mcif/cvif → 外存）`
独立引擎 pdp / cdp / rubik / bdma 各自直连 mcif/cvif 读写外存。

## 编程模型

- 每个引擎经 CSB 总线配置 **ping-pong 双组寄存器**（组0/组1 交替编程与执行），完成后经 glb 上报中断
- 验证环境就按此模型工作：一个测试 = 一段 CSB 寄存器读写 trace + 输入/golden 内存镜像（verif/traces/traceplayer/<test>/）

## 验证环境（verif/）

- verif/dut/dut.f 文件列表 → VCS 编译 outdir RTL + verif/synth_tb 测试台（csb_master_seq.v 播放 trace、axi_slave.v 内存模型）
- verif/sim/checktest.pl 判定 PASS/FAIL；运行产物落在 verif/sim/（gitignored）
- verif/verilator/：无 VCS 时的开源备选（本机未装 verilator，未实测）

## 其他目录

- cmod/ —— SystemC C-model（参考模型；需 SystemC，本机未装，未实测）
- spec/manual/ —— Ordt（spec/manual/Ordt.jar）生成寄存器手册
- perf/ —— 性能估算电子表格
