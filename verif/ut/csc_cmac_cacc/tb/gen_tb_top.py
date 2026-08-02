#!/usr/bin/env python3
# gen_tb_top.py : 生成 verif/ut/csc_cmac_cacc/tb/tb_top.sv
# 端口清单直接解析 outdir 下 7 个 DUT 模块源文件，杜绝手抄错位。
import re, os, sys

ROOT = "/home/yian/prj/nvdla-study-team/hw/outdir/nv_full/vmod/nvdla"
OUT  = "/home/yian/prj/nvdla-study-team/hw/verif/ut/csc_cmac_cacc/tb/tb_top.sv"

def parse_ports(path):
    """按声明顺序返回 [(dir, width_str_or_None, name)]"""
    ports = []
    pat = re.compile(r'^(input|output)\s*(\[[^\]]+\])?\s*(\w+)\s*;')
    with open(path) as f:
        for line in f:
            m = pat.match(line)
            if m:
                ports.append((m.group(1), m.group(2), m.group(3)))
    return ports

csc_ports  = parse_ports(f"{ROOT}/csc/NV_NVDLA_csc.v")
cmac_ports = parse_ports(f"{ROOT}/cmac/NV_NVDLA_cmac.v")
cacc_ports = parse_ports(f"{ROOT}/cacc/NV_NVDLA_cacc.v")
rt_sc_a    = parse_ports(f"{ROOT}/retiming/NV_NVDLA_RT_csc2cmac_a.v")
rt_sc_b    = parse_ports(f"{ROOT}/retiming/NV_NVDLA_RT_csc2cmac_b.v")
rt_mac_a   = parse_ports(f"{ROOT}/retiming/NV_NVDLA_RT_cmac_a2cacc.v")
rt_mac_b   = parse_ports(f"{ROOT}/retiming/NV_NVDLA_RT_cmac_b2cacc.v")

TIEOFF = {
    "pwrbus_ram_pd":                 "32'b0",
    "dla_clk_ovr_on_sync":           "1'b0",
    "global_clk_ovr_on_sync":        "1'b0",
    "tmc2slcg_disable_clock_gating": "1'b1",
}
CLK = {"nvdla_core_clk": "nvdla_core_clk", "nvdla_core_rstn": "nvdla_core_rstn"}

wires = {}   # net -> width（去重，冲突报错）
def note_wire(net, width):
    if net in ("nvdla_core_clk", "nvdla_core_rstn"):
        return
    w = width or ""
    if net in wires and wires[net] != w:
        sys.exit(f"width clash on {net}: {wires[net]} vs {w}")
    wires[net] = w

def map_port(name, rules):
    """rules: [(prefix, replacement_prefix)]，无命中 -> identity"""
    if name in TIEOFF: return TIEOFF[name]
    if name in CLK:    return CLK[name]
    for pfx, rep in rules:
        if name.startswith(pfx):
            return rep + name[len(pfx):]
    return name

def emit_inst(mod, inst, ports, rules, special=None):
    lines = [f"  {mod} {inst} ("]
    first = True
    for d, w, p in ports:
        net = (special or {}).get(p) or map_port(p, rules)
        if net not in TIEOFF.values() and not net.startswith("u_"):
            note_wire(net, w)
        sep = "   " if first else "  ,"
        lines.append(f"  {sep}.{p:<32}({net})")
        first = False
    lines.append("  );")
    return "\n".join(lines)

# ---- 各实例映射规则（连线权威：NV_nvdla.v u_partition_ma/mb port map + 各分区）----
csc_special = {}
for d, w, p in csc_ports:
    if p.startswith("cdma2sc_"):
        csc_special[p] = f"u_cs_if.{p}"   # stub 驱动侧直连 interface

inst_csc = emit_inst("NV_NVDLA_csc", "u_NV_NVDLA_csc", csc_ports, [], csc_special)

inst_rt_sc_a = emit_inst("NV_NVDLA_RT_csc2cmac_a", "u_NV_NVDLA_RT_csc2cmac_a", rt_sc_a, [
    ("sc2mac_wt_src_",  "sc2mac_wt_a_"),
    ("sc2mac_wt_dst_",  "sc2mac_wt_a_dst_"),
    ("sc2mac_dat_src_", "sc2mac_dat_a_"),
    ("sc2mac_dat_dst_", "sc2mac_dat_a_dst_"),
])
inst_rt_sc_b = emit_inst("NV_NVDLA_RT_csc2cmac_b", "u_NV_NVDLA_RT_csc2cmac_b", rt_sc_b, [
    ("sc2mac_wt_src_",  "sc2mac_wt_b_"),
    ("sc2mac_wt_dst_",  "sc2mac_wt_b_dst_"),
    ("sc2mac_dat_src_", "sc2mac_dat_b_"),
    ("sc2mac_dat_dst_", "sc2mac_dat_b_dst_"),
])
# cmac 端口名 a/b 两例同名（csb 口带 _a_，数据口无后缀），靠外部连线区分
# （对照 NV_nvdla.v u_partition_ma:csb2cmac_a_req->csb2cmac_a_req_dst /
#   u_partition_mb:csb2cmac_a_req->csb2cmac_b_req_dst、mac2accu->mac_a/b2accu_src）
inst_cmac_a = emit_inst("NV_NVDLA_cmac", "u_NV_NVDLA_cmac_a", cmac_ports, [
    ("csb2cmac_a_req_",  "csb2cmac_a_req_"),
    ("cmac_a2csb_resp_", "cmac_a2csb_resp_"),
    ("sc2mac_dat_",      "sc2mac_dat_a_dst_"),
    ("sc2mac_wt_",       "sc2mac_wt_a_dst_"),
    ("mac2accu_",        "mac_a2accu_src_"),
])
inst_cmac_b = emit_inst("NV_NVDLA_cmac", "u_NV_NVDLA_cmac_b", cmac_ports, [
    ("csb2cmac_a_req_",  "csb2cmac_b_req_"),
    ("cmac_a2csb_resp_", "cmac_b2csb_resp_"),
    ("sc2mac_dat_",      "sc2mac_dat_b_dst_"),
    ("sc2mac_wt_",       "sc2mac_wt_b_dst_"),
    ("mac2accu_",        "mac_b2accu_src_"),
])
inst_rt_mac_a = emit_inst("NV_NVDLA_RT_cmac_a2cacc", "u_NV_NVDLA_RT_cmac_a2cacc", rt_mac_a, [
    ("mac2accu_src_", "mac_a2accu_src_"),
    ("mac2accu_dst_", "mac_a2accu_dst_"),
])
inst_rt_mac_b = emit_inst("NV_NVDLA_RT_cmac_b2cacc", "u_NV_NVDLA_RT_cmac_b2cacc", rt_mac_b, [
    ("mac2accu_src_", "mac_b2accu_src_"),
    ("mac2accu_dst_", "mac_b2accu_dst_"),
])
inst_cacc = emit_inst("NV_NVDLA_cacc", "u_NV_NVDLA_cacc", cacc_ports, [
    ("mac_a2accu_", "mac_a2accu_dst_"),
    ("mac_b2accu_", "mac_b2accu_dst_"),
])

wire_decls = "\n".join(
    f"  wire {w:<10} {n};" for n, w in wires.items()
)

header = '''// -----------------------------------------------------------------------------
// tb_top : csc + cmac(A/B) + cacc 子流水线 UT 顶层（本文件由脚本生成，勿手编大段
//          端口表；生成器见 tb/gen_tb_top.py，端口清单解析自 outdir DUT 源文件）
//   - 7 实例：NV_NVDLA_csc + RT_csc2cmac_a/b + NV_NVDLA_cmac x2 +
//     RT_cmac_a2cacc/b + NV_NVDLA_cacc；RT 是纯打拍（vmod/nvdla/retiming/），
//     带上保持整芯节拍。连线权威：NV_nvdla.v u_partition_ma(:2523)/mb(:2817)
//     port map + partition_c(csc)/partition_a(cacc)
//   - cmac 模块 csb 口端口名固定带 _a_（csb2cmac_a_req/cmac_a2csb_resp），
//     b 例同名端口接 csb2cmac_b_*/cmac_b2csb_* 网线；数据口（sc2mac_*/mac2accu_*）
//     无 a/b 后缀，靠外部连线区分——照 NV_nvdla.v 两处 port map 核对
//   - CSB：单 csb master 面 + 4 目标译码（块号 6/7/8/9 分发 req_pvld，prdy 按
//     目标选择回送，4 路 resp OR-mux + onehot0 检查——driver 单笔阻塞保证无冲突）
//   - cbuf_model 三通道挂 sc2buf（响应侧，固定 6 拍延迟）；csc_cdma_stub 挂
//     cdma2sc/sc2cdma；sdp_sink_stub 挂 cacc2sdp；intr_if x2 按位挂
//     cacc2glb_done_intr_pd；accu2sc_credit cacc->csc 直连（DUT 内自闭环，
//     真实芯片同为分区间直连线，NV_nvdla.v:156-157 无 RT）
//   - L1 观测 monitor 挂点（Wave2 预留）：sc2mac_dat_a_*/sc2mac_wt_a_*（RT 前）、
//     mac_a2accu_src_*/mac_b2accu_src_*（RT 前）均为 tb 显式 wire，可直接挂接口
//   - tie-off：pwrbus_ram_pd=0、clk_ovr=0、tmc2slcg_disable_clock_gating=1
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import nvdla_ut_pkg::*;
  import csc_cmac_cacc_ut_pkg::*;

  // ---------------- 时钟 / 复位 ----------------
  real core_period_ns = 7.0;

  logic nvdla_core_clk  = 1'b0;
  logic nvdla_core_rstn = 1'b0;

  initial begin
    void'($value$plusargs("core_period_ns=%f", core_period_ns));
    forever #(core_period_ns / 2.0) nvdla_core_clk = ~nvdla_core_clk;
  end

  initial begin
    nvdla_core_rstn = 1'b0;
    #101;
    nvdla_core_rstn = 1'b1;
  end

'''

body_ifs = '''
  // ---------------- interface 实例 ----------------
  csb_if u_csb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  cbuf_resp_if #(.ADDR_W(12)) u_cbuf_dat_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_resp_if #(.ADDR_W(12)) u_cbuf_wt_if  (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  cbuf_resp_if #(.ADDR_W(8))  u_cbuf_wmb_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  csc_cdma_if u_cs_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  sdp_if u_sdp_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  intr_if u_intr0_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));
  intr_if u_intr1_if (.clk(nvdla_core_clk), .rstn(nvdla_core_rstn));

  // ---------------- CSB 单 master 面 -> 4 目标译码 ----------------
  // 块号 blk = byte_addr[17:12] = word_addr[15:10]（同 ut_types.svh csb_target_of）
  // CSC=6(0x6000) CMAC_A=7(0x7000) CMAC_B=8(0x8000) CACC=9(0x9000)
  // req_pd = {7'h0, nposted, write, wdat[31:0], 6'h0, addr[15:0]}（csb-link.md 6.1）
  wire [5:0]  csb_blk    = u_csb_if.addr[15:10];
  wire [62:0] csb_req_pd = {7'h0, u_csb_if.nposted, u_csb_if.write,
                            u_csb_if.wdat, 6'h0, u_csb_if.addr};

  assign csb2csc_req_pvld    = u_csb_if.valid && (csb_blk == 6'd6);
  assign csb2cmac_a_req_pvld = u_csb_if.valid && (csb_blk == 6'd7);
  assign csb2cmac_b_req_pvld = u_csb_if.valid && (csb_blk == 6'd8);
  assign csb2cacc_req_pvld   = u_csb_if.valid && (csb_blk == 6'd9);
  assign csb2csc_req_pd      = csb_req_pd;
  assign csb2cmac_a_req_pd   = csb_req_pd;
  assign csb2cmac_b_req_pd   = csb_req_pd;
  assign csb2cacc_req_pd     = csb_req_pd;

  // prdy 按目标选择回送（四路 RTL 实为常 1：CSC_regfile.v:745 / CMAC_reg.v:500 /
  // CACC_regfile.v:591；选择器保持结构正确性）
  assign u_csb_if.ready = (csb_blk == 6'd6) ? csb2csc_req_prdy    :
                          (csb_blk == 6'd7) ? csb2cmac_a_req_prdy :
                          (csb_blk == 6'd8) ? csb2cmac_b_req_prdy :
                          (csb_blk == 6'd9) ? csb2cacc_req_prdy   : 1'b1;

  // 4 路 resp OR-mux：driver 单笔阻塞（等响应才发下一笔）保证同刻至多 1 路 valid，
  // onehot0 检查兜底；resp_pd[33]=type：0=读数据 1=写完成（csb-link.md 6.2）
  wire [3:0] csb_resp_vld_vec = {cacc2csb_resp_valid, cmac_b2csb_resp_valid,
                                 cmac_a2csb_resp_valid, csc2csb_resp_valid};
  wire [33:0] csb_resp_pd_mux =
      ({34{csc2csb_resp_valid}}    & csc2csb_resp_pd)    |
      ({34{cmac_a2csb_resp_valid}} & cmac_a2csb_resp_pd) |
      ({34{cmac_b2csb_resp_valid}} & cmac_b2csb_resp_pd) |
      ({34{cacc2csb_resp_valid}}   & cacc2csb_resp_pd);
  wire csb_resp_any = |csb_resp_vld_vec;

  assign u_csb_if.rvalid      = csb_resp_any & ~csb_resp_pd_mux[33];
  assign u_csb_if.rdata       = csb_resp_pd_mux[31:0];
  assign u_csb_if.wr_complete = csb_resp_any &  csb_resp_pd_mux[33];

  always @(posedge nvdla_core_clk)
    if (nvdla_core_rstn === 1'b1 && !$onehot0(csb_resp_vld_vec))
      `uvm_error("tb_top",
                 $sformatf("CSB resp collision: {cacc,cmac_b,cmac_a,csc}=%b",
                           csb_resp_vld_vec))

  // ---------------- sc2buf 三读口 -> cbuf_model（响应侧） ----------------
  assign u_cbuf_dat_if.rd_en   = sc2buf_dat_rd_en;
  assign u_cbuf_dat_if.rd_addr = sc2buf_dat_rd_addr;
  assign sc2buf_dat_rd_valid   = u_cbuf_dat_if.rd_valid;
  assign sc2buf_dat_rd_data    = u_cbuf_dat_if.rd_data;
  assign u_cbuf_wt_if.rd_en    = sc2buf_wt_rd_en;
  assign u_cbuf_wt_if.rd_addr  = sc2buf_wt_rd_addr;
  assign sc2buf_wt_rd_valid    = u_cbuf_wt_if.rd_valid;
  assign sc2buf_wt_rd_data     = u_cbuf_wt_if.rd_data;
  assign u_cbuf_wmb_if.rd_en   = sc2buf_wmb_rd_en;
  assign u_cbuf_wmb_if.rd_addr = sc2buf_wmb_rd_addr;
  assign sc2buf_wmb_rd_valid   = u_cbuf_wmb_if.rd_valid;
  assign sc2buf_wmb_rd_data    = u_cbuf_wmb_if.rd_data;

  // ---------------- cdma_sc 状态-信用面（csc 输出 -> 监测；输入由 stub 驱） ----
  assign u_cs_if.sc2cdma_dat_updt        = sc2cdma_dat_updt;
  assign u_cs_if.sc2cdma_dat_entries     = sc2cdma_dat_entries;
  assign u_cs_if.sc2cdma_dat_slices      = sc2cdma_dat_slices;
  assign u_cs_if.sc2cdma_wt_updt         = sc2cdma_wt_updt;
  assign u_cs_if.sc2cdma_wt_kernels      = sc2cdma_wt_kernels;
  assign u_cs_if.sc2cdma_wt_entries      = sc2cdma_wt_entries;
  assign u_cs_if.sc2cdma_wmb_entries     = sc2cdma_wmb_entries;
  assign u_cs_if.sc2cdma_dat_pending_req = sc2cdma_dat_pending_req;
  assign u_cs_if.sc2cdma_wt_pending_req  = sc2cdma_wt_pending_req;

  // ---------------- cacc2sdp -> sdp_sink ----------------
  assign u_sdp_if.valid  = cacc2sdp_valid;
  assign u_sdp_if.pd     = cacc2sdp_pd;
  assign cacc2sdp_ready  = u_sdp_if.ready;

  // ---------------- 中断按位挂接 ----------------
  assign u_intr0_if.intr = cacc2glb_done_intr_pd[0];
  assign u_intr1_if.intr = cacc2glb_done_intr_pd[1];
'''

footer = '''
  // ---------------- config_db / UVM 启动 ----------------
  initial begin
    uvm_config_db#(virtual csb_if)::set(null, "*", "csb_vif", u_csb_if);

    uvm_config_db#(virtual cbuf_resp_if#(12))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_dat_vif", u_cbuf_dat_if);
    uvm_config_db#(virtual cbuf_resp_if#(12))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_wt_vif", u_cbuf_wt_if);
    uvm_config_db#(virtual cbuf_resp_if#(8))::set(
      null, "uvm_test_top.env.cbuf_mdl*", "cbuf_wmb_vif", u_cbuf_wmb_if);

    uvm_config_db#(virtual csc_cdma_if)::set(
      null, "uvm_test_top.env.cdma_stub*", "csc_cdma_vif", u_cs_if);

    uvm_config_db#(virtual sdp_if)::set(
      null, "uvm_test_top.env.sdp_sink*", "sdp_vif", u_sdp_if);

    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr0_agt*", "intr_vif", u_intr0_if);
    uvm_config_db#(virtual intr_if)::set(
      null, "uvm_test_top.env.intr1_agt*", "intr_vif", u_intr1_if);

`ifdef WAVES_FSDB
    if ($test$plusargs("fsdb")) begin
      string fsdb_name = "waves.fsdb";
      void'($value$plusargs("fsdbfile=%s", fsdb_name));
      $fsdbDumpfile(fsdb_name);
      $fsdbDumpvars(0, tb_top);
    end
`endif
    run_test();
  end

endmodule : tb_top
'''

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(header)
    f.write("  // ---------------- 互连 wire（脚本自 DUT 端口表生成） ----------------\n")
    f.write(wire_decls + "\n")
    f.write(body_ifs)
    f.write("\n  // ---------------- DUT：csc（partition_c 内例，端口 1:1 同名连线） ------\n")
    f.write(inst_csc + "\n")
    f.write("\n  // ---------------- RT：csc->cmac 打拍（a 例在 partition_o、b 例在 c） ----\n")
    f.write(inst_rt_sc_a + "\n\n" + inst_rt_sc_b + "\n")
    f.write("\n  // ---------------- DUT：cmac A/B（模块端口同名，外部连线区分） ----------\n")
    f.write(inst_cmac_a + "\n\n" + inst_cmac_b + "\n")
    f.write("\n  // ---------------- RT：cmac->cacc 打拍（a 例在 partition_p、b 例在 a） ---\n")
    f.write(inst_rt_mac_a + "\n\n" + inst_rt_mac_b + "\n")
    f.write("\n  // ---------------- DUT：cacc（partition_a 内例） -------------------------\n")
    f.write(inst_cacc + "\n")
    f.write(footer)

print(f"generated {OUT}")
print(f"wires: {len(wires)}")
