// -----------------------------------------------------------------------------
// cdma_cbuf_refmodel : 由 DMA 内存镜像 + 层配置推期望 cbuf 内容 / DMA 足迹 / 记账
//
// ============ DC 数据 entry 打包规则（NV_NVDLA_CDMA_dc.v 实证推导，留档） ============
// 术语：atom=32B（int8 装 32 通道、int16 装 16 通道的一个像素位置）；
//       surface s=第 s 个 32B 通道面；Csurf=面数（int8:C/32、int16:C/16 上取整）；
//       entry=128B=4 个 256b slot（slot k 占 data[k*256 +: 256]）。
//
// 1) 取数环路（请求侧）：grain(若干 slice) -> [batch] -> 面组(2 面一组，
//    req_ch_mode=2，data_shrink 时 4) -> 组内两面按请求交替发（req_atm_sel），
//    每面每 grain 连续取 grain*W 个 atom，单笔请求 1~8 atom 且不跨 256B 边界
//    （首笔 size=8-addr[7:5]，dc.v req_atm_size_addr_limit）。
//    atom 地址 = dat_addr + y*line_stride + s*surf_stride + w*32。
//
// 2) 响应/打包环路（回填侧，嵌套 外->内 = grain -> batch -> 面组 -> slice -> w）：
//    sbuf 每面区按 {ch,奇偶,对号} 存 atom；读侧每步凑 512b 半 entry 送 cvt。
//    entry 索引 = wr_base + h*eps + entry_off（eps=D_ENTRY_PER_SLICE+1，
//    wr_base=status wr_idx，首层 0；到 (data_bank+1)*256 回绕）。
//    is_data_normal（in==proc 精度）三种形态（dc.v is_w_cnt_div* 与 hsel 逻辑）：
//    a. 面四元组（Csurf 的每 4 面，组对 q=s/4）：entry_off = q*W + w，
//       slot = s%4 —— 一个 entry = 同一像素 w 的 4 个连续面（C 主序打包），
//       低组(s%4<2)走 dc2cvt hsel=0（slot0/1）、高组走 hsel=1（slot2/3），
//       hsel 由面组计数器 rsp_ch_cnt[1] 决定；
//    b. 尾双面（Csurf%4==2 的最后两面，含 Csurf==2）：is_w_cnt_div2 生效，
//       entry_off = (Csurf/4)*W + w/2，slot = (w%2)*2 + 面奇偶 —— 一个 entry =
//       2 个连续像素 × 2 面，hsel=w[0]；W 为奇数时末 entry 只写 slot0/1；
//    c. 单面（Csurf==1）：is_w_cnt_div4 生效，读侧每步取同面 2 个 atom，
//       entry_off = w/4，slot = w%4 —— 一个 entry = 4 个连续像素，hsel=w[1]；
//       W%4==2 时末 entry 只写 slot0/1（W 须为偶，奇数会出 mask=4'h1 部分
//       atom 写，Wave2 不支持）。
//    Csurf 为奇数(>1) 的尾单面走 rsp_ch_cnt 奇偶特例，Wave2 不建模。
//    注意（T2 实证）：b/c 形态 W 尾留半 entry 时，RTL 经 ext128 释放会把未占用
//    的高半也一起写（cdma2buf hsel=2'b11，内容为 cvt 流水线残留 don't-care）——
//    期望模型只登记有效 slot，比对也只看有效 slot。
//
// 3) 权重（非压缩）：字节流线性拷贝。DRAM [wt_addr, +bpk*K) 按 64B 切半 entry，
//    半 entry j -> cbuf addr = (data_bank+1)*256 + j/2、wt hsel = j%2
//    （wt.v: 写口 addr=idx[12:1]、hsel=idx[0]，idx 起点 {data_bank+1,9'b0}，
//    到 weight_bank_end={data+weight+2 bank} 回绕）。entry 低半 = 流内偏移
//    k*128..+64，高半 = +64..+128。
//
// 4) 记账（对账合同）：dat 每 grain 一拍 updt：entries=grain_slices*eps、
//    slices=grain_slices（出口比内部事件晚 9 拍，status.v d0..d9 链）；
//    Σentries=H*eps、Σslices=H。wt 每 kernel group 一拍：kernels=16(int16)/
//    32(int8)、尾组=余数；entries=该组新增半 entry 数/2；Σkernels=K、
//    Σwt_entries=bpk*K/128、Σwmb=0（非压缩）。
// =============================================================================
`ifndef CDMA_CBUF_REFMODEL_SVH
`define CDMA_CBUF_REFMODEL_SVH

class cdma_cbuf_refmodel extends uvm_object;

  cdma_layer_cfg cfg;

  // 期望 cbuf 内容（键=12 位绝对 entry 地址）
  bit [1023:0] exp_dat_data      [bit [11:0]];
  bit [3:0]    exp_dat_slot_mask [bit [11:0]];
  bit [1023:0] exp_wt_data       [bit [11:0]];
  bit [3:0]    exp_wt_slot_mask  [bit [11:0]];

  // DMA 足迹（键=32B 块字节地址）
  bit dat_chunks [bit [63:0]];
  bit wt_chunks  [bit [63:0]];

  `uvm_object_utils(cdma_cbuf_refmodel)

  function new(string name = "cdma_cbuf_refmodel");
    super.new(name);
  endfunction

  // byte 源用 responder 句柄（未初始化地址同一 default_byte 公式）
  function bit [255:0] atom_of(dma_slave_responder_cdp_t rsp, bit [63:0] a);
    bit [255:0] d;
    for (int i = 0; i < 32; i++) d[i*8 +: 8] = rsp.mem_byte(a + i);
    return d;
  endfunction

  // dat_wr_base：层始 status wr_idx（前层足迹和 % 区容量）；
  // wt_half_base：wt 半 entry 环形指针（前层 Σ(wt_bytes/64)）——两指针跨层不复位
  function void build(cdma_layer_cfg cfg_i,
                      dma_slave_responder_cdp_t dat_rsp,
                      dma_slave_responder_cdp_t wt_rsp,
                      int unsigned dat_wr_base = 0,
                      int unsigned wt_half_base = 0);
    int unsigned cs, pairs, rem, eps, e_off, slot;
    bit [11:0]   e;
    bit [63:0]   a;

    cfg = cfg_i;
    exp_dat_data.delete();      exp_dat_slot_mask.delete();
    exp_wt_data.delete();       exp_wt_slot_mask.delete();
    dat_chunks.delete();        wt_chunks.delete();

    cs    = cfg.csurf();
    pairs = cs / 4;
    rem   = cs % 4;
    eps   = cfg.eps();

    // ---- dat entries ----
    for (int unsigned h = 0; h < cfg.height; h++) begin
      for (int unsigned s = 0; s < cs; s++) begin
        for (int unsigned w = 0; w < cfg.width; w++) begin
          a = cfg.dat_addr + h * cfg.line_stride + s * cfg.surf_stride + w * 32;
          dat_chunks[a] = 1'b1;
          if (s < pairs * 4) begin              // 面四元组
            e_off = (s / 4) * cfg.width + w;
            slot  = s % 4;
          end
          else if (rem == 2) begin              // 尾双面
            e_off = pairs * cfg.width + (w >> 1);
            slot  = ((w & 1) << 1) | (s - pairs * 4);
          end
          else begin                            // 单面（cs==1）
            e_off = w >> 2;
            slot  = w & 3;
          end
          e = 12'((dat_wr_base + h * eps + e_off) % ((cfg.data_bank + 1) * 256));
          if (!exp_dat_data.exists(e)) begin
            exp_dat_data[e]      = '0;
            exp_dat_slot_mask[e] = '0;
          end
          exp_dat_data[e][slot*256 +: 256] = atom_of(dat_rsp, a);
          exp_dat_slot_mask[e][slot]       = 1'b1;
        end
      end
    end

    // ---- wt entries ----
    begin
      int unsigned halves = cfg.wt_bytes() / 64;
      int unsigned wt_base = (cfg.data_bank + 1) * 256;
      int unsigned region  = (cfg.weight_bank + 1) * 256;
      for (int unsigned j0 = 0; j0 < halves; j0++) begin
        int unsigned j = j0 + wt_half_base; // 环形半 entry 指针跨层继续
        e = 12'(wt_base + (((j % (region * 2)) >> 1)));
        if (!exp_wt_data.exists(e)) begin
          exp_wt_data[e]      = '0;
          exp_wt_slot_mask[e] = '0;
        end
        for (int i = 0; i < 64; i++)
          exp_wt_data[e][(j & 1)*512 + i*8 +: 8] = wt_rsp.mem_byte(cfg.wt_addr + j0*64 + i);
        exp_wt_slot_mask[e][(j & 1)*2 +: 2] = 2'b11;
      end
      for (int unsigned c = 0; c < cfg.wt_bytes() / 32; c++)
        wt_chunks[cfg.wt_addr + c*32] = 1'b1;
    end

    `uvm_info(get_type_name(),
              $sformatf("built: dat entries=%0d wt entries=%0d dat chunks=%0d wt chunks=%0d [%s]",
                        exp_dat_data.num(), exp_wt_data.num(),
                        dat_chunks.num(), wt_chunks.num(), cfg.convert2string()),
              UVM_LOW)
  endfunction

  function void get_dat_addr_list(ref bit [11:0] q[$]);
    bit [11:0] k;
    q.delete();
    if (exp_dat_data.first(k)) do q.push_back(k); while (exp_dat_data.next(k));
  endfunction

  function void get_wt_addr_list(ref bit [11:0] q[$]);
    bit [11:0] k;
    q.delete();
    if (exp_wt_data.first(k)) do q.push_back(k); while (exp_wt_data.next(k));
  endfunction

endclass : cdma_cbuf_refmodel

`endif // CDMA_CBUF_REFMODEL_SVH
