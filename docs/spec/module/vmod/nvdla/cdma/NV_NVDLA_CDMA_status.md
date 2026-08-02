# NV_NVDLA_CDMA_status

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_status.v`

## 1. 模块定位

`NV_NVDLA_CDMA_status` 是 CDMA data 侧的账本和切层中枢。

它主要做三件事：

- 维护 CBUF data 区的 `valid_entries`、`valid_slices`、`free_entries`、`wr_idx`；
- 判断 data 侧和 weight 侧是否都完成，并产生 `status2dma_fsm_switch` / `dp2reg_done`；
- 处理 CSC 发起的 data pending 清账握手。

注意：weight 区的 entries/kernels/wmb 记账主要在 `NV_NVDLA_CDMA_wt` 内部完成；本模块只管 data 区。

## 2. 主要接口

### 2.1 data engine 增量输入

```verilog
dc2status_dat_updt/entries/slices
wg2status_dat_updt/entries/slices
img2status_dat_updt/entries/slices
```

DC/WG/IMG 三路互斥，正常同拍只会有一路上报增量。

### 2.2 CSC 释放输入

```verilog
sc2cdma_dat_updt
sc2cdma_dat_entries[11:0]
sc2cdma_dat_slices[11:0]
```

CSC 从 CBUF 消费完 data 后，通过这些信号把 entries/slices 归还给 CDMA。

### 2.3 回供 DMA 的账本输出

```verilog
status2dma_valid_slices[11:0]
status2dma_free_entries[11:0]
status2dma_wr_idx[11:0]
```

data engine 根据这些值决定还能不能继续预取、下一批写到 CBUF data 区哪个 entry。

### 2.4 对 CSC 的 data update 输出

```verilog
cdma2sc_dat_updt
cdma2sc_dat_entries[11:0]
cdma2sc_dat_slices[11:0]
```

这是 CDMA 通知 CSC “CBUF data 区新增可读数据”的接口。

### 2.5 done / 切层接口

```verilog
dc2status_state[1:0]
wg2status_state[1:0]
img2status_state[1:0]
wt2status_state[1:0]

status2dma_fsm_switch
dp2reg_done
cdma_dat2glb_done_intr_pd[1:0]
cdma_wt2glb_done_intr_pd[1:0]
```

各子模块状态编码：

| 值 | 状态 |
|---|---|
| 0 | idle |
| 1 | pend |
| 2 | busy |
| 3 | done |

## 3. data 区容量

`reg2dp_data_bank` 是 N-1 编码，RTL 加 1 得到真实 data bank 数：

```verilog
real_bank_w = reg2dp_data_bank + 1'b1;
```

每个 CBUF bank 有 256 个 entry，所以 data 区容量是：

```text
real_bank * 256 entries
```

RTL 写成：

```verilog
{real_bank, 8'b0}
```

## 4. entries/slices 记账

DMA 写入增量：

```verilog
entries_add = (dc_updt  ? dc_entries  : 0) |
              (wg_updt  ? wg_entries  : 0) |
              (img_updt ? img_entries : 0);
```

RTL 用掩码 OR 写法实现：

```verilog
entries_add = ({12{dc2status_dat_updt}}  & dc2status_dat_entries) |
              ({12{wg2status_dat_updt}}  & wg2status_dat_entries) |
              ({12{img2status_dat_updt}} & img2status_dat_entries);
```

CSC 释放量：

```verilog
entries_sub = sc2cdma_dat_updt ? sc2cdma_dat_entries : 12'b0;
```

核心公式：

```verilog
status2dma_valid_entries_w =
    status2dma_valid_entries + entries_add - entries_sub;

status2dma_valid_slices_w =
    status2dma_valid_slices + slices_add - slices_sub;
```

pending 清账时优先清零：

```verilog
(pending_ack & pending_req) ? 13'b0 : ...
```

## 5. free_entries

```verilog
status2dma_free_entries_w =
    {real_bank, 8'b0} - status2dma_valid_entries_w;
```

这里使用 `valid_entries_w` 新值，所以 `free_entries` 与同拍增减后的 valid 账本保持一致。

`free_entries` 是 DC/WG/IMG 限流预取的核心信号。CBUF data 写口没有 ready，不能靠 CBUF 自己挡写爆。

## 6. wr_idx 环形写指针

`status2dma_wr_idx` 是 data 区 entry 粒度写指针。

更新逻辑：

```verilog
status2dma_wr_idx_inc = status2dma_wr_idx + entries_add;
status2dma_wr_idx_inc_wrap =
    status2dma_wr_idx + entries_add - {real_bank, 8'b0};
status2dma_wr_idx_overflow =
    status2dma_wr_idx_inc >= {1'b0, real_bank, 8'b0};
```

选择：

```verilog
status2dma_wr_idx_w =
    (pending_ack & pending_req) ? 12'b0 :
    (~update_dma) ? status2dma_wr_idx :
    status2dma_wr_idx_overflow ? status2dma_wr_idx_inc_wrap :
    status2dma_wr_idx_inc[11:0];
```

也就是：

- DMA 报增量时写指针前进；
- 超过 data 区容量时回绕；
- pending 清账时归零；
- CSC 释放只影响 valid/free，不直接移动 wr_idx。

## 7. cdma2sc_dat_updt 延迟

DMA engine 报 `*_2status_dat_updt` 的时刻早于数据真正落到 CBUF RAM。为了避免 CSC 太早读，status 把 update 打 9 拍：

```text
dat_updt_d0 -> ... -> dat_updt_d9
dat_entries_d0 -> ... -> dat_entries_d9
dat_slices_d0 -> ... -> dat_slices_d9
```

最终输出：

```verilog
cdma2sc_dat_updt    = dat_updt_d9;
cdma2sc_dat_entries = dat_entries_d9;
cdma2sc_dat_slices  = dat_slices_d9;
```

这 9 拍用于对齐 CVT 流水和 CBUF 写流水，保证 CSC 收到 update 后可以安全发读。

## 8. done 与切层

data 侧 done 是 DC/WG/IMG 任一路 done：

```verilog
dat2status_done = dc2status_done | wg2status_done | img2status_done;
```

切层要求 data 和 weight 都 done：

```verilog
status2dma_fsm_switch_w =
    reg2dp_op_en &
    ~status2dma_fsm_switch &
    wt2status_done &
    dat2status_done;
```

`~status2dma_fsm_switch` 是自屏蔽，保证 `fsm_switch` 只出一拍。

`dp2reg_done` 直接等于 `status2dma_fsm_switch`：

```verilog
assign dp2reg_done = status2dma_fsm_switch;
```

这会驱动 regfile 清当前 group 的 `op_en` 并翻转 consumer。

## 9. done interrupt

data 和 weight 各自独立产生 done interrupt，不需要等对方：

```verilog
dat_done_intr_w[0] = reg2dp_op_en & ~dp2reg_consumer & ~dat_done_d1 & dat_done;
dat_done_intr_w[1] = reg2dp_op_en &  dp2reg_consumer & ~dat_done_d1 & dat_done;
```

bit0 对应 group0，bit1 对应 group1。weight 侧同理。

## 10. pending 清账

CSC 拉起：

```verilog
sc2cdma_dat_pending_req
```

活跃 data engine 进入 pend 状态后，status 回 ack：

```verilog
pending_ack_w =
    reg2dp_op_en & (dc2status_pend | wg2status_pend | img2status_pend);

cdma2sc_dat_pending_ack = pending_ack;
```

`pending_ack & pending_req` 同拍作为清账事件，把：

```text
valid_entries
valid_slices
wr_idx
```

清零。

## 11. 断言保护

本模块断言了若干关键前提：

- `op_en` 无效时子模块不能报 done；
- DC/WG/IMG 不能两路同时 done；
- pending 期间不能同时有 DMA 增量；
- 账本增减不应非法下溢/溢出。

## 12. 容易误解的点

1. `status` 只管 data CBUF 区，不管 weight 区完整账本。
2. `cdma2sc_dat_updt` 不是立即转发 DMA engine 的 updt，而是延迟 9 拍后输出。
3. `free_entries` 用于 CDMA 自限流，不是 CBUF 返回的 ready。
4. `dp2reg_done` 要等 data 和 weight 都 done；但 data/weight done interrupt 可以各自先报。
5. `wr_idx` 是写指针，CSC 释放 data 不会让它倒退。

