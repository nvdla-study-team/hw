// -----------------------------------------------------------------------------
// csb_master_driver : CSB 单口面 master driver（falcon 域）
//   - 拉 valid 等 ready 握手，握手后撤 valid
//   - 带响应事务（读 / nposted 写）串行化：等到 rvalid / wr_complete 才 item_done。
//     原因1：DUT 响应汇聚是 OR-mux 无仲裁 + 19 路 zero_one_hot 断言；
//     原因2：每路目的地出口只有 1 级保持寄存器，持续背压下第二笔会覆盖。
//   - posted 写无响应，可流水。
//   - 等响应超时（默认 2000 falcon 拍）报 uvm_error 后放行，避免整测卡死。
// -----------------------------------------------------------------------------
`ifndef CSB_MASTER_DRIVER_SVH
`define CSB_MASTER_DRIVER_SVH

class csb_master_driver extends uvm_driver #(csb_seq_item);

  virtual csb_if vif;
  int unsigned   resp_timeout_cycles = 2000;

  `uvm_component_utils(csb_master_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    csb_seq_item tr;

    if (vif == null)
      `uvm_fatal(get_type_name(), "csb_master_driver has no virtual interface")

    drive_idle();
    wait (vif.rstn === 1'b1);
    repeat (2) @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(tr);

      if (vif.rstn !== 1'b1) begin // 复位期间输出清零并等待释放
        drive_idle();
        wait (vif.rstn === 1'b1);
        repeat (2) @(vif.drv_cb);
      end

      repeat (tr.idle_before) @(vif.drv_cb);

      // 发请求，等握手
      vif.drv_cb.valid   <= 1'b1;
      vif.drv_cb.addr    <= tr.addr;
      vif.drv_cb.wdat    <= tr.wdat;
      vif.drv_cb.write   <= tr.write;
      vif.drv_cb.nposted <= tr.nposted;
      do @(vif.drv_cb); while (vif.drv_cb.ready !== 1'b1);
      drive_idle();

      if (tr.expects_resp())
        wait_resp(tr);

      seq_item_port.item_done();
    end
  endtask

  task drive_idle();
    vif.drv_cb.valid   <= 1'b0;
    vif.drv_cb.addr    <= '0;
    vif.drv_cb.wdat    <= '0;
    vif.drv_cb.write   <= 1'b0;
    vif.drv_cb.nposted <= 1'b0;
  endtask

  // 等待读数据 / 写完成，带超时（隔离 fork，join_any 后 disable）
  task wait_resp(csb_seq_item tr);
    fork begin : isolation
      fork
        begin
          forever begin
            @(vif.drv_cb);
            if (!tr.write && vif.drv_cb.rvalid === 1'b1) begin
              tr.rdat       = vif.drv_cb.rdata;
              tr.got_rvalid = 1'b1;
              break;
            end
            if (tr.write && vif.drv_cb.wr_complete === 1'b1) begin
              tr.got_wr_complete = 1'b1;
              break;
            end
          end
        end
        begin
          repeat (resp_timeout_cycles) @(vif.drv_cb);
          tr.timed_out = 1'b1;
          `uvm_error(get_type_name(),
                     $sformatf("response timeout (%0d falcon cycles): %s",
                               resp_timeout_cycles, tr.convert2string()))
        end
      join_any
      disable fork;
    end join
  endtask

endclass : csb_master_driver

`endif // CSB_MASTER_DRIVER_SVH
