// -----------------------------------------------------------------------------
// cbuf_model : CBUF 行为模型（TB 扮演 cbuf 响应 csc 的 sc2buf 三读口）
//   - 存储：16 bank x 256 entry x 1024b，地址 {bank[3:0], entry[7:0]}（关联数组，
//     未写过的 entry 读 0——对齐复位 flush 后全 0 的真实 cbuf 状态）
//   - 时序：en 采样边沿起恰 6 拍后 valid+data（5 级移位延迟线 + 输出驱动拍，
//     支持每拍一个新地址的背靠背流水；合同见 cbuf_resp_if.sv 头注）
//   - 三通道：dat/wt ADDR_W=12（全地址）、wmb ADDR_W=8（恒 bank15，TB 补高 4'hF，
//     对偶 NV_NVDLA_cbuf.v:3984-3990 wmb 读口只连 bank15）
//   - 地址域检查旋钮：set_dat_banks()/set_wt_banks() 配置后，读址落在域外报
//     UVM_ERROR（Wave2 由 layer_cfg 配置域值；默认关闭）
//   - API：preload(addr, data) / load_entries(base, entries[]) / clear() / read()
//   virtual interface 经 config_db 键 "cbuf_dat_vif"/"cbuf_wt_vif"/"cbuf_wmb_vif"
// -----------------------------------------------------------------------------
`ifndef CBUF_MODEL_SVH
`define CBUF_MODEL_SVH

typedef class cbuf_model;

// 单通道响应引擎（cbuf_model 内部件，参数化 ADDR_W）
class cbuf_resp_chan #(
  int ADDR_W = 12
) extends uvm_component;

  typedef cbuf_resp_chan #(ADDR_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual cbuf_resp_if #(ADDR_W) vif_t;
  vif_t      vif;
  cbuf_model mdl;              // 共享存储（父组件回读）

  // wmb 口地址只有 entry 号，高 4 位补固定 bank（4'hF）
  bit        use_fixed_bank = 1'b0;
  bit [3:0]  fixed_bank     = 4'h0;

  // 地址域检查旋钮（默认关；Wave2 由 layer_cfg 配置）
  bit        check_range = 1'b0;
  bit [3:0]  bank_lo     = 4'd0;
  bit [3:0]  bank_hi     = 4'd15;

  int unsigned n_reads;

  // en 采样边沿 -> valid 驱动边沿间隔 5 拍：消费侧采到 valid 恰为 en 后 6 拍
  // （驱动经 output #1 skew，下一边沿被 DUT 采样，合计 6 级触发器延迟）
  localparam int PIPE = 5;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function bit [11:0] full_addr(bit [ADDR_W-1:0] a);
    if (use_fixed_bank) return {fixed_bank, 8'(a)};
    else                return 12'(a);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit        vld_pipe  [PIPE];
    bit [11:0] addr_pipe [PIPE];
    bit        out_vld;
    bit [11:0] out_addr;

    if (vif == null) return; // 骨架模式
    vif.mdl_cb.rd_valid <= 1'b0;
    vif.mdl_cb.rd_data  <= '0;

    forever begin
      @(vif.mdl_cb);
      if (vif.rstn !== 1'b1) begin
        foreach (vld_pipe[i]) vld_pipe[i] = 1'b0;
        vif.mdl_cb.rd_valid <= 1'b0;
        vif.mdl_cb.rd_data  <= '0;
        continue;
      end
      // 弹出管线尾 -> 本拍输出；随后整体移位、采入本拍请求（背靠背安全）
      out_vld  = vld_pipe[PIPE-1];
      out_addr = addr_pipe[PIPE-1];
      for (int i = PIPE - 1; i > 0; i--) begin
        vld_pipe[i]  = vld_pipe[i-1];
        addr_pipe[i] = addr_pipe[i-1];
      end
      vld_pipe[0]  = (vif.mdl_cb.rd_en === 1'b1);
      addr_pipe[0] = full_addr(vif.mdl_cb.rd_addr);
      if (vld_pipe[0]) begin
        n_reads++;
        if (check_range &&
            (addr_pipe[0][11:8] < bank_lo || addr_pipe[0][11:8] > bank_hi))
          `uvm_error(get_type_name(),
                     $sformatf("%s read addr 0x%03h (bank %0d) out of range [%0d:%0d]",
                               get_name(), addr_pipe[0], addr_pipe[0][11:8],
                               bank_lo, bank_hi))
      end
      vif.mdl_cb.rd_valid <= out_vld;
      vif.mdl_cb.rd_data  <= out_vld ? mdl.read(out_addr) : '0;
    end
  endtask

endclass : cbuf_resp_chan


class cbuf_model extends uvm_component;

  typedef cbuf_resp_chan #(12) chan12_t;
  typedef cbuf_resp_chan #(8)  chan8_t;

  chan12_t dat_chan;
  chan12_t wt_chan;
  chan8_t  wmb_chan;

  // 16 bank x 256 entry；键 = {bank[3:0], entry[7:0]}
  protected bit [1023:0] mem [bit [11:0]];

  `uvm_component_utils(cbuf_model)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual cbuf_resp_if #(12) dat_vif, wt_vif;
    virtual cbuf_resp_if #(8)  wmb_vif;
    super.build_phase(phase);

    dat_chan = chan12_t::type_id::create("dat_chan", this);
    wt_chan  = chan12_t::type_id::create("wt_chan", this);
    wmb_chan = chan8_t::type_id::create("wmb_chan", this);
    dat_chan.mdl = this;
    wt_chan.mdl  = this;
    wmb_chan.mdl = this;
    wmb_chan.use_fixed_bank = 1'b1;
    wmb_chan.fixed_bank     = 4'hF; // wmb 恒 bank15

    if (uvm_config_db#(virtual cbuf_resp_if#(12))::get(this, "", "cbuf_dat_vif", dat_vif))
      dat_chan.vif = dat_vif;
    else
      `uvm_info(get_type_name(), "cbuf_dat_vif not found, model in skeleton mode", UVM_HIGH)
    if (uvm_config_db#(virtual cbuf_resp_if#(12))::get(this, "", "cbuf_wt_vif", wt_vif))
      wt_chan.vif = wt_vif;
    if (uvm_config_db#(virtual cbuf_resp_if#(8))::get(this, "", "cbuf_wmb_vif", wmb_vif))
      wmb_chan.vif = wmb_vif;
  endfunction

  // ---- 存储 API ----
  function bit [1023:0] read(bit [11:0] addr);
    return mem.exists(addr) ? mem[addr] : '0;
  endfunction

  function void preload(bit [11:0] addr, bit [1023:0] data);
    mem[addr] = data;
  endfunction

  // 自 base 起连续预载（entry 序 = cbuf 地址序，跨 bank 自然进位）
  function void load_entries(bit [11:0] base, bit [1023:0] entries[]);
    foreach (entries[i]) mem[12'(base + i)] = entries[i];
  endfunction

  function void clear();
    mem.delete();
  endfunction

  // ---- 地址域检查旋钮（Wave2 layer_cfg 调用）----
  function void set_dat_banks(bit [3:0] lo, bit [3:0] hi);
    dat_chan.check_range = 1'b1;
    dat_chan.bank_lo = lo;
    dat_chan.bank_hi = hi;
  endfunction

  function void set_wt_banks(bit [3:0] lo, bit [3:0] hi);
    wt_chan.check_range = 1'b1;
    wt_chan.bank_lo = lo;
    wt_chan.bank_hi = hi;
  endfunction

endclass : cbuf_model

`endif // CBUF_MODEL_SVH
