# NV_NVDLA_CDMA_cvt

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_cvt.v`

## 1. 模块定位

`NV_NVDLA_CDMA_cvt` 是 CDMA data 侧写 CBUF 前的最后一级。

它汇合：

```text
dc2cvt_dat_wr_*
wg2cvt_dat_wr_*
img2cvt_dat_wr_*
```

输出：

```text
cdma2buf_dat_wr_*
```

也就是说，DC/WG/IMG 都不直接写 CBUF data 口，必须先经过 CVT。

CVT 的职责包括：

- DC/WG/IMG 三路输入选择；
- 数据精度转换和 truncate/offset/scale 处理；
- image mean/pad mask 相关处理；
- NaN/Inf 检测与计数；
- 输出 1024-bit CBUF data write packet；
- data CBUF flush。

## 2. 输入接口

DC/WG 输入是 512-bit 半 entry：

```verilog
dc2cvt_dat_wr_en
dc2cvt_dat_wr_addr[11:0]
dc2cvt_dat_wr_hsel
dc2cvt_dat_wr_data[511:0]

wg2cvt_dat_wr_en
wg2cvt_dat_wr_addr[11:0]
wg2cvt_dat_wr_hsel
wg2cvt_dat_wr_data[511:0]
```

IMG 输入是 1024-bit：

```verilog
img2cvt_dat_wr_en
img2cvt_dat_wr_addr[11:0]
img2cvt_dat_wr_hsel
img2cvt_dat_wr_data[1023:0]
img2cvt_mn_wr_data[1023:0]
img2cvt_dat_wr_pad_mask[127:0]
```

每路还有 12-bit info packet：

```verilog
dc2cvt_dat_wr_info_pd
wg2cvt_dat_wr_info_pd
img2cvt_dat_wr_info_pd
```

## 3. info packet

CVT 对 12-bit info packet 解包：

```verilog
cvt_wr_mask[3:0]      = cvt_wr_info_pd[3:0];
cvt_wr_interleave     = cvt_wr_info_pd[4];
cvt_wr_ext64          = cvt_wr_info_pd[5];
cvt_wr_ext128         = cvt_wr_info_pd[6];
cvt_wr_mean           = cvt_wr_info_pd[7];
cvt_wr_uint           = cvt_wr_info_pd[8];
cvt_wr_sub_h[2:0]     = cvt_wr_info_pd[11:9];
```

这些字段控制后续数据排列、扩展、mean 处理、mask 和输入符号解释。

## 4. 三路输入选择

CVT 假设 DC/WG/IMG 同层互斥，所以输入选择使用 valid 掩码 OR。

info 选择：

```verilog
cvt_wr_info_pd =
    ({12{dc2cvt_dat_wr_en}}  & dc2cvt_dat_wr_info_pd) |
    ({12{wg2cvt_dat_wr_en}}  & wg2cvt_dat_wr_info_pd) |
    ({12{img2cvt_dat_wr_en}} & img2cvt_dat_wr_info_pd);
```

地址选择：

```verilog
cvt_wr_addr =
    ({12{dc2cvt_dat_wr_en}}  & dc2cvt_dat_wr_addr) |
    ({12{wg2cvt_dat_wr_en}}  & wg2cvt_dat_wr_addr) |
    ({12{img2cvt_dat_wr_en}} & img2cvt_dat_wr_addr);
```

DC/WG 半 entry 数据先合并为 512-bit：

```verilog
cvt_wr_half_data =
    ({512{dc2cvt_dat_wr_en}} & dc2cvt_dat_wr_data) |
    ({512{wg2cvt_dat_wr_en}} & wg2cvt_dat_wr_data);
```

再和 IMG 的 1024-bit 数据合并：

```verilog
cvt_wr_data_ori =
    {512'b0, cvt_wr_half_data} |
    ({1024{img2cvt_dat_wr_en}} & img2cvt_dat_wr_data);
```

因此：

- DC/WG 输入天然是低 512-bit 半 entry；
- IMG 可以直接提供完整 1024-bit；
- `hsel` 决定最终写 CBUF 哪半边有效。

## 5. 精度转换和 HLS cell

CVT 根据寄存器配置工作：

```verilog
reg2dp_in_precision
reg2dp_proc_precision
reg2dp_cvt_en
reg2dp_cvt_truncate
reg2dp_cvt_offset
reg2dp_cvt_scale
reg2dp_nan_to_zero
reg2dp_pad_value
```

内部有 64 个转换 cell 输出：

```verilog
cellout_0 ... cellout_63
```

并通过 `nvdla_hls_clk` 时钟域运行。`slcg_hls_en` 是给顶层 SLCG 的 HLS cell 时钟使能。

从功能上看，这一级负责把输入 data 变成 CBUF 里后续 CSC/CMAC 期望的处理精度和排列格式。

## 6. NaN/Inf 处理

CVT 对 FP16 输入检测 exponent/mantissa：

```text
exp 全 1 且 mantissa 非 0 -> NaN
exp 全 1 且 mantissa 为 0 -> Inf
```

输出计数：

```verilog
dp2reg_nan_data_num[31:0]
dp2reg_inf_data_num[31:0]
```

如果 `reg2dp_nan_to_zero` 要求清 NaN，CVT 会用 mask 把 NaN lane 清零。

## 7. pad / mean 处理

IMG 侧有额外输入：

```verilog
img2cvt_mn_wr_data
img2cvt_dat_wr_pad_mask
```

`img2cvt_dat_wr_pad_mask` 只在 IMG valid 时生效：

```verilog
cvt_wr_pad_mask_vld = img2cvt_dat_wr_en;
cvt_wr_pad_mask = cvt_wr_pad_mask_vld ? img2cvt_dat_wr_pad_mask : 128'b0;
```

`reg2dp_pad_value` 提供 padding 填充值。`cvt_wr_mean` 和 `img2cvt_mn_wr_data` 用于 image mean 相关路径。

## 8. 输出到 CBUF

最终输出：

```verilog
assign cdma2buf_dat_wr_en   = cvt_out_vld_reg;
assign cdma2buf_dat_wr_addr = cvt_out_addr_reg;
assign cdma2buf_dat_wr_hsel = cvt_out_hsel_reg;
assign cdma2buf_dat_wr_data = {
    cvt_out_data_p7_reg,
    cvt_out_data_p6_reg,
    cvt_out_data_p5_reg,
    cvt_out_data_p4_reg,
    cvt_out_data_p3_reg,
    cvt_out_data_p2_reg,
    cvt_out_data_p1_reg,
    cvt_out_data_p0_reg
};
```

输出 data 是 1024 bit，由 8 个 128-bit 分片拼成。`hsel[1:0]` 是 CBUF data 写口的半 entry 写使能：

```text
hsel[0] -> low 512b
hsel[1] -> high 512b
```

## 9. data CBUF flush

CVT 内部有 data CBUF flush 计数：

```verilog
dat_cbuf_flush_idx
dat_cbuf_flush_vld_w = ~dat_cbuf_flush_idx[12];
dp2reg_dat_flush_done = dat_cbuf_flush_idx[12];
```

flush 和正常 CVT 输出不能同拍写：

```verilog
nv_assert_never(..., cvt_out_vld_bp & dat_cbuf_flush_vld_w);
```

这保证 data flush 写和正常 data 写不会在同一拍冲突。

## 10. 容易误解的点

1. CVT 是 data 侧唯一真正输出 `cdma2buf_dat_wr_*` 的模块。
2. DC/WG 给 CVT 的是 512-bit 半 entry；IMG 可以给 1024-bit。
3. CVT 不是简单 mux，它还做精度转换、pad/mean、NaN/Inf 统计。
4. `cdma2buf_dat_wr_hsel` 是 2-bit 半 entry enable，不是 weight 侧那种 1-bit column select。
5. flush 逻辑也在 CVT 内，flush 写与正常 CVT 输出互斥。

