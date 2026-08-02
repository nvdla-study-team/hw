// -----------------------------------------------------------------------------
// sdp_item : cacc2sdp 输出 beat 观测事务
//   pd[511:0] 拆 16x32b lane；[512]=batch_end、[513]=layer_end
//   （打包事实源 NV_NVDLA_CACC_delivery_buffer.v:1397-1414）
//   注意：batch_end（pd[512]）在 nv_full RTL 中硬拴 0（delivery_buffer.v:1482
//   一带，方案书 csc-cmac-cacc.md 实读），字段保留但不要当有效标志建模/对账
// -----------------------------------------------------------------------------
`ifndef SDP_ITEM_SVH
`define SDP_ITEM_SVH

class sdp_item extends uvm_sequence_item;

  bit [513:0] pd;        // 原始打包
  bit [31:0]  lane[16];  // lane i = pd[32i +: 32]
  bit         batch_end; // pd[512]
  bit         layer_end; // pd[513]

  `uvm_object_utils(sdp_item)

  function new(string name = "sdp_item");
    super.new(name);
  endfunction

  function void unpack_pd(bit [513:0] p);
    pd = p;
    foreach (lane[i]) lane[i] = p[32*i +: 32];
    batch_end = p[512];
    layer_end = p[513];
  endfunction

  virtual function string convert2string();
    return $sformatf("SDP beat lane0=0x%08h lane15=0x%08h batch_end=%0b layer_end=%0b",
                     lane[0], lane[15], batch_end, layer_end);
  endfunction

endclass : sdp_item

`endif // SDP_ITEM_SVH
