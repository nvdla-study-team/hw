// -----------------------------------------------------------------------------
// ut_base_test : 全部 UT 测试基类
//   - +ut_timeout_us=N（默认 500）设置 UVM 全局超时
//   - final_phase 按 report server 计数打 "UT RESULT: PASSED/FAILED" 横幅，
//     make check 以该横幅 + UVM_ERROR/UVM_FATAL 计数 + 无 "^ERROR :" 判定
// -----------------------------------------------------------------------------
`ifndef UT_BASE_TEST_SVH
`define UT_BASE_TEST_SVH

class ut_base_test extends uvm_test;

  int unsigned timeout_us = 500;

  `uvm_component_utils(ut_base_test)

  function new(string name = "ut_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("ut_timeout_us=%d", timeout_us));
    uvm_root::get().set_timeout(timeout_us * 1us, 1);
    `uvm_info(get_type_name(),
              $sformatf("global timeout set to %0d us", timeout_us), UVM_LOW)
  endfunction

  virtual function void final_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    super.final_phase(phase);
    if (svr.get_severity_count(UVM_FATAL) == 0 &&
        svr.get_severity_count(UVM_ERROR) == 0) begin
      $display("=======================================");
      $display("UT RESULT: PASSED");
      $display("=======================================");
    end
    else begin
      $display("=======================================");
      $display("UT RESULT: FAILED  (UVM_FATAL=%0d UVM_ERROR=%0d)",
               svr.get_severity_count(UVM_FATAL),
               svr.get_severity_count(UVM_ERROR));
      $display("=======================================");
    end
  endfunction

endclass : ut_base_test

`endif // UT_BASE_TEST_SVH
