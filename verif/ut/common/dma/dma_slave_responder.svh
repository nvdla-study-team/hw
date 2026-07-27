// -----------------------------------------------------------------------------
// dma_slave_responder : DMA slave 内存模型（参数化，阶段2 骨架：编译 + 可实例化）
//   - 写通道 : id=[WR_REQ_W-1]，0=cmd（addr[63:0]，[77]=require_ack）1=data；
//              data beat 按字节写入 mem，地址自增；
//              wr_rsp_complete 仅对 require_ack=1 的命令、其数据收齐语义简化为
//              下一个 cmd 到来前的最后一个 data beat 后返回（骨架实现：收到
//              带 ack 的 cmd 后第一个 data beat 即回一拍 complete）
//   - 读通道 : req {addr,size} -> 按 size+1 个 512-bit beat 回数据，
//              尊重 rd_rsp_prdy；mask=2'b11（两个 256-bit 半拍全有效）
//   - credit : rd_cdt_lat_fifo_pop 脉冲直通计数
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

  localparam int DATA_W  = RD_RSP_W - 2;   // 数据位宽（去掉 mask[1:0]）
  localparam int BYTES_N = DATA_W / 8;

  bit [7:0]    mem [bit [63:0]];
  int unsigned credit_returned;
  int unsigned rd_rsp_dly_min = 0;
  int unsigned rd_rsp_dly_max = 2;

  function new(string name, uvm_component parent);
    super.new(name, parent);
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
      rd_loop();
      wr_loop();
      credit_loop();
    join
  endtask

  task rd_loop();
    bit [63:0]         a;
    bit [14:0]         sz;
    bit [DATA_W-1:0]   beat;
    forever begin
      vif.slv_cb.rd_req_prdy <= 1'b1;
      @(vif.slv_cb);
      if (vif.slv_cb.rd_req_pvld === 1'b1) begin
        a  = vif.slv_cb.rd_req_pd[63:0];
        sz = vif.slv_cb.rd_req_pd[RD_REQ_W-1:64];
        vif.slv_cb.rd_req_prdy <= 1'b0; // 简化：回数期间不收新读请求
        for (int b = 0; b <= sz; b++) begin
          repeat ($urandom_range(rd_rsp_dly_max, rd_rsp_dly_min)) @(vif.slv_cb);
          for (int i = 0; i < BYTES_N; i++)
            beat[i*8 +: 8] = mem.exists(a + i) ? mem[a + i] : 8'h00;
          vif.slv_cb.rd_rsp_pvld <= 1'b1;
          vif.slv_cb.rd_rsp_pd   <= {2'b11, beat}; // mask: 两个 256-bit 半拍全有效
          do @(vif.slv_cb); while (vif.slv_cb.rd_rsp_prdy !== 1'b1);
          vif.slv_cb.rd_rsp_pvld <= 1'b0;
          a += BYTES_N;
        end
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
