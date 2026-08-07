// SPDX-FileCopyrightText: © 2026 XXX Authors
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module top (
    // Assume muxing inside the eFPGA -> 40 general purpose IO pins
    // If chip IO will have 16 in, 16 out, then we'll have to do some multiplexing inside the eFPGA.

    // Stream in: 17 pins -- two 8-bit lanes per beat, no mask: the schedule is
    // fixed, so each lane's role follows from the FSM state alone.
    input  wire        s_valid,
    input  wire [15:0] s_data,   // lane 0 = op1, lane 1 = op2
    output wire        s_ready,  // 1 pin

    // Stream out: 11 pins
    output wire        m_valid,
    output wire [7:0]  m_data,
    output wire        m_last,
    input  wire        m_ready,  // 1 pin

    output wire       frame_done,

    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);                              // 33 pins of 40

    localparam int unsigned W         = 8;   // posit width
    localparam int unsigned H         = 8;   // n_hidden
    localparam int unsigned U         = 4;   // n_inout
    localparam int unsigned LANES_IN  = 2;   // lane 0 = op1, lane 1 = op2
    localparam int unsigned LANES_OUT = 1;

    // ---- FSM + FMA ----------------------------------------------------------
    logic [W-1:0] fma_opa, fma_opb, fma_opc, fma_res_c, fma_res_q;

    ssm_fsm #(
        .W                (W),
        .H                (H),
        .U                (U),
        .STREAM_LANES_IN  (LANES_IN),
        .STREAM_LANES_OUT (LANES_OUT)
    ) ssm_fsm_0 (
        .clk        (clk),
        .rst_n      (rst_n),

        .s_valid    (s_valid),
        .s_data     (s_data),
        .s_ready    (s_ready),

        .fma_opa    (fma_opa),
        .fma_opb    (fma_opb),
        .fma_opc    (fma_opc),
        .fma_res    (fma_res_q),

        .m_valid    (m_valid),
        .m_data     (m_data),
        .m_last     (m_last),
        .m_ready    (m_ready),

        .frame_done (frame_done)
    );

    // The FMA macro is combinational end to end (its i_clk is unused), while
    // the FSM's writeback expects the result of the op issued last cycle. The
    // result register lives here; it also keeps the posit decode-mul-add-encode
    // path out of the accumulator feedback loop.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) fma_res_q <= '0;
        else        fma_res_q <= fma_res_c;
    end

    // placeholder - to be added.
    (* keep *) fma #(
    ) fma_0 (
        .clk      (clk),
        //.rst      (~rst_n),   // fma.vhd resets active high
        .i_opa    (fma_opa),
        .i_opb    (fma_opb),
        .i_opc    (fma_opc),
        .o_result (fma_res_c)
    );

endmodule

`default_nettype wire
