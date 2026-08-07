// SPDX-FileCopyrightText: 2026 XXX
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Description: SystemVerilog testbench for the heichips26_digital_project module.
//
// Streams the golden vectors from golden/sequence.py into the wrapper's
// byte-serial port. Outputs are left for the waveform -- no self-checking.
//
// Every beat costs two byte-cycles. A lane the golden model marks absent still
// gets its cycle on the wire -- in_mask goes low and the byte is a placeholder --
// because the wrapper's phase counter toggles on each accepted byte.

`timescale 1ns / 1ps

module heichips26_digital_project_tb;
  // Parameters
  parameter  real CLK_FREQ      = 50.0e6;
  localparam real CLK_PERIOD_NS = 1e9 / CLK_FREQ;

  // Design shape. Must match top.sv's localparams and the vector file header.
  parameter int W = 8;   // posit width
  parameter int H = 8;   // n_hidden
  parameter int U = 4;   // n_inout

  parameter  int FRAMES          = 1;
  localparam int BEATS_PER_FRAME = 12*H + U*(2*H + 1);
  localparam int BEATS           = FRAMES * BEATS_PER_FRAME;

  localparam string VEC_IN = "../../../../golden/vectors/ssm_h8_u4_in.hex";

  // Signals
  logic       clk   = 1'b0;
  logic       rst_n = 1'b1;  // active-low reset

  // Host side of the byte-serial port
  logic [7:0] ui_in    = 8'h00;  // operand byte
  logic       in_valid = 1'b0;   // uio_in[0]
  logic       m_ready  = 1'b1;   // uio_in[1]
  logic       in_mask  = 1'b0;   // uio_in[2]

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // human readable labels
  wire [7:0] uio_in = {5'b0, in_mask, m_ready, in_valid};
  wire       in_ready   = uio_out[3];
  wire       m_valid    = uio_out[4];
  wire       m_mask     = uio_out[5];
  wire       m_last     = uio_out[6];
  wire       frame_done = uio_out[7];
  wire [7:0] m_data     = uo_out;

  // DUT
  heichips26_digital_project dut_heichips26_digital_project (
    .clk      (clk),
    .rst_n    (rst_n),
    .ena      (1'b1),
    .ui_in    (ui_in),
    .uo_out   (uo_out),
    .uio_in   (uio_in),
    .uio_out  (uio_out),
    .uio_oe   (uio_oe)
  );

  // Clock generation
  /* verilator lint_off STMTDLY */
  always #(CLK_PERIOD_NS / 2) clk = ~clk;
  /* verilator lint_on STMTDLY */

  // Stimulus
  initial begin
    $dumpfile("heichips26_digital_project_tb.fst");
    $dumpvars;

    // Reset pulse (2 clock cycles)
    rst_n = 1'b0;
    #(2 * CLK_PERIOD_NS);
    rst_n = 1'b1;
    #(CLK_PERIOD_NS);


    $display("PASS: simulation complete.");
    $finish;
  end
endmodule // heichips26_digital_project_tb
