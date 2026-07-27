// -----------------------------------------------------------------------------
// ut_types.svh : UT 平台公共类型与函数
//   - csb_tgt_e     : 17 路 CSB 扇出目的地枚举，枚举值 == 4KB 块号 byte_addr[17:12]
//   - csb_target_of : 由 16 位字地址预测路由目的地（含 dummy）
//   - csb_default_pattern : responder / scoreboard 共用的确定性读默认数据
// 事实源: outdir/nv_full/vmod/nvdla/csb_master/NV_NVDLA_csb_master.v
//   译码: (byte_addr & 18'h3F000) == {blk,12'h0}, byte_addr = {word_addr,2'b00}
//   块号 0x00..0x10 -> 17 路目的地, 0x11..0x3F (word addr >= 0x4400) -> 内部 dummy
// -----------------------------------------------------------------------------
`ifndef UT_TYPES_SVH
`define UT_TYPES_SVH

localparam int unsigned NUM_CSB_TGT = 17;

typedef enum int unsigned {
  CSB_TGT_GLB      = 0,   // byte 0x0000
  CSB_TGT_GEC      = 1,   // byte 0x1000
  CSB_TGT_MCIF     = 2,   // byte 0x2000
  CSB_TGT_CVIF     = 3,   // byte 0x3000
  CSB_TGT_BDMA     = 4,   // byte 0x4000
  CSB_TGT_CDMA     = 5,   // byte 0x5000
  CSB_TGT_CSC      = 6,   // byte 0x6000
  CSB_TGT_CMAC_A   = 7,   // byte 0x7000
  CSB_TGT_CMAC_B   = 8,   // byte 0x8000
  CSB_TGT_CACC     = 9,   // byte 0x9000
  CSB_TGT_SDP_RDMA = 10,  // byte 0xa000
  CSB_TGT_SDP      = 11,  // byte 0xb000
  CSB_TGT_PDP_RDMA = 12,  // byte 0xc000
  CSB_TGT_PDP      = 13,  // byte 0xd000
  CSB_TGT_CDP_RDMA = 14,  // byte 0xe000
  CSB_TGT_CDP      = 15,  // byte 0xf000
  CSB_TGT_RBK      = 16,  // byte 0x10000
  CSB_TGT_DUMMY    = 17   // 未命中 -> DUT 内部 dummy client
} csb_tgt_e;

// 由 16 位字地址预测路由目的地
function automatic csb_tgt_e csb_target_of(bit [15:0] word_addr);
  bit [17:0] byte_addr;
  bit [5:0]  blk;
  byte_addr = {word_addr, 2'b00};
  blk       = byte_addr[17:12];
  if (blk <= 6'd16) return csb_tgt_e'(blk);
  else              return CSB_TGT_DUMMY;
endfunction

// 未写过的地址的确定性读默认数据：responder 与 scoreboard 独立复算得到同一值
function automatic bit [31:0] csb_default_pattern(int unsigned tgt_id,
                                                  bit [15:0]   word_addr);
  return 32'hD000_0000 | (tgt_id << 16) | word_addr;
endfunction

`endif // UT_TYPES_SVH
