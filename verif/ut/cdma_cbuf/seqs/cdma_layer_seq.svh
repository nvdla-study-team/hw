// -----------------------------------------------------------------------------
// cdma_layer_seq : 按 cdma_layer_cfg 编程一层 DC 配置
//   do_program=1 : 轮询 flush_done -> 写全部相关 D 寄存器（不写 op_en）
//   do_enable=1  : 写 D_OP_ENABLE=1
//   两步分开是为了让 test 在两步之间调 scoreboard.set_layer()（flush 流量
//   吸收期与 active 检查期以 op_en 为界）
//   寄存器编码见 cdma_layer_cfg 头注释（0-based 字段写 值-1）
// -----------------------------------------------------------------------------
`ifndef CDMA_LAYER_SEQ_SVH
`define CDMA_LAYER_SEQ_SVH

class cdma_layer_seq extends cdma_csb_base_seq;

  cdma_layer_cfg cfg;
  bit do_program = 1'b1;
  bit do_enable  = 1'b0;

  // D 组偏移（NV_NVDLA_CDMA_dual_reg.v:325-379 wren 译码）
  localparam bit [11:0] D_OP_ENABLE       = 12'h010;
  localparam bit [11:0] D_MISC_CFG        = 12'h014;
  localparam bit [11:0] D_DATAIN_FORMAT   = 12'h018;
  localparam bit [11:0] D_DATAIN_SIZE_0   = 12'h01c;
  localparam bit [11:0] D_DATAIN_SIZE_1   = 12'h020;
  localparam bit [11:0] D_PIXEL_OFFSET    = 12'h028;
  localparam bit [11:0] D_DAIN_RAM_TYPE   = 12'h02c;
  localparam bit [11:0] D_DAIN_ADDR_HIGH0 = 12'h030;
  localparam bit [11:0] D_DAIN_ADDR_LOW0  = 12'h034;
  localparam bit [11:0] D_LINE_STRIDE     = 12'h040;
  localparam bit [11:0] D_SURF_STRIDE     = 12'h048;
  localparam bit [11:0] D_DAIN_MAP        = 12'h04c;
  localparam bit [11:0] D_BATCH_NUMBER    = 12'h058;
  localparam bit [11:0] D_BATCH_STRIDE    = 12'h05c;
  localparam bit [11:0] D_ENTRY_PER_SLICE = 12'h060;
  localparam bit [11:0] D_FETCH_GRAIN     = 12'h064;
  localparam bit [11:0] D_WEIGHT_FORMAT   = 12'h068;
  localparam bit [11:0] D_WEIGHT_SIZE_0   = 12'h06c;
  localparam bit [11:0] D_WEIGHT_SIZE_1   = 12'h070;
  localparam bit [11:0] D_WEIGHT_RAM_TYPE = 12'h074;
  localparam bit [11:0] D_WEIGHT_ADDR_HI  = 12'h078;
  localparam bit [11:0] D_WEIGHT_ADDR_LO  = 12'h07c;
  localparam bit [11:0] D_WEIGHT_BYTES    = 12'h080;
  localparam bit [11:0] D_WMB_BYTES       = 12'h094;
  localparam bit [11:0] D_MEAN_FORMAT     = 12'h098;
  localparam bit [11:0] D_CVT_CFG         = 12'h0a4;
  localparam bit [11:0] D_CVT_OFFSET      = 12'h0a8;
  localparam bit [11:0] D_CVT_SCALE       = 12'h0ac;
  localparam bit [11:0] D_CONV_STRIDE     = 12'h0b0;
  localparam bit [11:0] D_ZERO_PADDING    = 12'h0b4;
  localparam bit [11:0] D_BANK            = 12'h0bc;
  localparam bit [11:0] D_NAN_TO_ZERO     = 12'h0c0;
  localparam bit [11:0] S_CBUF_FLUSH      = 12'h00c;

  `uvm_object_utils(cdma_layer_seq)

  function new(string name = "cdma_layer_seq");
    super.new(name);
  endfunction

  task wait_flush_done();
    bit [31:0] rd;
    bit done = 1'b0;
    for (int i = 0; i < 3000 && !done; i++) begin
      csb_read(S_CBUF_FLUSH, rd);
      done = rd[0];
    end
    if (!done)
      `uvm_error(get_type_name(), "flush_done never set")
  endtask

  virtual task body();
    bit [1:0] prec;
    if (cfg == null)
      `uvm_fatal(get_type_name(), "cfg not set")
    prec = cfg.is_int8 ? 2'd0 : 2'd1;

    if (do_program) begin
      wait_flush_done();
      cfg.check_supported();
      // 数据面
      csb_write(D_MISC_CFG,        {16'h0, 2'b0, prec, 2'b0, prec, 7'b0, 1'b0});
      csb_write(D_DATAIN_FORMAT,   32'h0);                     // feature
      csb_write(D_DATAIN_SIZE_0,   ((cfg.height - 1) << 16) | (cfg.width - 1));
      csb_write(D_DATAIN_SIZE_1,   cfg.channel - 1);
      csb_write(D_PIXEL_OFFSET,    32'h0);
      csb_write(D_DAIN_RAM_TYPE,   {31'b0, cfg.dat_ram_mc});
      csb_write(D_DAIN_ADDR_HIGH0, cfg.dat_addr[63:32]);
      csb_write(D_DAIN_ADDR_LOW0,  cfg.dat_addr[31:0]);
      csb_write(D_LINE_STRIDE,     cfg.line_stride);
      csb_write(D_SURF_STRIDE,     cfg.surf_stride);
      csb_write(D_DAIN_MAP,        {15'b0, 1'b0, 15'b0, cfg.line_packed});
      csb_write(D_BATCH_NUMBER,    32'h0);
      csb_write(D_BATCH_STRIDE,    32'h0);
      csb_write(D_ENTRY_PER_SLICE, cfg.eps() - 1);
      csb_write(D_FETCH_GRAIN,     (cfg.line_packed ? cfg.grain : 1) - 1);
      // 权重面（非压缩）
      csb_write(D_WEIGHT_FORMAT,   32'h0);
      csb_write(D_WEIGHT_SIZE_0,   cfg.bpk - 1);
      csb_write(D_WEIGHT_SIZE_1,   cfg.kernels - 1);
      csb_write(D_WEIGHT_RAM_TYPE, {31'b0, cfg.wt_ram_mc});
      csb_write(D_WEIGHT_ADDR_HI,  cfg.wt_addr[63:32]);
      csb_write(D_WEIGHT_ADDR_LO,  cfg.wt_addr[31:0]);
      csb_write(D_WEIGHT_BYTES,    cfg.wt_bytes());
      csb_write(D_WMB_BYTES,       32'h0);
      // 杂项：cvt bypass / 无 pad / 无 mean
      csb_write(D_MEAN_FORMAT,     32'h0);
      csb_write(D_CVT_CFG,         32'h0);   // cvt_en=0
      csb_write(D_CVT_OFFSET,      32'h0);
      csb_write(D_CVT_SCALE,       32'h1);
      csb_write(D_CONV_STRIDE,     32'h0);
      csb_write(D_ZERO_PADDING,    32'h0);
      csb_write(D_NAN_TO_ZERO,     32'h0);
      csb_write(D_BANK,            (cfg.weight_bank << 16) | cfg.data_bank);
      `uvm_info(get_type_name(), $sformatf("layer programmed: %s", cfg.convert2string()), UVM_LOW)
    end

    if (do_enable) begin
      csb_write(D_OP_ENABLE, 32'h1);
      `uvm_info(get_type_name(), "op_en set", UVM_LOW)
    end
  endtask

endclass : cdma_layer_seq

`endif // CDMA_LAYER_SEQ_SVH
