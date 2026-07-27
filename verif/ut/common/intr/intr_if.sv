// -----------------------------------------------------------------------------
// intr_if : 中断线 interface（monitor-only）
// -----------------------------------------------------------------------------
interface intr_if (input logic clk, input logic rstn);

  logic intr;

  clocking mon_cb @(posedge clk);
    default input #1step;
    input intr;
  endclocking

endinterface : intr_if
