// -----------------------------------------------------------------------------
// sdp2pdp_item : sdp2pdp 出口 beat 事务（阶段4 前置公共组件）
//   裸 pd[255:0] + 16x16b lane 视图（lane i = pd[16i +: 16]）
//   注意：pd 字段语义环境搭建阶段不定案（lane 拆法按 16x16b 惯例先给），
//   待 SDP 数据通路 wave 定案后回写本头注
// -----------------------------------------------------------------------------
`ifndef SDP2PDP_ITEM_SVH
`define SDP2PDP_ITEM_SVH

class sdp2pdp_item extends uvm_sequence_item;

  bit [255:0] pd;  // 原始打包（语义待定案）

  `uvm_object_utils(sdp2pdp_item)

  function new(string name = "sdp2pdp_item");
    super.new(name);
  endfunction

  // lane i = pd[16i +: 16]（i 取 0..15）
  function bit [15:0] get_lane(int unsigned i);
    return pd[16*i +: 16];
  endfunction

  function void set_lane(int unsigned i, bit [15:0] v);
    pd[16*i +: 16] = v;
  endfunction

  virtual function string convert2string();
    return $sformatf("SDP2PDP beat lane0=0x%04h lane15=0x%04h",
                     get_lane(0), get_lane(15));
  endfunction

endclass : sdp2pdp_item

`endif // SDP2PDP_ITEM_SVH
