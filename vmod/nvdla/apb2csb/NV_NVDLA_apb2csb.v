// ================================================================
// NVDLA Open Source Project
// 
// Copyright(c) 2016 - 2017 NVIDIA Corporation.  Licensed under the
// NVDLA Open Hardware License; Check "LICENSE" which comes with 
// this distribution for more information.
// ================================================================

// File Name: NV_NVDLA_apb2csb.v

// ----------------------------------------------------------------
// 【机制总览】APB → CSB 协议翻译桥（纯组合 + 1 个在途标志，pclk 单时钟域）
//
// 作用：把主机侧的 APB 从设备访问翻译成 NVDLA CSB 单口请求。
// 两个协议的关键差异与本桥的化解方式：
//   1) 地址粒度：APB 用字节地址，CSB 用 32bit 字地址
//      —— 取 paddr[17:2] 作字地址（丢弃低 2 位，寄存器空间 256KB）。
//   2) 写完成语义：CSB 写分 posted（发完即忘）与 non-posted（等 wr_complete
//      回包）两种；APB 侧无法表达后者 —— 本桥恒发 posted 写，
//      APB 写事务在 csb2nvdla_ready 拉高当拍即告结束。
//   3) 读握手：APB 读要求 prdata 与 pready 同拍有效，而 CSB 的读请求与
//      读数据回包（nvdla2csb_valid）分离且相隔多拍
//      —— 用 rd_trans_low 标志记录"读请求已发出、回包未到"的在途状态，
//      期间靠 pready=0 拉长 APB 访问，并防止重复发出读请求。
//
// 时序假设：CSB 侧的跨时钟域由下游 csb_master 内部完成，本桥不涉及 CDC；
// 依赖 APB 协议保证主机在 pready=0 期间保持 psel/penable/地址/数据不变。
// ----------------------------------------------------------------
module NV_NVDLA_apb2csb (
   pclk
  ,prstn
  ,csb2nvdla_ready
  ,nvdla2csb_data
  ,nvdla2csb_valid
  ,paddr
  ,penable
  ,psel
  ,pwdata
  ,pwrite
  ,csb2nvdla_addr
  ,csb2nvdla_nposted
  ,csb2nvdla_valid
  ,csb2nvdla_wdat
  ,csb2nvdla_write
  ,prdata
  ,pready
  );


input  pclk;
input  prstn;

// APB 从设备口：本桥只看 psel & penable 同高的 access 阶段，不区分 setup 阶段
//apb interface
input         psel; 
input         penable;
input         pwrite;
input [31:0]  paddr;
input [31:0]  pwdata;
output [31:0] prdata;
output        pready;

// CSB 主机口：valid/ready 握手发请求；读数据回包走 nvdla2csb_valid/data。
// 本桥不接 nvdla2csb_wr_complete（下面被注释掉的端口即是）——恒 posted 写的取舍
//csb interface 
output         csb2nvdla_valid;   
input          csb2nvdla_ready; 
output  [15:0] csb2nvdla_addr;
output  [31:0] csb2nvdla_wdat;
output         csb2nvdla_write;
output         csb2nvdla_nposted;

input          nvdla2csb_valid; 
input   [31:0] nvdla2csb_data;

//input  nvdla2csb_wr_complete;

// rd_trans_low：读事务"在途"标志。置 1 表示读请求已被 CSB 收下、读数据尚未
// 返回。它只负责压掉 csb2nvdla_valid，防止等待回包期间同一笔 APB 读被 CSB
// 当成第二笔读请求；APB 侧的等待由 pready 逻辑独立完成
reg    rd_trans_low;
wire   rd_trans_vld;
wire   wr_trans_vld;

// synoff nets

// monitor nets

// debug nets

// tie high nets

// tie low nets

// no connect nets

// not all bits used nets

// todo nets

    
// APB access 阶段判定：psel 与 penable 同高即地址/数据已稳定，按 pwrite 分读写
assign   wr_trans_vld = psel & penable & pwrite; 
assign   rd_trans_vld = psel & penable & ~pwrite;

// 在途标志生命周期：CSB 收下读请求（csb2nvdla_ready 与读请求同拍为高）置位；
// 读数据回包到达清零。清零分支在前，保证回包当拍立即结束在途状态
always @(posedge pclk or negedge prstn) begin
  if (!prstn) begin
    rd_trans_low <= 1'b0;
  end else begin
    if(nvdla2csb_valid & rd_trans_low) 
        rd_trans_low <= 1'b0;
    else if (csb2nvdla_ready & rd_trans_vld) 
        rd_trans_low <= 1'b1;
  end
end

// 请求发出：写事务直通（APB 主机自会保持到 ready）；读事务只在"无在途读"时
// 拉 valid，否则等待回包期间持续为高的 valid 会被 CSB 当成新的读请求
assign   csb2nvdla_valid   = wr_trans_vld | rd_trans_vld & ~rd_trans_low;
// 字节地址 → 32bit 字地址：paddr[1:0] 丢弃（寄存器均按字对齐访问），
// paddr[17:2] 共 16bit，覆盖 NVDLA 全部 256KB 寄存器地址空间
assign   csb2nvdla_addr    = paddr[17:2];
assign   csb2nvdla_wdat    = pwdata[31:0];
assign   csb2nvdla_write   = pwrite;
// 恒 posted 写：写完成/写错误对 APB 主机不可见，换来写事务无需等待回包
assign   csb2nvdla_nposted = 1'b0;

// 读数据直通：合法性由 pready 保证——APB 读访问被拉长到回包到达的那一拍
assign   prdata = nvdla2csb_data[31:0]; 

// pready 生成（按需拉低）：写事务在 CSB 未 ready（下游请求 FIFO 满）时等待；
// 读事务一直等到读数据回包当拍才结束 APB 访问
assign   pready = ~(wr_trans_vld & ~csb2nvdla_ready | rd_trans_vld & ~nvdla2csb_valid);

endmodule // NV_NVDLA_apb2csb

