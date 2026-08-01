// -----------------------------------------------------------------------------
// cdma_layer_cfg : 一层 DC 卷积取数配置（refmodel/seq/scoreboard 共用事实源）
//   Wave2 支持面（refmodel 合同，越界 randomize 失败 / check_supported() fatal）：
//     - DC feature（conv_mode=0、datain_format=0）、非压缩权重、cvt bypass
//     - in_precision == proc_precision（int8/int16，is_data_normal）
//     - batches=1、无 padding（dc 通路本就无 pad）
//     - Csurf 偶数任意 W；Csurf==1 要求 W 为偶数（避开 mask=4'h1 半 atom 半拍，
//       cvt 部分写行为 Wave3 再建模）；Csurf 奇数(>1) 不支持
//     - line_packed=1 时要求 line_stride == W*32（RTL 按 grain 连续取数）
//     - 权重每 kernel group 字节数须 128B 对齐（int16: bpk*16 / int8: bpk*32，
//       避免 wt_updt entries 每组 >>1 的舍入差）
//   寄存器编码注意（均已 RTL 实证）：
//     - D_DATAIN_SIZE_*/D_WEIGHT_SIZE_* 等字段 0-based（写 值-1）
//     - D_ENTRY_PER_SLICE / D_FETCH_GRAIN 也是 0-based（dc.v data_entries_w =
//       reg2dp_entries+1、fetch_grain_w = reg2dp_grains+1）
//     - 地址/步长寄存器低 5 位（WEIGHT_BYTES 低 7 位）恒 0，写字节值
//   约束里全部用显式派生 rand 变量（csurf_r/eps_r），不在约束中调成员函数
//   （LRM：约束内函数引用的 rand 成员按状态变量求值，会失效）
// -----------------------------------------------------------------------------
`ifndef CDMA_LAYER_CFG_SVH
`define CDMA_LAYER_CFG_SVH

class cdma_layer_cfg extends uvm_object;

  // ---- 数据面 ----
  rand bit          is_int8;      // 0=int16 1=int8（in==proc）
  rand int unsigned width;        // W：每行 atom（元素位置）数
  rand int unsigned height;       // H：slice 数
  rand int unsigned channel;      // C：通道数
  rand bit          dat_ram_mc;   // 1=MC 0=CV
  rand bit [63:0]   dat_addr;     // 32B 对齐字节地址
  rand int unsigned line_stride;  // 字节，32B 倍数
  rand int unsigned surf_stride;  // 字节，32B 倍数
  rand bit          line_packed;
  rand int unsigned grain;        // fetch_grain（slice 数；line_packed=0 时恒 1）
  rand int unsigned data_bank;    // 寄存器值 = bank 数-1
  // ---- 权重面 ----
  rand bit          wt_ram_mc;
  rand bit [63:0]   wt_addr;
  rand int unsigned bpk;          // byte_per_kernel（字节）
  rand int unsigned kernels;      // K
  rand int unsigned weight_bank;  // 寄存器值 = bank 数-1

  // ---- 派生（约束内可用）----
  rand int unsigned csurf_r;      // 32B 通道面数
  rand int unsigned eps_r;        // 一 slice 实际 entry 足迹
  rand int unsigned kpg_r;        // kernels per group

  bit stall_ok = 1'b0;            // T5：允许 dat 足迹超 bank 容量（靠 CSC 释放推进）

  `uvm_object_utils(cdma_layer_cfg)

  function new(string name = "cdma_layer_cfg");
    super.new(name);
  endfunction

  constraint derive_c {
    csurf_r == (is_int8 ? (channel + 31) / 32 : (channel + 15) / 16);
    eps_r   == (csurf_r / 4) * width
               + ((csurf_r % 4 == 2) ? (width + 1) / 2 :
                  (csurf_r % 4 == 1) ? (width + 3) / 4 : 0);
    kpg_r   == (is_int8 ? 32 : 16);
  }

  constraint geom_c {
    width  inside {[1:16]};
    height inside {[1:8]};
    if (is_int8) { channel inside {32, 64, 128, 256}; }  // csurf 1/2/4/8
    else         { channel inside {16, 32, 64, 128}; }
    (csurf_r == 1) -> (width % 2 == 0);
  }
  constraint stride_c {
    line_stride % 32 == 0;
    line_packed  -> line_stride == width * 32;
    !line_packed -> (line_stride >= width * 32 && line_stride <= width * 32 + 256);
    surf_stride == height * line_stride; // 面间紧凑，足迹不重叠
    line_packed dist {1 := 3, 0 := 1};
    grain inside {[1:4]};
    !line_packed -> grain == 1;
    grain <= height;
  }
  constraint addr_c {
    dat_addr[4:0] == 0;
    dat_addr inside {[64'h4000 : 64'h4_0000]};
    wt_addr[4:0] == 0;
    wt_addr inside {[64'h10_0000 : 64'h11_0000]};
  }
  constraint bank_c {
    data_bank inside {[0:3]};
    weight_bank inside {[0:2]};
    // 层内不等 CSC 释放，dat/wt 足迹必须整层装得下
    height * eps_r <= (data_bank + 1) * 256;
    (bpk * kernels) / 128 <= (weight_bank + 1) * 256;
  }
  constraint wt_c {
    kernels inside {[1:64]};
    bpk inside {[16:256]};
    (bpk * kernels) % 128 == 0;              // 总量 128B 对齐（D_WEIGHT_BYTES 粒度）
    (bpk * kpg_r) % 128 == 0;                // 每满组 128B 对齐（记账无舍入）
    ((kernels % kpg_r) == 0) || ((bpk * (kernels % kpg_r)) % 128 == 0); // 尾组
    !is_int8 -> (bpk % 2 == 0);
  }

  // ---- 派生量（randomize 后使用）----
  function int unsigned csurf();
    return is_int8 ? (channel + 31) / 32 : (channel + 15) / 16;
  endfunction
  function int unsigned eps();
    int unsigned p = csurf() / 4;
    int unsigned r = csurf() % 4;
    return p * width + (r == 2 ? (width + 1) / 2 : (r == 1 ? (width + 3) / 4 : 0));
  endfunction
  function int unsigned dat_entries_total(); return height * eps(); endfunction
  function int unsigned wt_bytes();          return bpk * kernels; endfunction
  function int unsigned wt_entries_total();  return wt_bytes() / 128; endfunction
  function int unsigned kernels_per_group(); return is_int8 ? 32 : 16; endfunction

  function void post_randomize();
    check_supported();
  endfunction

  function void check_supported();
    if (csurf() > 1 && csurf() % 2 != 0)
      `uvm_fatal("cdma_layer_cfg", $sformatf("unsupported odd csurf=%0d", csurf()))
    if (csurf() == 1 && width % 2 != 0)
      `uvm_fatal("cdma_layer_cfg", "csurf==1 requires even width")
    if (line_packed && line_stride != width * 32)
      `uvm_fatal("cdma_layer_cfg", "line_packed requires line_stride==W*32")
    if (wt_bytes() % 128 != 0)
      `uvm_fatal("cdma_layer_cfg", "wt_bytes must be 128B aligned")
    if (!stall_ok && dat_entries_total() > (data_bank + 1) * 256)
      `uvm_fatal("cdma_layer_cfg", "dat footprint exceeds data banks")
    if (stall_ok && dat_entries_total() >= (data_bank + 1) * 512)
      `uvm_fatal("cdma_layer_cfg", "stall footprint must stay < 2x region (RTL 单次回绕减法)")
    if (wt_entries_total() > (weight_bank + 1) * 256)
      `uvm_fatal("cdma_layer_cfg", "wt footprint exceeds weight banks")
    if (data_bank + 1 + weight_bank + 1 > 16)
      `uvm_fatal("cdma_layer_cfg", "data+weight banks exceed 16")
  endfunction

  virtual function string convert2string();
    return $sformatf("%s W=%0d H=%0d C=%0d(csurf=%0d) eps=%0d dat@0x%0h %s ls=%0d ss=%0d lp=%0b g=%0d dbank=%0d | wt K=%0d bpk=%0d @0x%0h %s wbank=%0d",
                     is_int8 ? "int8" : "int16", width, height, channel, csurf(), eps(),
                     dat_addr, dat_ram_mc ? "MC" : "CV", line_stride, surf_stride,
                     line_packed, grain, data_bank,
                     kernels, bpk, wt_addr, wt_ram_mc ? "MC" : "CV", weight_bank);
  endfunction

endclass : cdma_layer_cfg

`endif // CDMA_LAYER_CFG_SVH
