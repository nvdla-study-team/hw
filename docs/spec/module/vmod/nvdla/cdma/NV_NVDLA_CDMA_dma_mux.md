# NV_NVDLA_CDMA_dma_mux

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_dma_mux.v`

## 1. 模块定位

`NV_NVDLA_CDMA_dma_mux` 是 CDMA data 侧的 DMA 读口三合一模块：

```text
u_dc / u_wg / u_img
  -> NV_NVDLA_CDMA_dma_mux
  -> cdma_dat2mcif_rd_req_* / cdma_dat2cvif_rd_req_*

mcif2cdma_dat_rd_rsp_* / cvif2cdma_dat_rd_rsp_*
  -> NV_NVDLA_CDMA_dma_mux
  -> u_dc / u_wg / u_img
```

它只服务 data 侧。weight 侧 `u_wt` 独占 `cdma_wt2mcif_*` / `cdma_wt2cvif_*` 读口，不经过本模块。

本模块不生成 DMA 请求、不修改 request/response payload，也不维护 CBUF 空间账本。它只做：

- DC/WG/IMG 三路 data request 合并到 MCIF/CVIF 两个外部接口；
- MCIF/CVIF response 按请求来源分回 DC/WG/IMG；
- 在 req/rsp 两个方向各插入一级 ready/valid pipe。

## 2. 关键设计前提

DC、WG、IMG 在一层 CDMA 操作中互斥：

| 通路 | 场景 |
|---|---|
| DC | direct convolution + feature input |
| IMG | direct convolution + image/pixel input |
| WG | Winograd convolution + feature input |

因此同一时刻最多只有一路 data engine 发请求。本模块基于这个前提实现为 OR 汇合，而不是仲裁器。

RTL 末尾用 zero-one-hot 断言保护这个前提。MCIF 侧断言形如：

```verilog
nv_assert_zero_one_hot(...,
  {dc_dat2mcif_rd_req_valid,
   wg_dat2mcif_rd_req_valid,
   img_dat2mcif_rd_req_valid});
```

如果两路同时 valid，本模块不会仲裁，request payload 会被按位 OR 到一起，属于非法情况。

## 3. Request 方向

MCIF 和 CVIF 两套 request 逻辑完全同构。以 MCIF 为例。

### 3.1 选择信号

```verilog
mc_sel_dc_w  = dc_dat2mcif_rd_req_valid;
mc_sel_wg_w  = wg_dat2mcif_rd_req_valid;
mc_sel_img_w = img_dat2mcif_rd_req_valid;
```

因为三路 valid 互斥，所以 valid 本身就是 one-hot select。

### 3.2 valid 合并

```verilog
req_mc_in_pvld = dc_dat2mcif_rd_req_valid |
                 wg_dat2mcif_rd_req_valid |
                 img_dat2mcif_rd_req_valid;
```

只要任一路 data engine 发请求，mux 输入侧 request valid 就拉高。

### 3.3 payload 合并

```verilog
req_mc_in_pd = ({79 {mc_sel_dc_w}}  & dc_dat2mcif_rd_req_pd) |
               ({79 {mc_sel_wg_w}}  & wg_dat2mcif_rd_req_pd) |
               ({79 {mc_sel_img_w}} & img_dat2mcif_rd_req_pd);
```

这是 one-hot mux 的掩码 OR 写法。正常情况下只有一路 select 为 1，所以 `req_mc_in_pd` 等于当前活跃 engine 的 79-bit request packet。

79-bit DMA read request packet 语义由各 data engine 生成，本模块不解析：

```text
pd[63:0]  = address
pd[78:64] = size
```

### 3.4 ready 回传

```verilog
dc_dat2mcif_rd_req_ready  = req_mc_in_prdy & dc_dat2mcif_rd_req_valid;
wg_dat2mcif_rd_req_ready  = req_mc_in_prdy & wg_dat2mcif_rd_req_valid;
img_dat2mcif_rd_req_ready = req_mc_in_prdy & img_dat2mcif_rd_req_valid;
```

`req_mc_in_prdy` 是合并点的统一 ready。RTL 把它与各路 valid 相与后再回传，目的是只让当前发请求的 engine 看到握手成立，避免空闲 engine 误采样 ready。

### 3.5 req pipe

合并后的 request 经过一级 ready/valid pipe：

```text
req_mc_in_* -> skid buffer -> bubble-collapse pipe -> req_mc_out_*
```

作用：

- 切断跨模块组合时序路径；
- 下游反压时用 skid register 暂存一拍数据；
- 保持 ready/valid 协议：valid 在 ready 前不能撤销；
- 正常无反压时保持每拍一笔吞吐。

pipe 输出再连到 CDMA 顶层 MCIF data request：

```verilog
cdma_dat2mcif_rd_req_valid = req_mc_out_pvld;
cdma_dat2mcif_rd_req_pd    = req_mc_out_pd;
req_mc_out_prdy            = cdma_dat2mcif_rd_req_ready;
```

CVIF request 侧同理，只是信号名前缀从 `mc` 换成 `cv`。

## 4. Response 方向

Response 方向也是 MCIF/CVIF 两套同构逻辑。以 MCIF 为例。

### 4.1 请求来源记录

request 握手成立时，本模块寄存这一侧接口当前由哪个 data engine 使用：

```verilog
if (req_mc_in_pvld & req_mc_in_prdy)
    mc_sel_dc <= mc_sel_dc_w;
```

`mc_sel_wg`、`mc_sel_img` 同理。

这里不是 per-request tag queue。它只记录当前接口归属。这个设计成立的原因是：

- 同一层内 DC/WG/IMG 互斥；
- 层切换前 active engine 会收完在途 response；
- 因此 response 回来时只需要知道当前活跃 engine 是谁。

如果未来设计允许 DC/WG/IMG 交错发 request，这个 mux 就不够，需要真正的 outstanding tag/FIFO。

### 4.2 response 输入 pipe

外部 MCIF response 先进入 pipe：

```text
mcif2cdma_dat_rd_rsp_* -> rsp_mc_in_* -> pipe -> rsp_mc_out_*
```

和 request 方向一样，pipe 用于切断时序并处理反压。

### 4.3 valid 分发

```verilog
mcif2dc_dat_rd_rsp_valid  = rsp_mc_out_pvld & mc_sel_dc;
mcif2wg_dat_rd_rsp_valid  = rsp_mc_out_pvld & mc_sel_wg;
mcif2img_dat_rd_rsp_valid = rsp_mc_out_pvld & mc_sel_img;
```

response valid 只发给当前被 `mc_sel_*` 选中的 engine。

### 4.4 payload 分发

```verilog
mcif2dc_dat_rd_rsp_pd  = {514 {mc_sel_dc}}  & rsp_mc_out_pd;
mcif2wg_dat_rd_rsp_pd  = {514 {mc_sel_wg}}  & rsp_mc_out_pd;
mcif2img_dat_rd_rsp_pd = {514 {mc_sel_img}} & rsp_mc_out_pd;
```

response packet 是 514 bit，通常为：

```text
pd[511:0]   = read data
pd[513:512] = mask
```

本模块不解析 mask/data，只按 select 分发。

### 4.5 ready 反选

```verilog
rsp_mc_out_prdy = (mc_sel_dc  & mcif2dc_dat_rd_rsp_ready) |
                  (mc_sel_wg  & mcif2wg_dat_rd_rsp_ready) |
                  (mc_sel_img & mcif2img_dat_rd_rsp_ready);
```

外部 response pipe 的 ready 只取当前目标 engine 的 ready。

例如当前层为 DC：

```text
mc_sel_dc=1, mc_sel_wg=0, mc_sel_img=0

MCIF response
  -> mcif2dc_dat_rd_rsp_valid/pd
  -> ready 只看 mcif2dc_dat_rd_rsp_ready
```

## 5. 时延与吞吐

本模块在每个方向插入一级 pipe：

| 方向 | 路径 | 额外时延 |
|---|---|---|
| request | engine -> MCIF/CVIF | 1 拍 |
| response | MCIF/CVIF -> engine | 1 拍 |

无反压时仍可做到每拍一笔。它没有 credit 计数，也不限制 outstanding 数量；outstanding 管理由各 data engine 和外部 DMA 接口协议共同承担。

## 6. 容易误解的点

1. `dma_mux` 不是仲裁器。  
   它依赖 DC/WG/IMG 互斥，valid/payload 是 OR 合并。

2. `mc_sel_*` / `cv_sel_*` 不是 request tag FIFO。  
   它们只记录当前接口属于哪个 engine，适用于同层单 engine 活跃的场景。

3. ready 回传和 valid 相与不是仲裁。  
   只是避免未发请求的 engine 看到虚假的 ready。

4. 本模块不懂 CNN 模式。  
   DC/WG/IMG 谁活跃由上游各 engine 根据 `reg2dp_conv_mode`、`reg2dp_datain_format` 等配置决定。

5. 本模块不处理 data 内容。  
   79-bit request 和 514-bit response 的字段由上下游定义；mux 只保持 payload 原样转发。

