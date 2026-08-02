// -----------------------------------------------------------------------------
// ccc_layer_cfg : 一层 DC 卷积（csc+cmac+cacc 链）配置 + 数据源 + cbuf 打包
//   （refmodel/seq/scoreboard 共用事实源，范式沿用 cdma_layer_cfg）
//
// ==== Wave2 支持面（refmodel 合同，越界 randomize 失败 / check_supported fatal）====
//   - DC 直卷积（conv_mode=0）、feature 输入（datain_format=0）、非压缩权重
//   - int8 / int16，in_precision == proc_precision
//   - 单 batch、stride=1、无 pad、无 dilation、y_extension=0
//   - R = S = 1（1x1 卷积核）：权重流内序退化为纯 channel 序，规避
//     [R][S][C] 摆放次序的未证明假设；R/S>1 属 T4 几何专项（延后）
//   - K：int16 ≤16（单 kernel 组）、int8 ≤32（单组，17-32 即 a/b 双半）；
//     int16 K>16 需要 sg 的 kernel 组迭代，延后
//   - C 通道数：int8 32 的倍数、int16 16 的倍数（整 surface；尾 atom mask 由
//     C 非整组变体覆盖——本版按整 surface，尾通道 mask 走 T5 的 K 尾）
//   - CACC 输出恒 packed 线性一种配置：dataout_addr/line_stride/surf_stride 全 0、
//     line_packed=surf_packed=1（delivery 只消费 bit0 奇偶，F-OUT-5）
//   - 累加不触发 34b/48b 中途饱和（|Σ| < 2^33 / 2^47，由幅度约束保证，refmodel
//     内置 guard 检查）；最终 32b 截断/饱和/舍入按 CALC 逐行翻译精确建模
//
// ==== 寄存器编码注意（RTL 实证）====
//   - datain/dataout/weight 几何字段 0-based（写 值-1）；D_ATOMICS = Wo*Ho-1；
//     D_ENTRY_PER_SLICE = eps-1（dl.v:2083 +1）；D_RELEASE = H-1（sg.v:2623 +1）
//   - D_WEIGHT_BYTES 写字节数（低 7 位恒 0，字段值 = bytes/128 = wt entry 数，
//     wl.v:1852 直接当 entry 计数消费）
//   - 约束内不调成员函数（LRM：约束中函数引用 rand 成员按状态变量求值）；
//     Wave1 另一坑：randomize with 里引用的名字先解析到 item 自身域——地址/
//     派生值一律先算入本地变量再进约束（ccc_csb_base_seq.svh 实例）
//
// ==== cbuf 镜像打包（与 cdma_cbuf_refmodel 同一规则，规则只存在一处）====
//   dat：docs/spec/units/cdma-cbuf.md §4.4 三形态（本文件 pack_dat()），
//   wt：kernel-major 线性字节流按 64B 半 entry 折行（pack_wt()）
// -----------------------------------------------------------------------------
`ifndef CCC_LAYER_CFG_SVH
`define CCC_LAYER_CFG_SVH

class ccc_layer_cfg extends uvm_object;

  // ---- 几何 ----
  rand bit          is_int8;      // 0=int16 1=int8
  rand int unsigned width;        // 输入 W（R=S=1 下 = 输出 W）
  rand int unsigned height;       // 输入 H
  rand int unsigned channel;      // 输入 C
  rand int unsigned kernels;      // K（输出通道数）
  rand int unsigned clip_truncate;// CACC D_CLIP_CFG [0:31]
  rand int unsigned data_bank;    // 寄存器值 = bank 数-1
  rand int unsigned weight_bank;

  // ---- 数据幅度旋钮（T2 边角覆盖用；默认全幅随机）----
  int dat_min = 0, dat_max = 0;   // 0/0 = 按精度全幅
  int wt_min  = 0, wt_max  = 0;
  // ---- 校准图样（T1 beat 序/映射定位用，+ccc_pattern= 选择；0=随机）----
  //   1: dat 全 1、wt[k][c]=k+1        -> out[k]=(k+1)*C，定位 kernel 映射
  //   2: dat[c]=c 低 8 位、wt[k][c]=δ(c==k) -> out[k]=dat 元素 k，定位通道序
  int unsigned pattern_mode = 0;

  // ---- 派生（约束内用显式 rand 变量）----
  rand int unsigned csurf_r;
  rand int unsigned eps_r;

  // ---- 数据源（randomize 后 gen_data() 填充）----
  int dat_elem [];                // [ (c*H + h)*W + w ]，有符号元素值
  int wt_elem  [];                // [ k*C + c ]（R=S=1：kernel 内纯 channel 序）

  `uvm_object_utils(ccc_layer_cfg)

  function new(string name = "ccc_layer_cfg");
    super.new(name);
  endfunction

  constraint derive_c {
    csurf_r == (is_int8 ? channel / 32 : channel / 16);
    eps_r   == (csurf_r / 4) * width
               + ((csurf_r % 4 == 2) ? (width + 1) / 2 :
                  (csurf_r % 4 == 1) ? (width + 3) / 4 : 0);
  }

  constraint geom_c {
    width  inside {[1:8]};
    height inside {[1:8]};
    if (is_int8) { channel inside {64, 128, 192, 256}; }
    else         { channel inside {64, 128, 192}; }
    (csurf_r == 1) -> (width % 2 == 0);          // 沿用 cdma 打包 c 形态约束
    (csurf_r > 1) -> (csurf_r % 2 == 0);         // 奇 csurf(>1) 尾单面不建模
    if (is_int8) { kernels inside {[1:32]}; }
    else         { kernels inside {[1:16]}; }
    clip_truncate inside {[0:16]};
  }

  constraint bank_c {
    data_bank inside {[0:3]};
    weight_bank inside {[0:2]};
    height * eps_r <= (data_bank + 1) * 256;             // 整层足迹装得下
    (kernels * channel * (is_int8 ? 1 : 2)) / 128 <= (weight_bank + 1) * 256;
    data_bank + 1 + weight_bank + 1 <= 16;
  }

  // ---- 派生量（randomize 后使用）----
  function int unsigned esize();       return is_int8 ? 1 : 2; endfunction
  function int unsigned cpa();         return is_int8 ? 32 : 16; endfunction // 通道/atom
  function int unsigned csurf();       return channel / cpa(); endfunction
  function int unsigned eps();
    int unsigned p = csurf() / 4, r = csurf() % 4;
    return p * width + (r == 2 ? (width + 1) / 2 : (r == 1 ? (width + 3) / 4 : 0));
  endfunction
  function int unsigned kbytes_pk();   return channel * esize(); endfunction // R=S=1
  // 权重流几何（T1 图样 1 实测校准，见 wt_stream_byte 头注）：
  // C 轮 = 64 通道；每轮 beat 数 = int16: K / int8: ceil(K/2)；beat 恒 128B
  function int unsigned c_rounds();    return channel / 64; endfunction
  function int unsigned beats_per_round();
    return is_int8 ? (kernels + 1) / 2 : kernels;
  endfunction
  function int unsigned wt_bytes();    return c_rounds() * beats_per_round() * 128; endfunction
  function int unsigned wt_entries();  return wt_bytes() / 128; endfunction
  function int unsigned out_w();       return width;  endfunction // R=S=1
  function int unsigned out_h();       return height; endfunction
  function int unsigned atomics();     return out_w() * out_h(); endfunction
  function int unsigned beats_per_pixel(); return is_int8 ? 2 : 1; endfunction
  function int unsigned total_beats(); return atomics() * beats_per_pixel(); endfunction
  function int unsigned wt_base_entry(); return (data_bank + 1) * 256; endfunction

  function int elem_min(bit is_wt);
    int m = is_wt ? wt_min : dat_min;
    if (m == 0 && (is_wt ? wt_max : dat_max) == 0)
      return is_int8 ? -128 : -32768;
    return m;
  endfunction
  function int elem_max(bit is_wt);
    int m = is_wt ? wt_max : dat_max;
    if (m == 0 && (is_wt ? wt_min : dat_min) == 0)
      return is_int8 ? 127 : 32767;
    return m;
  endfunction

  function void post_randomize();
    check_supported();
    gen_data();
  endfunction

  function void check_supported();
    if (channel % 64 != 0)
      `uvm_fatal("ccc_layer_cfg",
                 $sformatf("unsupported C=%0d (need 64 aligned: wt 流按 64 通道整轮打包)", channel))
    if (csurf() > 1 && csurf() % 2 != 0)
      `uvm_fatal("ccc_layer_cfg", $sformatf("unsupported odd csurf=%0d", csurf()))
    if (csurf() == 1 && width % 2 != 0)
      `uvm_fatal("ccc_layer_cfg", "csurf==1 requires even width")
    if (!is_int8 && kernels > 16)
      `uvm_fatal("ccc_layer_cfg", "int16 K>16 (multi kernel-group) unsupported in Wave2")
    if (is_int8 && kernels > 32)
      `uvm_fatal("ccc_layer_cfg", "int8 K>32 unsupported")
    if (height * eps() > (data_bank + 1) * 256)
      `uvm_fatal("ccc_layer_cfg", "dat footprint exceeds data banks")
    if (wt_entries() > (weight_bank + 1) * 256)
      `uvm_fatal("ccc_layer_cfg", "wt footprint exceeds weight banks")
    if (data_bank + 1 + weight_bank + 1 > 16)
      `uvm_fatal("ccc_layer_cfg", "data+weight banks exceed 16")
    // clip_truncate 全域 [0:31] 支持：refmodel 与 RTL 同宽移位（50b/64b），
    // t>16 时低位丢弃行为两边一致（T2 clip=31 实测）
    if (clip_truncate > 31)
      `uvm_fatal("ccc_layer_cfg", "clip_truncate is 5b [0:31]")
  endfunction

  // 数据填充（用 $urandom_range，可复现性由 UVM 种子链保证）
  function void gen_data();
    int lo, hi;
    dat_elem = new[channel * height * width];
    wt_elem  = new[kernels * channel];
    case (pattern_mode)
      1: begin // dat 全 1、wt=k+1
        foreach (dat_elem[i]) dat_elem[i] = 1;
        for (int unsigned k = 0; k < kernels; k++)
          for (int unsigned c = 0; c < channel; c++)
            wt_elem[k * channel + c] = k + 1;
      end
      2: begin // dat[c] = (c&63)+1（与 h/w 无关，int8 幅度安全）、wt=单位阵
        for (int unsigned c = 0; c < channel; c++)
          for (int unsigned h = 0; h < height; h++)
            for (int unsigned w = 0; w < width; w++)
              dat_elem[(c * height + h) * width + w] = (c & 63) + 1;
        foreach (wt_elem[i]) wt_elem[i] = 0;
        for (int unsigned k = 0; k < kernels; k++)
          wt_elem[k * channel + k] = 1;
      end
      default: begin
        lo = elem_min(0); hi = elem_max(0);
        foreach (dat_elem[i]) dat_elem[i] = $urandom_range(hi - lo, 0) + lo;
        lo = elem_min(1); hi = elem_max(1);
        foreach (wt_elem[i]) wt_elem[i] = $urandom_range(hi - lo, 0) + lo;
      end
    endcase
  endfunction

  function int dat_of(int unsigned c, int unsigned h, int unsigned w);
    return dat_elem[(c * height + h) * width + w];
  endfunction
  function int wt_of(int unsigned k, int unsigned c);
    return wt_elem[k * channel + c];
  endfunction

  // ---- atom（32B）内容：surface s、位置 (h,w) 的通道块 ----
  function bit [255:0] dat_atom(int unsigned s, int unsigned h, int unsigned w);
    bit [255:0] a = '0;
    if (is_int8) begin
      for (int i = 0; i < 32; i++) a[i*8 +: 8] = 8'(dat_of(s*32 + i, h, w));
    end
    else begin
      for (int i = 0; i < 16; i++) a[i*16 +: 16] = 16'(dat_of(s*16 + i, h, w));
    end
    return a;
  endfunction

  // ---- dat cbuf 打包（cdma-cbuf.md §4.4 三形态）----
  //   entry_base：本层起始 entry（同 bank 连续层 CSC 读指针环形前进不复位，
  //   = 前层足迹累计 % 区容量；PEND 清账层从 0 起——T2 实测踩坑后补）
  function void pack_dat(cbuf_model mdl, int unsigned entry_base = 0);
    int unsigned cs = csurf(), pairs = cs / 4, rem = cs % 4, ep = eps();
    int unsigned e_off, slot, region = (data_bank + 1) * 256;
    bit [1023:0] entry_mem [bit [11:0]];
    bit [11:0]   e;
    for (int unsigned h = 0; h < height; h++)
      for (int unsigned s = 0; s < cs; s++)
        for (int unsigned w = 0; w < width; w++) begin
          if (s < pairs * 4) begin            // a. 面四元组：C 主序
            e_off = (s / 4) * width + w;
            slot  = s % 4;
          end
          else if (rem == 2) begin            // b. 尾双面：2 像素 x 2 面
            e_off = pairs * width + (w >> 1);
            slot  = ((w & 1) << 1) | (s - pairs * 4);
          end
          else begin                          // c. 单面（cs==1）：4 像素
            e_off = w >> 2;
            slot  = w & 3;
          end
          e = 12'((entry_base + h * ep + e_off) % region);
          if (!entry_mem.exists(e)) entry_mem[e] = '0;
          entry_mem[e][slot*256 +: 256] = dat_atom(s, h, w);
        end
    foreach (entry_mem[k]) mdl.preload(k, entry_mem[k]);
  endfunction

  // ---- wt 流字节（T1 图样 1/2 实测校准的软件权重格式，回归合同）----
  //   外层 C 轮（64 通道/轮）、轮内 kernel-slot beat（128B/beat）：
  //   - int16：beat j = kernel j 的本轮 64 通道，2B LE 逐通道；
  //   - int8 ：beat j = kernel 2j 的本轮 64B + kernel 2j+1 的 64B（前后半拼接，
  //     K 奇数时末 beat 高 64B 补 0）；
  //   与"kernel-major bpk 裸流"不同——这是 wl 直接按 sel slot 流式消费的格式
  function bit [7:0] wt_stream_byte(int unsigned i);
    int unsigned ci   = i / (beats_per_round() * 128); // C 轮
    int unsigned r    = i % (beats_per_round() * 128);
    int unsigned beat = r / 128;
    int unsigned b    = r % 128;
    int unsigned k, c;
    if (is_int8) begin
      k = beat * 2 + (b >= 64);
      c = ci * 64 + (b % 64);
      if (k >= kernels) return 8'h0;       // K 奇数末 beat 高半补 0
      return 8'(wt_of(k, c));
    end
    else begin
      k = beat;
      c = ci * 64 + (b / 2);
      return 8'(wt_of(k, c) >> (8 * (b % 2)));
    end
  endfunction

  // entry_base：本层 wt 起始 entry（相对 weight 区起点；跨层环形累计，同 dat）
  function void pack_wt(cbuf_model mdl, int unsigned entry_base = 0);
    int unsigned halves = (wt_bytes() + 63) / 64;
    int unsigned region = (weight_bank + 1) * 256;
    bit [1023:0] entry_mem [bit [11:0]];
    bit [11:0]   e;
    for (int unsigned j = 0; j < halves; j++) begin
      e = 12'(wt_base_entry() + ((entry_base + j / 2) % region));
      if (!entry_mem.exists(e)) entry_mem[e] = '0;
      for (int unsigned i = 0; i < 64; i++)
        if (j*64 + i < wt_bytes())
          entry_mem[e][(j % 2)*512 + i*8 +: 8] = wt_stream_byte(j*64 + i);
    end
    foreach (entry_mem[k]) mdl.preload(k, entry_mem[k]);
  endfunction

  function void preload(cbuf_model mdl,
                        int unsigned dat_entry_base = 0,
                        int unsigned wt_entry_base = 0);
    mdl.clear();
    pack_dat(mdl, dat_entry_base);
    pack_wt(mdl, wt_entry_base);
    // 读址域检查旋钮：dat 落 [0,data_bank]、wt 落 [data_bank+1, +weight_bank+1]
    mdl.set_dat_banks(4'd0, 4'(data_bank));
    mdl.set_wt_banks(4'(data_bank + 1), 4'(data_bank + 1 + weight_bank));
  endfunction

  virtual function string convert2string();
    return $sformatf("%s W=%0d H=%0d C=%0d(csurf=%0d) eps=%0d K=%0d clip=%0d dbank=%0d wbank=%0d wt_entries=%0d beats=%0d",
                     is_int8 ? "int8" : "int16", width, height, channel, csurf(),
                     eps(), kernels, clip_truncate, data_bank, weight_bank,
                     wt_entries(), total_beats());
  endfunction

endclass : ccc_layer_cfg

`endif // CCC_LAYER_CFG_SVH
