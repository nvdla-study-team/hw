# NV_NVDLA_CDMA_shared_buffer

源码：`vmod/nvdla/cdma/NV_NVDLA_CDMA_shared_buffer.v`

## 1. 模块定位

`NV_NVDLA_CDMA_shared_buffer` 是 CDMA data 侧三个 engine 共用的内部临时 RAM。

它位于：

```text
u_dc/u_wg/u_img response 整理逻辑
  -> NV_NVDLA_CDMA_shared_buffer
  -> u_dc/u_wg/u_img 再读出
  -> u_cvt
```

它不是最终 CBUF，也不和 CSC 直接交互。它的作用是给 DC/WG/IMG 在 DMA response 和 CVT 输出之间提供临时缓存、重排空间。

## 2. 物理组织

模块实例化 16 个 RAM：

```verilog
nv_ram_rws_16x256 u_shared_buffer_00
...
nv_ram_rws_16x256 u_shared_buffer_15
```

每个 RAM：

```text
深度 16
宽度 256 bit
```

总容量：

```text
16 RAM * 16 entry * 256 bit = 65536 bit = 8KB
```

地址宽度是 8 bit。地址切分为：

```text
addr[7:4] = RAM bank select
addr[3:0] = RAM entry select
```

DC/IMG 的 bank select 直接取 `[7:4]`：

```verilog
dc2sbuf_p0_wr_bsel  = dc2sbuf_p0_wr_addr[7:4];
img2sbuf_p0_wr_bsel = img2sbuf_p0_wr_addr[7:4];
```

WG 读侧特殊，部分 bank select 取 `[7:6]`，因为 WG 按自己的 tile/line 组织访问 shared buffer。

## 3. 端口模型

每个 data engine 都有两套 256-bit 写口和两套 256-bit 读口：

```text
dc2sbuf_p0/p1_wr_*
dc2sbuf_p0/p1_rd_*

wg2sbuf_p0/p1_wr_*
wg2sbuf_p0/p1_rd_*

img2sbuf_p0/p1_wr_*
img2sbuf_p0/p1_rd_*
```

但这不是三套独立 RAM。三路 engine 复用同一组 16 个 RAM。

设计前提仍然是：

```text
DC/WG/IMG 同层互斥
```

所以任意时刻只有一个 engine 合法访问 shared_buffer。

## 4. 写路径

写路径逻辑本质是：

```text
来自 DC/WG/IMG 的 p0/p1 写请求
  -> 按 addr[7:4] 解码到 16 个 RAM
  -> 每个 RAM 只有一个实际 we/wa/wdat
```

以 DC 为例：

```text
dc2sbuf_p0_wr_addr[7:4] 选择 RAM
dc2sbuf_p0_wr_addr[3:0] 作为该 RAM 写地址
dc2sbuf_p0_wr_data[255:0] 写入
```

p0 和 p1 可以同拍写不同 RAM，但不能写同一个 RAM。RTL 有断言保护：

```verilog
dc2sbuf_p0_wr_en & dc2sbuf_p1_wr_en &
(dc2sbuf_p0_wr_bsel == dc2sbuf_p1_wr_bsel)
```

WG/IMG 同理。

## 5. 读路径

读路径和写路径对称：

```text
engine p0/p1 rd addr
  -> bank select
  -> RAM read enable/address
  -> 读出 256-bit
  -> mux 到对应 engine 的 rd_data
```

所有 engine 的读数据最终接同一组内部输出寄存器：

```verilog
dc2sbuf_p0_rd_data  = sbuf_p0_rdat_d2;
wg2sbuf_p0_rd_data  = sbuf_p0_rdat_d2;
img2sbuf_p0_rd_data = sbuf_p0_rdat_d2;

dc2sbuf_p1_rd_data  = sbuf_p1_rdat_d2;
wg2sbuf_p1_rd_data  = sbuf_p1_rdat_d2;
img2sbuf_p1_rd_data = sbuf_p1_rdat_d2;
```

这看起来像“数据广播给三家”，但因为三家互斥，只有当前活跃 engine 会使用返回数据。

## 6. 为什么需要 shared_buffer

外部 DMA response 是按内存 burst 返回的，而 CVT/CBUF 希望看到的是按 CBUF entry、slice、channel 组织好的数据。DC/WG/IMG 需要临时落地、重排、拼接。

shared_buffer 提供的是一个中间工作区：

```text
DMA response 顺序
  -> 写 shared_buffer
  -> 按卷积/CBUF 所需顺序读出
  -> 送 CVT
```

它尤其用于：

- DC feature surface 的 channel/slice 重排；
- WG Winograd tile 数据组织；
- IMG pixel unpack/pack 后的临时缓冲。

## 7. 冲突约束

模块内部没有仲裁器，靠上游保证访问合法，并用断言兜底。

主要断言：

- DC/WG/IMG 不能多路同时写 shared_buffer；
- DC/WG/IMG 不能多路同时读 shared_buffer；
- 同一 engine 的 p0/p1 不能同拍写同一个 RAM bank；
- 同一 engine 的 p0/p1 不能同拍读同一个 RAM bank；
- 每个 RAM 不允许同拍读写同一地址。

例如：

```verilog
nv_assert_never(..., "multiple write to shared buffer", ...);
nv_assert_never(..., "multiple read to shared buffer", ...);
nv_assert_never(..., "Error! shared ram XX read and write hazard!", ...);
```

## 8. 容易误解的点

1. shared_buffer 不是 CBUF。它是 CDMA 内部小 RAM，容量约 8KB。
2. 三个 engine 都有端口名，但不是三份存储；它们共享同一组 RAM。
3. 模块本身不仲裁，依赖 DC/WG/IMG 互斥。
4. 输出 `*_rd_data` 广播给三路 engine 是安全的，因为只有当前活跃 engine 会消费。
5. p0/p1 是为了并行搬 2 个 256-bit 半片，不等于 CBUF 的 1024-bit entry。

