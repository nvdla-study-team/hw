# NV_NVDLA_CDMA_dc

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_dc.v`

## 1. 模块定位

`NV_NVDLA_CDMA_dc` 是 CDMA data 侧的 direct convolution feature 取数引擎。

它只处理这种层配置：

```text
reg2dp_conv_mode     = direct
reg2dp_datain_format = feature
```

也就是输入已经是普通 feature map/surface layout，而不是原始 image，也不是 Winograd tile 输入。

在 CDMA 顶层里的主路径是：

```text
regfile 配置
  -> NV_NVDLA_CDMA_dc
  -> dc_dat2mcif/cvif_rd_req_*      // 经 dma_mux 出顶层
  <- mcif/cvif2dc_dat_rd_rsp_*      // 经 dma_mux 分回
  -> shared_buffer                  // DMA 返回后的临时缓存/重排
  -> dc2cvt_dat_wr_*                // 512b 半 entry 送 CVT
  -> status                         // entries/slices 记账
```

`dc` 不直接写 CBUF。它只输出 `dc2cvt_dat_wr_*`，最终 CBUF data 写口由 `NV_NVDLA_CDMA_cvt` 统一产生。

## 2. 主要接口

### 2.1 DMA read 接口

```verilog
dc_dat2mcif_rd_req_valid/ready/pd[78:0]
dc_dat2cvif_rd_req_valid/ready/pd[78:0]
mcif2dc_dat_rd_rsp_valid/ready/pd[513:0]
cvif2dc_dat_rd_rsp_valid/ready/pd[513:0]
```

`reg2dp_datain_ram_type` 决定请求走 MCIF 还是 CVIF。

### 2.2 到 CVT 的输出

```verilog
dc2cvt_dat_wr_en
dc2cvt_dat_wr_addr[11:0]
dc2cvt_dat_wr_hsel
dc2cvt_dat_wr_data[511:0]
dc2cvt_dat_wr_info_pd[11:0]
```

这里 data 只有 512 bit，表示一个 CBUF entry 的半边。`hsel` 表示这一拍写低半还是高半。CVT 会把 DC/WG 的半 entry 输入扩展、转换、拼接成最终 `cdma2buf_dat_wr_data[1023:0]`。

### 2.3 shared_buffer 端口

```verilog
dc2sbuf_p0_wr_en/addr/data[255:0]
dc2sbuf_p1_wr_en/addr/data[255:0]
dc2sbuf_p0_rd_en/addr -> dc2sbuf_p0_rd_data[255:0]
dc2sbuf_p1_rd_en/addr -> dc2sbuf_p1_rd_data[255:0]
```

DMA response 回来后先写 shared buffer，再按卷积消费顺序读出送 CVT。

### 2.4 status 记账接口

```verilog
status2dma_free_entries[11:0]
status2dma_wr_idx[11:0]
status2dma_valid_slices[11:0]
status2dma_fsm_switch

dc2status_dat_updt
dc2status_dat_entries[11:0]
dc2status_dat_slices[11:0]
dc2status_state[1:0]
```

`status2dma_free_entries` 和 `status2dma_wr_idx` 是 DC 发请求/生成 CBUF 写地址的重要约束。CBUF 没有 ready，DC 必须自己保证不会写爆 data 区。

## 3. FSM

主 FSM 定义：

```verilog
localparam DC_STATE_IDLE = 2'b00;
localparam DC_STATE_PEND = 2'b01;
localparam DC_STATE_BUSY = 2'b10;
localparam DC_STATE_DONE = 2'b11;
```

状态语义：

| 状态 | 语义 |
|---|---|
| `IDLE` | 等待 `dc_en`，即本层确认为 DC 模式且 `op_en` 生效 |
| `PEND` | 处理 `sc2cdma_dat_pending_req`，等待清账握手完成 |
| `BUSY` | 正常生成 DMA 请求、接收 response、写 shared_buffer/CVT |
| `DONE` | DC 侧取数完成，等待 `status2dma_fsm_switch` 回到 IDLE |

关键跳转：

```text
IDLE + dc_en + need_pending -> PEND
IDLE + dc_en                -> BUSY
BUSY + fetch_done           -> DONE
DONE + status2dma_fsm_switch -> IDLE
```

特殊路径：

```text
IDLE + dc_en + data_reuse + last_skip_data_rls + mode_match -> DONE
```

这表示 data reuse/skip release 场景下，本层不需要实际重新 fetch data，直接完成。

## 4. DMA request 生成

DC request 是 79 bit：

```verilog
dma_rd_req_pd[63:0]  = dma_rd_req_addr[63:0];
dma_rd_req_pd[78:64] = dma_rd_req_size[14:0];
```

地址按 32B atom 对齐：

```verilog
dma_rd_req_addr = {req_addr_d1[58:0], 5'b0};
```

请求 size 是 0-based 的 32B atom 数：

```verilog
req_atm_size_out = req_atm_size - 1'b1;
dma_rd_req_size  = {{13{1'b0}}, req_size_out_d1};
```

`req_atm_size_addr_limit` 限制第一笔请求不能跨越 256B 对齐边界：

```verilog
req_atm_size_addr_limit =
    (req_atm_cnt == 14'b0) ? (4'h8 - req_addr[2:0]) : 4'h8;
```

因此单笔最多 8 个 32B atom，即 256B。

## 5. Request/response 匹配 FIFO

DC 内部实例化：

```verilog
NV_NVDLA_CDMA_DC_fifo u_fifo
```

发出请求时写 FIFO：

```verilog
dma_req_fifo_req  = req_valid_d1 & dma_rd_req_rdy;
dma_req_fifo_data = {req_ch_idx_d1, req_size_d1};
```

FIFO 记录这笔 DMA 请求的 channel index 和 size。response 回来后，DC 用 FIFO 中的信息判断当前 response 属于哪个内部通道、需要接收多少 beat，从而正确写入 shared_buffer 和后续输出到 CVT。

## 6. MCIF/CVIF 选择与 response 合并

DC 内部先生成抽象 `dma_rd_req_*`，再按 `reg2dp_datain_ram_type` 选择外部接口：

```text
datain_ram_type = MCIF -> dc_dat2mcif_rd_req_*
datain_ram_type = CVIF -> dc_dat2cvif_rd_req_*
```

MCIF/CVIF response 正常不会同拍同时返回给 DC，RTL 有断言：

```verilog
nv_assert_never(..., mc_dma_rd_rsp_vld & cv_dma_rd_rsp_vld);
```

response ready：

```verilog
dma_rd_rsp_rdy = ~is_blocking;
```

`is_blocking` 表示内部下游暂时不能接收 response，DC 会反压 DMA response。

## 7. shared_buffer 写入

DC 将 DMA response 拆成两个 256-bit port 写入 shared_buffer：

```verilog
dc2sbuf_p0_wr_en   = p0_wr_en;
dc2sbuf_p1_wr_en   = p1_wr_en;
dc2sbuf_p0_wr_addr = p0_wr_addr;
dc2sbuf_p1_wr_addr = p1_wr_addr;
dc2sbuf_p0_wr_data = dma_rsp_data_p0;
dc2sbuf_p1_wr_data = dma_rsp_data_p1;
```

这样做的原因是 DMA 返回宽度为 512 bit，而 shared_buffer 物理上用 256-bit RAM port 组织，DC 把一拍 response 拆成 p0/p1 两半写入。

## 8. 到 CVT 的输出

DC 输出给 CVT 的最终寄存器为：

```verilog
dc2cvt_dat_wr_en      = cbuf_wr_en_d3;
dc2cvt_dat_wr_addr    = cbuf_wr_addr_d3;
dc2cvt_dat_wr_hsel    = cbuf_wr_hsel_d3;
dc2cvt_dat_wr_info_pd = cbuf_wr_info_pd_d3;
dc2cvt_dat_wr_data    = cbuf_wr_data_d3;
```

注意这里信号名里带 `cbuf_wr`，但 DC 并不直接写 CBUF。它只是把“将来要写 CBUF 的地址/半字/数据/格式信息”送给 CVT。

## 9. status 增量输出

DC 写出一批 CBUF data 后，向 status 报增量：

```verilog
dc2status_dat_updt    = dat_updt_d3;
dc2status_dat_entries = dat_entries_d3;
dc2status_dat_slices  = dat_slices_d3;
```

status 再维护全局 data CBUF 账本，并延迟后通知 CSC。

## 10. 容易误解的点

1. `dc` 是普通 feature map 取数，不处理 image pixel format，也不做 Winograd tile 组织。
2. `dc` 不直接连 `cdma2buf_dat_wr_*`，它只输出 `dc2cvt_dat_wr_*`。
3. `dc2cvt_dat_wr_data` 是 512 bit，不是最终 CBUF 的 1024 bit。
4. `status2dma_free_entries` 是 DC 安全取数/写 CBUF 的关键约束，因为 CBUF 写口无 ready。
5. `NV_NVDLA_CDMA_DC_fifo` 不是大数据缓存，它保存请求元信息，用来匹配 response。

