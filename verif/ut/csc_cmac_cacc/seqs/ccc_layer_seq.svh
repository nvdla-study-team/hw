// -----------------------------------------------------------------------------
// ccc_layer_seq : 按 ccc_layer_cfg 编程四单元一层（do_program / do_enable 分步）
//   - program：写全部 D 组配置寄存器（不含 op_en）；字段编码见 ccc_layer_cfg 头注
//   - enable：op_en 从下游到上游 cacc -> cmac_b -> cmac_a -> csc（方案书 4.4 节
//     第 3 步：软件编程约定，DUT 无硬件互锁，乱序属未定义行为）
//   - producer 由测试先写 S_POINTER 选组（乒乓测试用），本序列不动指针
//   - D_WEIGHT_BYTES 写 wt_entries*128：字段值=bytes>>7 被 wl 当 entry 数消费
//     （wl.v:1852），非 128B 整流按 ceil 折算
// -----------------------------------------------------------------------------
`ifndef CCC_LAYER_SEQ_SVH
`define CCC_LAYER_SEQ_SVH

class ccc_layer_seq extends ccc_csb_base_seq;

  ccc_layer_cfg cfg;
  bit do_program = 1'b1;
  bit do_enable  = 1'b0;

  `uvm_object_utils(ccc_layer_seq)

  function new(string name = "ccc_layer_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] prec;
    if (cfg == null)
      `uvm_fatal(get_type_name(), "ccc_layer_seq needs cfg")
    prec = cfg.is_int8 ? 32'h0 : 32'h1;

    if (do_program) begin
      // ---- CSC（0x6000）----
      csb_write(CSB_TGT_CSC, 12'h00c, (prec << 12) | (prec << 8));            // D_MISC_CFG
      csb_write(CSB_TGT_CSC, 12'h010, 32'h0);                                 // D_DATAIN_FORMAT=feature
      csb_write(CSB_TGT_CSC, 12'h014,
                ((cfg.height - 1) << 16) | (cfg.width - 1));                  // D_DATAIN_SIZE_EXT_0
      csb_write(CSB_TGT_CSC, 12'h018, cfg.channel - 1);                       // D_DATAIN_SIZE_EXT_1
      csb_write(CSB_TGT_CSC, 12'h01c, 32'h0);                                 // D_BATCH_NUMBER
      csb_write(CSB_TGT_CSC, 12'h020, 32'h0);                                 // D_POST_Y_EXTENSION
      csb_write(CSB_TGT_CSC, 12'h024, cfg.eps() - 1);                         // D_ENTRY_PER_SLICE
      csb_write(CSB_TGT_CSC, 12'h028, 32'h0);                                 // D_WEIGHT_FORMAT=uncompressed
      csb_write(CSB_TGT_CSC, 12'h02c, 32'h0);                                 // D_WEIGHT_SIZE_EXT_0 (R=S=1)
      csb_write(CSB_TGT_CSC, 12'h030,
                ((cfg.kernels - 1) << 16) | (cfg.channel - 1));               // D_WEIGHT_SIZE_EXT_1
      csb_write(CSB_TGT_CSC, 12'h034, cfg.wt_entries() * 128);                // D_WEIGHT_BYTES
      csb_write(CSB_TGT_CSC, 12'h038, 32'h0);                                 // D_WMB_BYTES
      csb_write(CSB_TGT_CSC, 12'h03c,
                ((cfg.out_h() - 1) << 16) | (cfg.out_w() - 1));               // D_DATAOUT_SIZE_0
      csb_write(CSB_TGT_CSC, 12'h040, cfg.kernels - 1);                       // D_DATAOUT_SIZE_1
      csb_write(CSB_TGT_CSC, 12'h044, cfg.atomics() - 1);                     // D_ATOMICS
      csb_write(CSB_TGT_CSC, 12'h048, cfg.height - 1);                        // D_RELEASE
      csb_write(CSB_TGT_CSC, 12'h04c, 32'h0);                                 // D_CONV_STRIDE_EXT (=1)
      csb_write(CSB_TGT_CSC, 12'h050, 32'h0);                                 // D_DILATION_EXT (=1)
      csb_write(CSB_TGT_CSC, 12'h054, 32'h0);                                 // D_ZERO_PADDING
      csb_write(CSB_TGT_CSC, 12'h058, 32'h0);                                 // D_ZERO_PADDING_VALUE
      csb_write(CSB_TGT_CSC, 12'h05c,
                (cfg.weight_bank << 16) | cfg.data_bank);                     // D_BANK
      csb_write(CSB_TGT_CSC, 12'h060, 32'h0);                                 // D_PRA_CFG
      csb_write(CSB_TGT_CSC, 12'h064, 32'h0);                                 // D_CYA

      // ---- CMAC A/B（0x7000/0x8000，两例必须同配）----
      csb_write(CSB_TGT_CMAC_A, 12'h00c, prec << 12);                         // D_MISC_CFG
      csb_write(CSB_TGT_CMAC_B, 12'h00c, prec << 12);

      // ---- CACC（0x9000）----
      csb_write(CSB_TGT_CACC, 12'h00c, prec << 12);                           // D_MISC_CFG
      csb_write(CSB_TGT_CACC, 12'h010,
                ((cfg.out_h() - 1) << 16) | (cfg.out_w() - 1));               // D_DATAOUT_SIZE_0
      csb_write(CSB_TGT_CACC, 12'h014, cfg.kernels - 1);                      // D_DATAOUT_SIZE_1
      csb_write(CSB_TGT_CACC, 12'h018, 32'h0);                                // D_DATAOUT_ADDR
      csb_write(CSB_TGT_CACC, 12'h01c, 32'h0);                                // D_BATCH_NUMBER
      csb_write(CSB_TGT_CACC, 12'h020, 32'h0);                                // D_LINE_STRIDE
      csb_write(CSB_TGT_CACC, 12'h024, 32'h0);                                // D_SURF_STRIDE
      csb_write(CSB_TGT_CACC, 12'h028, 32'h0001_0001);                        // D_DATAOUT_MAP packed
      csb_write(CSB_TGT_CACC, 12'h02c, cfg.clip_truncate);                    // D_CLIP_CFG
      csb_write(CSB_TGT_CACC, 12'h034, 32'h0);                                // D_CYA
    end

    if (do_enable) begin
      csb_write(CSB_TGT_CACC,   12'h008, 32'h1);
      csb_write(CSB_TGT_CMAC_B, 12'h008, 32'h1);
      csb_write(CSB_TGT_CMAC_A, 12'h008, 32'h1);
      csb_write(CSB_TGT_CSC,    12'h008, 32'h1);
    end
  endtask

endclass : ccc_layer_seq

`endif // CCC_LAYER_SEQ_SVH
