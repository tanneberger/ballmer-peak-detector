// SPDX-FileCopyrightText: 2026 XXX
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Description: SystemVerilog testbench for the counter module.

`timescale 1ns / 1ps

module fsm_tb;
  // Parameters
  parameter  real CLK_FREQ      = 50.0e6;
  parameter  int  CTR_WIDTH     = 8;
  parameter  int  CTR_MAX       = 2**CTR_WIDTH-1;
  localparam real CLK_PERIOD_NS = 1e9 / CLK_FREQ;

  // Signals
  logic                 clk    = 1'b0;
  logic                 rst_n  = 1'b1; // active-low reset
  logic                 enable = 1'b0;
  logic [CTR_WIDTH-1:0] count;

  // TODO: Instantiate the DUT 

  // Clock generation
  /* verilator lint_off STMTDLY */
  always #(CLK_PERIOD_NS / 2) clk = ~clk;
  /* verilator lint_on STMTDLY */


  // TODO: Read test vector and stream 

  // Self-checking stimulus
  initial begin
    $dumpfile("fsm_tb.fst");
    $dumpvars;

    // Reset pulse (2 clock cycles)
    rst_n = 1'b0;
    #(2 * CLK_PERIOD_NS);
    rst_n = 1'b1;
    #(CLK_PERIOD_NS);

    $display("PASS: simulation complete.");
    $finish;
  end
endmodule // fsm_tb
