// -----------------------------------------------------------------------------
// cdma_t0_reg_seq : T0 寄存器冒烟
//   1. 复位值读（S_STATUS/S_POINTER/S_ARBITER/D_OP_ENABLE/D_MISC_CFG/
//      D_DATAIN_FORMAT/D_BANK）
//   2. D 组代表寄存器 RW 写读比对（按可写位 mask；掩掉位读 0——三个样本寄存器的
//      *_out 拼接中非字段位全 tie 0）
//   3. S_POINTER producer 切换的 D 组影子行为（d0/d1 独立保值）
//   4. 0x000-0x0e8 步进 4 扫描读不挂
//   5. S_CBUF_FLUSH_STATUS 轮询 flush_done=1（复位 flush 各 4096 拍）
//   寄存器事实源（outdir/nv_full/vmod/nvdla/cdma/）：
//     single_reg.v:64-71（S 组 offset/字段/复位）、:103-105（arb 复位 F/3）
//     dual_reg.v:325-379（D 组 offset）、:380-414（readback 拼接）、
//               :671-713（复位值）、:743-913（可写位）
//     regfile.v:871-873（S/D 0x010 切分 + producer 选组）
// -----------------------------------------------------------------------------
`ifndef CDMA_T0_REG_SEQ_SVH
`define CDMA_T0_REG_SEQ_SVH

class cdma_t0_reg_seq extends cdma_csb_base_seq;

  // ---- 偏移 ----
  localparam bit [11:0] S_STATUS            = 12'h000;
  localparam bit [11:0] S_POINTER           = 12'h004;
  localparam bit [11:0] S_ARBITER           = 12'h008;
  localparam bit [11:0] S_CBUF_FLUSH_STATUS = 12'h00c;
  localparam bit [11:0] D_OP_ENABLE         = 12'h010;
  localparam bit [11:0] D_MISC_CFG          = 12'h014;
  localparam bit [11:0] D_DATAIN_FORMAT     = 12'h018;
  localparam bit [11:0] D_BANK              = 12'h0bc;

  // ---- 可写位 mask / 复位值（见文件头事实源） ----
  localparam bit [31:0] MISC_CFG_MASK  = 32'h1111_3301;
  localparam bit [31:0] MISC_CFG_RST   = 32'h0000_1100; // in/proc_precision=01
  localparam bit [31:0] DATAIN_FMT_MASK = 32'h0011_3F01;
  localparam bit [31:0] DATAIN_FMT_RST  = 32'h0000_0C00; // pixel_format=0xC
  localparam bit [31:0] BANK_MASK      = 32'h000F_000F;
  localparam bit [31:0] ARBITER_RST    = 32'h0003_000F; // arb_wmb=3/arb_weight=F

  `uvm_object_utils(cdma_t0_reg_seq)

  function new(string name = "cdma_t0_reg_seq");
    super.new(name);
  endfunction

  // 写读比对：读回值应 == 写值 & 可写位 mask
  task rw_check(input bit [11:0] off, input bit [31:0] mask,
                input bit [31:0] wr, input string tag);
    bit [31:0] rd;
    csb_write(off, wr);
    csb_read(off, rd);
    if (rd !== (wr & mask))
      `uvm_error(get_type_name(),
                 $sformatf("%s RW: off=0x%03h wr=0x%08h exp=0x%08h got=0x%08h",
                           tag, off, wr & mask, wr, rd))
    else
      `uvm_info(get_type_name(),
                $sformatf("%s RW: off=0x%03h wr=0x%08h rd=0x%08h OK", tag, off, wr, rd),
                UVM_MEDIUM)
  endtask

  virtual task body();
    bit [31:0] rd;

    // ---- 1. 复位值 ----
    csb_check(S_STATUS,        32'h0,          "rst S_STATUS");
    csb_check(S_POINTER,       32'h0,          "rst S_POINTER");
    csb_check(S_ARBITER,       ARBITER_RST,    "rst S_ARBITER");
    csb_check(D_OP_ENABLE,     32'h0,          "rst D_OP_ENABLE");
    csb_check(D_MISC_CFG,      MISC_CFG_RST,   "rst D_MISC_CFG");
    csb_check(D_DATAIN_FORMAT, DATAIN_FMT_RST, "rst D_DATAIN_FORMAT");
    csb_check(D_BANK,          32'h0,          "rst D_BANK");

    // ---- 2. D 组 RW 写读比对（producer=0 组）----
    rw_check(D_MISC_CFG, MISC_CFG_MASK, 32'hFFFF_FFFF, "D_MISC_CFG");
    rw_check(D_MISC_CFG, MISC_CFG_MASK, 32'hA5A5_A5A5, "D_MISC_CFG");
    rw_check(D_MISC_CFG, MISC_CFG_MASK, 32'h0000_0000, "D_MISC_CFG");
    csb_write(D_MISC_CFG, MISC_CFG_RST); // 恢复复位值

    rw_check(D_DATAIN_FORMAT, DATAIN_FMT_MASK, 32'hFFFF_FFFF, "D_DATAIN_FORMAT");
    rw_check(D_DATAIN_FORMAT, DATAIN_FMT_MASK, 32'h5A5A_5A5A, "D_DATAIN_FORMAT");
    csb_write(D_DATAIN_FORMAT, DATAIN_FMT_RST);

    rw_check(D_BANK, BANK_MASK, 32'hFFFF_FFFF, "D_BANK");
    rw_check(D_BANK, BANK_MASK, 32'h0000_0000, "D_BANK");

    // ---- 3. S_POINTER 切 producer 的 D 组影子行为 ----
    // producer=0 写 d0
    csb_write(D_BANK, 32'h0003_0002);
    csb_check(D_BANK, 32'h0003_0002, "shadow d0 wr");
    // 切 producer=1：D 组读写落 d1（d1 D_BANK 仍是复位 0）
    csb_write(S_POINTER, 32'h1);
    csb_check(S_POINTER, 32'h0000_0001, "S_POINTER producer=1");
    csb_check(D_BANK, 32'h0, "shadow d1 rst");
    csb_write(D_BANK, 32'h0005_0004);
    csb_check(D_BANK, 32'h0005_0004, "shadow d1 wr");
    // 切回 producer=0：d0 旧值仍在
    csb_write(S_POINTER, 32'h0);
    csb_check(D_BANK, 32'h0003_0002, "shadow d0 keep");
    // 再切 producer=1：d1 值也仍在
    csb_write(S_POINTER, 32'h1);
    csb_check(D_BANK, 32'h0005_0004, "shadow d1 keep");
    // 恢复：producer=0，两组 D_BANK 清 0
    csb_write(D_BANK, 32'h0);
    csb_write(S_POINTER, 32'h0);
    csb_write(D_BANK, 32'h0);

    // ---- 4. 0x000-0x0e8 步进 4 扫描读（不比对值，只验证不挂） ----
    for (int unsigned off = 12'h000; off <= 12'h0e8; off += 4) begin
      csb_read(12'(off), rd);
      `uvm_info(get_type_name(),
                $sformatf("scan off=0x%03h rd=0x%08h", off, rd), UVM_HIGH)
    end

    // ---- 5. flush_done 轮询（复位 flush dat/wt 各 4096 拍） ----
    begin
      bit done = 1'b0;
      for (int i = 0; i < 3000 && !done; i++) begin
        csb_read(S_CBUF_FLUSH_STATUS, rd);
        done = rd[0];
      end
      if (!done)
        `uvm_error(get_type_name(), "S_CBUF_FLUSH_STATUS.flush_done never set")
      else
        `uvm_info(get_type_name(), "cbuf flush done observed", UVM_LOW)
    end
  endtask

endclass : cdma_t0_reg_seq

`endif // CDMA_T0_REG_SEQ_SVH
