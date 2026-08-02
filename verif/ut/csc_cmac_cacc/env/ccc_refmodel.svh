// -----------------------------------------------------------------------------
// ccc_refmodel : 层配置 + 数据源 -> 期望 cacc2sdp beat 流
//
// ==== 分层 ====
//   1. conv 直算：out[k][h][w] = Σ_c dat[c][h][w] × wt[k][c]（R=S=1，longint 精确；
//      支持面约束保证 |Σ| < 2^33（int8）/ 2^47（int16），不触发 CACC 累加器
//      中途饱和——refmodel 内置 guard，越界即 fatal（说明配置越出支持面））
//   2. clip：逐行翻译 NV_NVDLA_CACC_CALC_int8.v / CALC_int16.v（见 clip32()），
//      产出 32b 最终值 + sat 标志；Σsat = 期望 D_OUT_SATURATION
//   3. beat 流（T1 实测校准后固化，校准结论见下）
//
// ==== beat 序校准结论（T1 图样+随机实测钉死 2026-08-02，回归合同）====
//   校准过程：图样 1（dat=1/wt=k+1）定位权重流格式与 kernel 映射；图样 2
//   （单位阵）钉死 beat 内字节序；随机 T1 全比对背书。权重流格式结论见
//   ccc_layer_cfg.svh wt_stream_byte 头注（C 轮 64 通道 × kernel-slot beat）。
//   - 输出像素按光栅序：p = h*Wo + w（w 最快），逐像素交付；
//   - int16（is_x1）：每像素 1 beat，lane l = kernel l（l≥K 补 32'h0——
//     calc_fout 无效 cell 门控为 0，dbuf 全 512b 实写）；
//   - int8（is_x2）：每像素 2 beat：beat0 lane l = kernel l（0-15），
//     beat1 lane l = kernel 16+l（16-31；K≤16 时 beat1 全 0 仍交付——
//     dlv_push_size 恒 2，delivery_ctrl.v:3038）；
//   - pd[512]=0 恒（batch_end 硬拴 0）；pd[513]=1 仅最末 beat。
// -----------------------------------------------------------------------------
`ifndef CCC_REFMODEL_SVH
`define CCC_REFMODEL_SVH

class ccc_refmodel extends uvm_object;

  ccc_layer_cfg cfg;

  bit [513:0] exp_beats [$];   // 期望 beat 流（含 layer_end 位）
  int unsigned exp_sat_count;  // 期望饱和事件数（仅有效 kernel lane 计入）

  `uvm_object_utils(ccc_refmodel)

  function new(string name = "ccc_refmodel");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // clip32 : CALC_int8/int16 最终出口逐行翻译（两精度共用，宽度参数化）
  //   acc     : 精确累加和（guard 已保证在 34/48b 饱和界内）
  //   t       : cfg_truncate
  //   is_int8 : 1 -> 34b 通路（CALC_int8.v），0 -> 48b（CALC_int16.v）
  //   返回 {sat, data32}
  //   对照行号（CALC_int8.v，int16 同构仅宽度不同）：
  //     :187 i_pre_sft_pd = sat_pd
  //     :188 {sft_pd, guide, stick[14:0]} = $signed({pre,16'b0}) >>> t
  //     :193 point5 = guide & (~sign | |stick)
  //     :189 need_sat = (sign & ~&sft[32:31]) | (~sign & |sft[32:31])
  //                     | (~sign & &{sft[30:0], point5})     （int16: [46:31]）
  //     :192/:194/:196 final = need_sat ? ±max : sft[31:0] + point5
  // ---------------------------------------------------------------------------
  function bit [32:0] clip32(longint acc, int unsigned t, bit is_int8);
    bit sign;
    bit [47:0] sft_pd;   // 移位后主体（int8 有效 34b / int16 48b）
    bit guide;
    bit [14:0] stick;
    bit point5, need_sat;
    bit [31:0] pos, fin;
    bit sat_hi;          // 高位溢出检查项（int8: sft[32:31]，int16: sft[46:31]）
    bit sat_hi_all1;

    if (is_int8) begin
      if (acc > 64'sd8589934591 || acc < -64'sd8589934592)   // ±2^33
        `uvm_fatal(get_type_name(), $sformatf("acc %0d exceeds int8 34b path (support contract)", acc))
      sign = acc[33];
      begin // 显式 50 位有符号移位（对应 RTL {pre_sft,16'b0} 的 50b 语境）
        bit signed [49:0] e50;
        e50 = {acc[33:0], 16'b0};
        e50 = e50 >>> t;
        sft_pd = {14'b0, e50[49:16]};
        guide  = e50[15];
        stick  = e50[14:0];
      end
      sat_hi      = |sft_pd[32:31];
      sat_hi_all1 = &sft_pd[32:31];
    end
    else begin
      if (acc > 64'sd140737488355327 || acc < -64'sd140737488355328) // ±2^47
        `uvm_fatal(get_type_name(), $sformatf("acc %0d exceeds int16 48b path (support contract)", acc))
      sign = acc[47];
      begin
        bit signed [63:0] e64;
        e64 = {acc[47:0], 16'b0};
        e64 = e64 >>> t;
        sft_pd = e64[63:16];
        guide  = e64[15];
        stick  = e64[14:0];
      end
      sat_hi      = |sft_pd[46:31];
      sat_hi_all1 = &sft_pd[46:31];
    end

    point5   = guide & (~sign | (|stick));
    need_sat = (sign & ~sat_hi_all1) | (~sign & sat_hi) |
               (~sign & (&{sft_pd[30:0], point5}));
    pos = sft_pd[31:0] + point5;
    fin = need_sat ? (sign ? 32'h8000_0000 : 32'h7FFF_FFFF) : pos;
    return {need_sat, fin};
  endfunction

  // ---------------------------------------------------------------------------
  function void build(ccc_layer_cfg cfg_i);
    longint acc;
    bit [32:0] cr;
    bit [31:0] res [];    // [k*out_h*out_w + h*out_w + w]
    int unsigned wo, ho, kk, bpp, nbeats, bi;
    bit [513:0] beat;

    cfg = cfg_i;
    exp_beats.delete();
    exp_sat_count = 0;

    wo = cfg.out_w(); ho = cfg.out_h(); kk = cfg.kernels;
    res = new[kk * ho * wo];

    // 1+2. conv 直算 + clip
    for (int unsigned k = 0; k < kk; k++)
      for (int unsigned h = 0; h < ho; h++)
        for (int unsigned w = 0; w < wo; w++) begin
          acc = 0;
          for (int unsigned c = 0; c < cfg.channel; c++)
            acc += longint'(cfg.dat_of(c, h, w)) * longint'(cfg.wt_of(k, c));
          cr = clip32(acc, cfg.clip_truncate, cfg.is_int8);
          if (cr[32]) exp_sat_count++;
          res[(k * ho + h) * wo + w] = cr[31:0];
        end

    // 3. beat 流（校准结论固化：光栅像素序 × K 组内 lane=kernel 序）
    bpp    = cfg.beats_per_pixel();
    nbeats = cfg.total_beats();
    bi     = 0;
    for (int unsigned h = 0; h < ho; h++)
      for (int unsigned w = 0; w < wo; w++)
        for (int unsigned b = 0; b < bpp; b++) begin
          beat = '0;
          for (int unsigned l = 0; l < 16; l++) begin
            int unsigned k = b * 16 + l;
            if (k < kk)
              beat[l*32 +: 32] = res[(k * ho + h) * wo + w];
          end
          beat[512] = 1'b0;                       // batch_end 硬拴 0
          beat[513] = (bi == nbeats - 1);         // layer_end
          exp_beats.push_back(beat);
          bi++;
        end

    `uvm_info(get_type_name(),
              $sformatf("built: %0d beats, exp_sat=%0d [%s]",
                        exp_beats.size(), exp_sat_count, cfg.convert2string()),
              UVM_LOW)
  endfunction

endclass : ccc_refmodel

`endif // CCC_REFMODEL_SVH
