# verif/ut — 自研 UVM 单元验证平台

团队学习项目自建的 UT 平台（VCS + UVM-1.2），与上游 `verif/{sim,synth_tb,traces}` 完全独立：
上游环境只读、只学；所有 UT 代码与产物都收在本目录。DUT 源一律取 `outdir/nv_full/vmod/`
（tmake 产物，工具真正消费的 Verilog）。

协议细节不在本文重复，见 spec：

- CSB 链路：`docs/spec/common/csb-link.md`
- DMA 客户端接口：`docs/spec/common/dma-if.md`

## 目录结构

```
verif/ut/
├── common.mk                  公共 make 片段（变量全 ?=，目标 build/run/check/wave/verdi/clean）
├── common/                    复用层（唯一 package：nvdla_ut_pkg）
│   ├── nvdla_ut_pkg.sv
│   ├── base/ut_types.svh      csb_tgt_e(=块号) / csb_target_of() / csb_default_pattern()
│   ├── base/ut_base_test.svh  +ut_timeout_us= 超时 + "UT RESULT: PASSED/FAILED" 横幅
│   ├── csb/                   CSB 两工作面：
│   │   ├── csb_if.sv              单口面 interface（falcon 域，drv_cb/mon_cb）
│   │   ├── csb_fanout_if.sv       扇出面 interface（core 域，rsp_cb/mon_cb；阶段3 加 drv_cb）
│   │   ├── csb_seq_item.svh       一套 item 两面共用
│   │   ├── csb_master_{driver,monitor,agent}.svh
│   │   └── csb_fanout_{cfg,responder,monitor,agent}.svh   1 个类 × 17 实例
│   ├── dma/                   dma_if + dma_slave_{responder,monitor,agent}（参数化）
│   ├── cbuf/                  cbuf 写监测 + sc2buf 读口 agent + cbuf_model（阶段3.1）
│   ├── cdma_sc/               cdma<->csc 状态/信用面 stub 两方向（阶段3.1/3.2）
│   ├── sdp/                   cacc2sdp 协议（历史命名）：sdp_if（drv_cb=sink、src_cb=源，
│   │                          阶段4 增）+ sdp_item + sdp_sink_stub + sdp_source_stub（阶段4 增）
│   ├── sdp2pdp/               sdp→pdp 链路 256b 流（阶段4 新增）：
│   │                          sdp2pdp_{if,item,sink_stub,source_stub}
│   └── intr/                  intr_if + intr_agent（monitor-only）
├── csb_master/                UT#1（阶段2）：NV_NVDLA_csb_master
│   ├── Makefile / filelist.f / csb_master_ut_pkg.sv
│   ├── tb/tb_top.sv           双时钟 10ns/7ns、17 路端口↔if 宏批量连接
│   ├── env/csb_master_{env,scoreboard}.svh
│   ├── seqs/csb_{base,smoke,dummy,random}_seq.svh
│   └── tests/csb_master_test_lib.svh   base / smoke / random
├── cdma_cbuf/                 UT#2（阶段3.1）：cdma+cbuf，refmodel/layer_cfg 三件套
├── csc_cmac_cacc/             UT#3（阶段3.2）：csc+cmac×2+cacc，tb 由 tb/gen_tb_top.py 生成
├── sdp/                       UT#4（阶段4）：NV_NVDLA_sdp，4 读 DMA + cacc2sdp/sdp2pdp 直连
├── pdp/                       UT#5（阶段4）：NV_NVDLA_pdp，1 读 1 写 + sdp2pdp 源
└── cdp/                       UT#6（阶段4）：NV_NVDLA_cdp，1 读 1 写、无直连
```

阶段4 三 UT（sdp/pdp/cdp）当前为**环境+T0 寄存器面冒烟**（`make regress` = T0 ×
seed1/2），测试点分解与数据通路见 `docs/spec/units/{sdp,pdp,cdp}.md` 验证方案书。
注意 `common/sdp/` 指 **cacc2sdp 协议**（历史命名），`common/sdp2pdp/` 才是
sdp→pdp 链路——勿混。

## 平台结构（csb_master UT）

```
                 falcon 域 (10ns)          │           core 域 (7ns)
  seqs ──> sqr ──> csb_master_driver ──┐   │   ┌── csb_fanout_responder[i]（reactive）
                                       ▼   │   ▼        背压 req_prdy + 本地 mem + 延迟响应
                csb_if ──────────► NV_NVDLA_csb_master ◄────── csb_fanout_if × 17
                                       │   │   │
           csb_master_monitor ─────────┘   │   └───────── csb_fanout_monitor[i]
                │ ap_req/ap_rsp            │                    │ ap_req/ap_rsp（17 路共用 imp）
                ▼                          │                    ▼
                └────────────► csb_master_scoreboard ◄──────────┘
                     （路由 / pd 字段还原 / 响应数据与 type / 队列清空）
```

## 跑法

```bash
cd verif/ut/csb_master
make run                                    # 默认 csb_master_smoke_test，seed 1
make run TEST=csb_master_random_test SEED=2
make regress                                # smoke + random x {1,2,3}，任一失败即停
make run WAVES=1 PLUSARGS=+UVM_VERBOSITY=UVM_HIGH   # 波形编译产物落 out_waves/
make verdi WAVES=1                          # 打开 out_waves/waves.fsdb
make clean
```

常用可覆盖变量（common.mk 全部 `?=`，命令行 / 环境均可覆盖）：
`VCS_HOME VERDI_HOME NOVAS_HOME LM_LICENSE_FILE VCS_CC UVM_VER TEST SEED UVM_VERBOSITY WAVES PLUSARGS OUTDIR`。
运行期 plusarg：`+ut_timeout_us=`（默认 500）、`+falcon_period_ns= +core_period_ns=`、`+fsdb +fsdbfile=`。

## check 判定（make check，run 后自动执行）

四条同时满足才 PASS，任一不满足非零退出：

1. 日志汇总 `UVM_FATAL : 0`
2. 日志汇总 `UVM_ERROR : 0`
3. 无 `^ERROR :` 行 —— DUT 内建断言（+define+ASSERT_ON）失败只打印 ERROR 并 $finish，
   **不产生 UVM_ERROR**，必须单独 grep
4. 有 `UT RESULT: PASSED` 横幅（ut_base_test final_phase 按 report server 计数打印）

## 关键设计决策（从 RTL 实测得来，阶段3 沿用）

1. **driver 串行化带响应事务**（读 / nposted 写等响应回来才 item_done；posted 写可流水）。
   两条根据：① 响应汇聚是 OR-mux 无仲裁 + 19 路 zero_one_hot 断言，多于 1 笔在途响应
   直接混叠；② 每路目的地出口只有 1 级保持寄存器（NV_NVDLA_csb_master.v:652-699 一带），
   持续背压下硬灌第二笔会覆盖丢失。
2. **DUT 只保证同一扇出口内请求有序，跨口不保序**（random seed2 实测抓到）：
   core_req_prdy 恒 1，FIFO 每拍照常 pop 进各口各自的保持寄存器，某口被背压时后到的
   请求可先在其它口完成握手。scoreboard 预期队列按目的地分开（exp_fan_q[17]），
   不能建全局 FIFO 序模型。
3. **同口覆盖风险由激励规避**：csb_random_seq 在 posted 写之后给下一笔 idle_before
   ∈[7:12] falcon 拍（>背压最大滞留 gap_max+1=9 core 拍），保证不触发覆盖。
   这是 RTL 真实限制（软件侧同样不能对被背压的口背靠背灌 posted 写）。
4. **dummy 行为**（word addr ≥ 0x4400）：读回 0、nposted 写回 wr_complete、posted 写
   无响应、**不回 error**。
5. responder 读数据 = 本地 mem 命中值或 `csb_default_pattern(tgt_id,addr)`
   （32'hD000_0000 | tgt<<16 | addr），scoreboard 用镜像 mem 独立复算，不抄 responder。

## 阶段3 扩展指引

- **新 UT**：拷 `csb_master/` 目录骨架，改 Makefile 四个变量 + filelist.f（DUT 件与 incdir），
  env/seqs/tests 换成目标模块的；复用层组件直接 import nvdla_ut_pkg 使用。
- **csb_fanout_agent 变主动 master**：单元 UT（如 CDP）的 reg 面就是一路 csb2xx 请求口。
  在 csb_fanout_if 加 drv_cb（output req_pvld/req_pd, input req_prdy/resp_*），agent 加
  is_active + driver/sequencer，复用同一 csb_seq_item。
- **dma_slave_agent 接线**：阶段2 只保证编译与可实例化（nvdla_ut_pkg 尾部 cdp 位宽
  typedef 特化）。接真 DUT 时：tb 例化 `dma_if#(...)`，config_db set "dma_vif"。
  注意写通道 wr_rsp_complete 只对 require_ack=1（wr cmd pd[77]）的命令返回；
  credit 归还脉冲源头见 NV_NVDLA_CDP_RDMA_eg.v:343 附近；读 rsp mask[1:0] 是
  512-bit beat 的两个 256-bit 半拍有效位；mcif/cvif 双目的地按 ram_type（1=MC 0=CV）选路。
- **中断**：intr_agent 已可用（上升沿计数 + analysis port），tb set "intr_vif" 即挂。
