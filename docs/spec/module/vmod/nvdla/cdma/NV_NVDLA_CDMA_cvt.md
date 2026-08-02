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

## 5. 数值预处理和 HLS cell

### 5.1 这一级为什么存在

外存中的 activation 精度和数值尺度，不一定等于本层 CMAC 使用的处理精度和尺度。
例如图像输入可能是无符号像素，量化网络的 activation 可能带 zero point，而乘法阵列要求
输入已经变成统一的有符号 INT8/INT16 或 FP16 表示。因此数据进入 CBUF 前，需要完成：

```text
外存/图像输入的数值域
    -> 去均值或去量化偏置
    -> 调整数值尺度
    -> 压回目标位宽
    -> 以 proc_precision 格式写入 CBUF
```

这样 CSC 从 CBUF 取出的数已经处于 CMAC 的处理精度；CSC 只负责按卷积窗口和通道组织
Data/Weight，不再负责逐元素量化换算。

CVT 使用的层配置为：

```verilog
reg2dp_in_precision       // 外存输入元素格式
reg2dp_proc_precision     // CBUF/CMAC处理格式
reg2dp_cvt_en             // 1: 经过cell；0: bypass
reg2dp_cvt_offset[15:0]   // 每个元素要减去的偏置
reg2dp_cvt_scale[15:0]    // 相减后乘的定点系数
reg2dp_cvt_truncate[5:0]  // 乘法结果算术右移位数
```

精度编码是：

```text
2'b00 = INT8
2'b01 = INT16
2'b10 = FP16
```

这些配置在一层启动时锁存，并复制给 64 个并行
`NV_NVDLA_CDMA_CVT_cell`。64 个 cell 的意义是同拍处理最多 64 个元素，不是做 64 次
卷积乘法；这里的乘法只是在调整 activation 的数值尺度。

### 5.2 整数输入的准确算法

HLS 行为源 `cmod/hls/cdma_libs/cdma_cvt.cpp` 给出的整数路径是：

```text
sub = x - alu_operand
mul = sub * scale
shifted = arithmetic_shift_right(mul, truncate)
out = convert_or_saturate(shifted, proc_precision)
```

常用简写为：

```text
y = SAT_proc_precision(((x - offset_or_mean) * scale) >> truncate)
```

每一步的 CNN/量化含义如下：

1. `x - offset_or_mean`

   - 普通 DC/WG feature 路径使用 `reg2dp_cvt_offset`；
   - IMG 路径在 `cvt_wr_mean=1` 时改用 `img2cvt_mn_wr_data` 中对应元素的 mean；
   - 它可以完成图像去均值，也可以把带 zero point 的量化值平移回以 0 为中心的有符号域。

2. `* scale`

   量化整数代表的真实值近似为 `real = integer * quant_scale`。输入张量和 CMAC 所需
   张量尺度不同时，需要乘一个比例系数把整数换到目标量化单位。硬件使用整数乘法实现，
   不在每个元素上做昂贵的浮点除法。

3. `>> truncate`

   乘法会增加位宽，`scale` 通常又被软件表示成带隐含小数位的定点整数。右移既去掉
   定点小数位，也控制结果幅度。它是算术右移，不是除完以后再保留完整小数，因此这里
   可能产生量化误差。

4. `SAT`

   最后按处理精度限幅。INT8 输出限制到有符号 8-bit 范围，INT16 输出限制到有符号
   16-bit 范围，避免简单截掉高位造成正数回绕成负数。

例如：

```text
x = 20, offset = 3, scale = 8, truncate = 2

sub     = 20 - 3 = 17
mul     = 17 * 8 = 136
shifted = 136 >> 2 = 34
INT8输出 = 34
```

如果结果为 300，INT8 路径不会保留低 8 bit 变成 44，而是饱和为 127。

### 5.3 三种输入精度分别怎样处理

| `in_precision` | `proc_precision` | cell 内行为 | 输出打包 |
|---|---|---|---|
| INT8 | INT8 | 符号/无符号扩展后执行减、乘、右移，饱和为 INT8 | 每个 cell 取低 8 bit |
| INT8 | INT16 | 执行同一整数公式，饱和为 INT16 | 每元素占 16 bit，数据宽度 expand |
| INT8 | FP16 | 先按整数公式得到 17-bit 整数，再执行 integer-to-FP16 | 每元素占 16 bit |
| INT16 | INT8 | 执行整数公式，饱和为 INT8 | 每元素缩为 8 bit，数据宽度 shrink |
| INT16 | INT16 | 执行整数公式，饱和为 INT16 | 每元素占 16 bit |
| INT16 | FP16 | 先按整数公式得到 17-bit 整数，再执行 integer-to-FP16 | 每元素占 16 bit |
| FP16 | FP16 | cell 直接传递输入 FP16 bit pattern | 每元素占 16 bit |

RTL 明确禁止 FP16 输入转换成 INT8/INT16：

```verilog
(cfg_in_precision == 2'h2) && (cfg_proc_precision != 2'h2)
```

对应断言报错 `invalid precision transform`。因此必须特别注意：

> FP16 输入在这个 CVT cell 中不会先转成整数，也不会执行整数
> `offset/scale/truncate` 链；它只能保持 FP16 输出。FP16 的 NaN/Inf 检测和可选
> NaN-to-zero 由 cell 外的 CVT 顶层逻辑处理。

### 5.4 offset 和 mean 如何二选一

cell 有两个逐元素输入：

```text
op0[16:0] = activation x，INT8/INT16时先扩展到17 bit
op1[15:0] = 要减去的数
```

`op1` 的来源为：

```verilog
oprand_1_N_ori = cvt_wr_mean_d1
               ? cvt_wr_mean_data_d1[对应lane]
               : cfg_offset[对应lane];
```

所以并不是先减 mean 再减 offset，而是二选一：

```text
IMG mean拍：x - per-element mean
其他数据拍：x - D_CVT_OFFSET
```

`cvt_wr_uint` 决定整数输入是否按无符号数扩展。DC/WG 路径有断言禁止设置 uint，
主要是 IMG 原始像素路径会使用无符号解释。

### 5.5 bypass 和转换延迟

当 `reg2dp_cvt_en=0` 时，输出选择 bypass 数据，不经过 64 个转换 cell：

```verilog
cvt_out_data_mix = cfg_cvt_en[5]
                  ? cvt_data_cell_out
                  : {cvt_data_bypass_hi, cvt_data_bypass_lo};
```

bypass 只适用于输入精度和处理精度相同；RTL 对“关闭 CVT 但精度发生变化”设置了断言。

两条路径延迟不同：

```text
bypass路径：控制/data对齐到 d1
cell路径：64个HLS cell固定约5拍，对齐到 d5
```

末级按 `cvt_en` 选择已经对齐的输出，因此地址、`hsel`、valid 和数据保持同拍。

### 5.6 数值预处理不等于卷积顺序重组

CVT 的重排只服务于精度宽度和 CBUF entry 打包，例如 INT8->INT16 时一个 8-bit 元素
扩成一个 16-bit 元素，INT16->INT8 时将两个时段的结果攒成紧凑的 8-bit 数据。它不会：

- 根据 `R/S` 选择卷积窗口；
- 因窗口重叠而复制 activation；
- 决定当前 Data 与哪个 kernel 的 Weight 相乘；
- 生成送入 CMAC A/B 阵列的时序。

这些计算顺序由后级 CSC 完成。CVT 的边界可以概括为：

```text
shared_buffer/DC/IMG/WG
    -> CVT：逐元素数值预处理 + CBUF位宽打包
    -> CBUF：保存内部feature格式
    -> CSC：按卷积窗口/通道/CMAC lane顺序读取和组织
    -> CMAC：Data * Weight
```

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
