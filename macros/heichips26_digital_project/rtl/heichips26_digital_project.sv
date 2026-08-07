// SPDX-FileCopyrightText: © 2026 XXX Authors
// SPDX-License-Identifier: Apache-2.0

// Adapted from the Tiny Tapeout template

`default_nettype none

module heichips26_digital_project (
`ifdef USE_POWER_PINS
    inout  wire VPWR,
    inout  wire VGND,
`endif
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    //   ui_in [7:0]  operand byte (beat 0 = lane 0 / op1, beat 1 = lane 1 / op2)
    //   uio_in[0]    in_valid   -- host has a byte on ui_in
    //   uio_in[1]    m_ready
    //   uio_in[2]    in_mask    -- the byte on ui_in carries data
    //   uio_out[3]   in_ready   -- wrapper takes a byte this cycle
    //   uio_out[4]   m_valid
    //   uio_out[5]   m_mask
    //   uio_out[6]   m_last
    //   uio_out[7]   frame_done
    //   uo_out[7:0]  m_data

    wire in_valid = uio_in[0];
    wire m_ready  = uio_in[1];
    wire in_mask  = uio_in[2];

    wire       s_ready;
    wire       m_valid;
    wire [7:0] m_data;
    wire       m_mask;
    wire       m_last;
    wire       frame_done;

    // mux two 8-bit beats into one 16-bit beat
    reg [7:0] op1_q;
    reg       mask0_q;
    reg       phase_q;   // 0 = next byte is lane 0, 1 = next byte is lane 1

    wire in_ready = phase_q ? s_ready : 1'b1;
    wire in_beat  = in_valid && in_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op1_q   <= 8'h00;
            mask0_q <= 1'b0;
            phase_q <= 1'b0;
        end else if (in_beat) begin
            if (!phase_q) begin
                op1_q   <= ui_in;
                mask0_q <= in_mask;
            end
            phase_q <= ~phase_q;
        end
    end

    wire        s_valid = in_valid && phase_q;
    wire [15:0] s_data  = {ui_in,   op1_q};    // lane 1 = op2, lane 0 = op1
    wire [1:0]  s_mask  = {in_mask, mask0_q};  // bit1 = lane 1, bit0 = lane 0

    top top_0 (
        .s_valid    (s_valid),
        .s_data     (s_data),
        .s_mask     (s_mask),
        .s_ready    (s_ready),

        .m_valid    (m_valid),
        .m_data     (m_data),
        .m_mask     (m_mask),
        .m_last     (m_last),
        .m_ready    (m_ready),

        .frame_done (frame_done),

        .clk        (clk),
        .rst_n      (rst_n)
    );

    assign uo_out  = m_data;
    assign uio_out = {frame_done, m_last, m_mask, m_valid, in_ready, 3'b000};
    assign uio_oe  = 8'b1111_1000;

    // List all unused inputs to prevent warnings.
    // uio_in[7:3] sit on bits this macro drives, so they are never read.
    wire _unused = &{ena, uio_in[7:3]};

endmodule
