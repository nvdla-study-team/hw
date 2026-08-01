// -----------------------------------------------------------------------------
// dma_slave_responder : DMA slave 内存模型（参数化；阶段3.1 读路径按 RTL 实证重写）
//
//   读通道（语义与 MCIF/CVIF READ 实测一致）：
//   - size 是 0-based 的 32B 块数：总块数 n = size+1
//     （vmod/nvdla/cdp/NV_NVDLA_CDP_RDMA_ig.v:833 "64.cnt = 64.size + 1"）
//   - 响应按 512b beat **紧凑打包**：块 i 取自 addr+32*i，beat j 低 256b=块 2j、
//     高 256b=块 2j+1；beat 数 = ceil(n/2)。首块永远落在首拍低半，与 addr[5] 无关
//     —— mcif 内部把 AXI 64B 对齐取数经 swizzle 重排后写进两个 256b 重排 FIFO
//     （NV_NVDLA_MCIF_READ_eg.v:1036-1046、:1049-1052 swizzle；
//       NV_NVDLA_MCIF_READ_IG_bpt.v:387 swizzle=stt_offset[0] 即 addr[5]）
//   - mask 只有两种取值：2'b11（两半有效）或 2'b01（n 为奇数时的末拍，仅低半）。
//     **2'b10 永不出现**（NV_NVDLA_MCIF_READ_eg.v:1095
//     `dma0_mask = dma0_is_last_odd ? 2'b01 : 2'b11`；消费侧 CDMA 同样按
//     mask[0]+mask[1] 计块、mask[0]→低半 mask[1]→高半落盘，
//     NV_NVDLA_CDMA_dc.v:8015、:8990-9005）
//   - 多笔在途：请求收进队列、独立响应线程按请求序回数（协议无 ID，同客户端按序）；
//     req_prdy 背压概率/拍数旋钮（默认不背压）
//   - 未初始化地址回确定性 pattern default_byte(addr)（地址异或哈希），
//     测试可用 load_bytes()/load_data() 预载内存镜像
//
//   写通道 : id=[WR_REQ_W-1]，0=cmd（addr[63:0]，[77]=require_ack）1=data（沿用骨架）
//   credit : rd_cdt_lat_fifo_pop 脉冲直通计数（cdma 无 pop，tb 绑 0 即可）
// -----------------------------------------------------------------------------
`ifndef DMA_SLAVE_RESPONDER_SVH
`define DMA_SLAVE_RESPONDER_SVH

class dma_slave_responder #(
  int RD_REQ_W = 79,
  int RD_RSP_W = 514,
  int WR_REQ_W = 515
) extends uvm_component;

  typedef dma_slave_responder #(RD_REQ_W, RD_RSP_W, WR_REQ_W) this_t;
  `uvm_component_param_utils(this_t)

  typedef virtual dma_if #(RD_REQ_W, RD_RSP_W, WR_REQ_W) vif_t;
  vif_t vif;

  localparam int DATA_W     = RD_RSP_W - 2;    // 数据位宽（去掉 mask[1:0]）
  localparam int HALF_W     = DATA_W / 2;      // 半拍位宽（256）
  localparam int HALF_BYTES = HALF_W / 8;      // 半拍字节数（32，即一个 32B 块）
  localparam int BYTES_N    = DATA_W / 8;      // 整拍字节数（64）

  bit [7:0]    mem [bit [63:0]];
  int unsigned credit_returned;

  // ---- 旋钮（默认零背压、rsp 延迟 0..2）----
  int unsigned rd_rsp_dly_min = 0;   // 每 beat 发出前延迟拍数
  int unsigned rd_rsp_dly_max = 2;
  int unsigned req_gap_pct    = 0;   // rd_req_prdy 压低概率（%）
  int unsigned req_gap_min    = 1;   // 压低拍数区间
  int unsigned req_gap_max    = 4;
  // 每笔请求首拍最小延迟（自请求握手起）。原因（cdma_cbuf T3 波形实证）：
  // CDMA wt 的响应消费不做请求信息 FIFO 头有效门控（NV_NVDLA_CDMA_wt.v
  // `wt_rsp_valid = dma_rd_rsp_vld & dma_rd_rsp_rdy & (dma_rsp_src==SRC_ID_WT)`，
  // 对比 dc 的 `is_rsp_ch0 = dma_rsp_fifo_req & ...` 有门控），若响应在该
  // FIFO 读延迟（约 4-5 拍）内返回，src=X 污染 wt FSM。真实 mcif/cvif 往返
  // 远大于此；从设备默认保持 ≥6 拍的隐性最小响应延迟契约。
  int unsigned rd_rsp_first_min = 6;

  // ---- 在途读请求队列（收请求与回数解耦，按序服务）----
  protected bit [63:0]   rd_addr_q[$];
  protected int unsigned rd_size_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // 未初始化地址的确定性 pattern（refmodel/scoreboard 可独立复算）
  virtual function bit [7:0] default_byte(bit [63:0] a);
    return a[7:0] ^ a[15:8] ^ a[23:16] ^ 8'h5A;
  endfunction

  virtual function bit [7:0] mem_byte(bit [63:0] a);
    return mem.exists(a) ? mem[a] : default_byte(a);
  endfunction

  // 测试预载内存镜像
  function void load_bytes(bit [63:0] addr, bit [7:0] bytes[]);
    foreach (bytes[i]) mem[addr + i] = bytes[i];
  endfunction

  // 按 32B 块预载（data[7:0] 落在 addr，小端字节序，与响应打包一致）
  function void load_data(bit [63:0] addr, bit [HALF_W-1:0] data);
    for (int i = 0; i < HALF_BYTES; i++) mem[addr + i] = data[i*8 +: 8];
  endfunction

  function void clear_mem();
    mem.delete();
  endfunction

  virtual task run_phase(uvm_phase phase);
    if (vif == null) begin
      `uvm_info(get_type_name(), "no vif bound, responder idle (skeleton mode)", UVM_HIGH)
      return;
    end
    vif.slv_cb.rd_req_prdy     <= 1'b0;
    vif.slv_cb.rd_rsp_pvld     <= 1'b0;
    vif.slv_cb.rd_rsp_pd       <= '0;
    vif.slv_cb.wr_req_prdy     <= 1'b0;
    vif.slv_cb.wr_rsp_complete <= 1'b0;
    wait (vif.rstn === 1'b1);
    @(vif.slv_cb);
    fork
      rd_req_loop();
      rd_rsp_loop();
      wr_loop();
      credit_loop();
    join
  endtask

  // 收请求：prdy 背压旋钮，握手拍入队（可多笔在途）
  task rd_req_loop();
    forever begin
      if (req_gap_pct > 0 && $urandom_range(99) < req_gap_pct) begin
        vif.slv_cb.rd_req_prdy <= 1'b0;
        repeat ($urandom_range(req_gap_max, req_gap_min)) @(vif.slv_cb);
      end
      vif.slv_cb.rd_req_prdy <= 1'b1;
      @(vif.slv_cb);
      if (vif.slv_cb.rd_req_pvld === 1'b1) begin
        rd_addr_q.push_back(vif.slv_cb.rd_req_pd[63:0]);
        rd_size_q.push_back(vif.slv_cb.rd_req_pd[RD_REQ_W-1:64]);
      end
    end
  endtask

  // 回数：按请求序；块 i 取 addr+32*i 紧凑打包；末奇块 mask=2'b01
  task rd_rsp_loop();
    bit [63:0]       a;
    int unsigned     n_chunks, n_beats;
    bit [HALF_W-1:0] lo, hi;
    bit              hi_vld;
    forever begin
      wait (rd_addr_q.size() > 0);
      a        = rd_addr_q.pop_front();
      n_chunks = rd_size_q.pop_front() + 1;
      n_beats  = (n_chunks + 1) / 2;
      for (int b = 0; b < n_beats; b++) begin
        int unsigned dly = $urandom_range(rd_rsp_dly_max, rd_rsp_dly_min);
        if (b == 0 && dly < rd_rsp_first_min) dly = rd_rsp_first_min;
        repeat (dly) @(vif.slv_cb);
        hi_vld = (2*b + 1) < n_chunks;
        for (int i = 0; i < HALF_BYTES; i++) begin
          lo[i*8 +: 8] = mem_byte(a + 64*b + i);
          hi[i*8 +: 8] = hi_vld ? mem_byte(a + 64*b + HALF_BYTES + i) : 8'h00;
        end
        vif.slv_cb.rd_rsp_pvld <= 1'b1;
        vif.slv_cb.rd_rsp_pd   <= {hi_vld ? 2'b11 : 2'b01, hi, lo};
        do @(vif.slv_cb); while (vif.slv_cb.rd_rsp_prdy !== 1'b1);
        vif.slv_cb.rd_rsp_pvld <= 1'b0;
      end
    end
  endtask

  task wr_loop();
    bit [63:0] wr_addr;
    bit        ack_pending;
    forever begin
      vif.slv_cb.wr_req_prdy     <= 1'b1;
      vif.slv_cb.wr_rsp_complete <= 1'b0;
      @(vif.slv_cb);
      if (vif.slv_cb.wr_req_pvld === 1'b1) begin
        if (vif.slv_cb.wr_req_pd[WR_REQ_W-1] == 1'b0) begin // cmd 变体
          wr_addr     = vif.slv_cb.wr_req_pd[63:0];
          ack_pending = vif.slv_cb.wr_req_pd[77]; // require_ack：置 1 才回 complete
        end
        else begin // data 变体
          for (int i = 0; i < BYTES_N; i++)
            mem[wr_addr + i] = vif.slv_cb.wr_req_pd[i*8 +: 8];
          wr_addr += BYTES_N;
          if (ack_pending) begin
            vif.slv_cb.wr_rsp_complete <= 1'b1; // 单拍 complete
            ack_pending = 1'b0;
          end
        end
      end
    end
  endtask

  task credit_loop();
    forever begin
      @(vif.slv_cb);
      if (vif.slv_cb.rd_cdt_lat_fifo_pop === 1'b1)
        credit_returned++;
    end
  endtask

endclass : dma_slave_responder

`endif // DMA_SLAVE_RESPONDER_SVH
