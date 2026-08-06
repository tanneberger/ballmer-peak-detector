// -----------------------------------------------------------------------------
// ssm_fsm -- sequencer for one SSM timestep on a single posit FMA port.
//
// Golden model : golden/sequence.py, function sequence()
//
//   x[k] = Lambda*x[k-1] + B@u[k] + b        (Lambda diagonal, complex)
//   y[k] = gate( Re{C@x[k]} + c ) + u        (real out, skip connection)
//
// Source of each FMA port:
//
//   opa (mul1) : the stream (a weight), except the U skip ops where it is the
//                constant 1.0.
//   opb (mul2) : state memory (x.R, x.C), except where it is u -- u is streamed
//                at the point of use, not buffered.
//   opc (add)  : the accumulator register, except at each chain head where it
//                is a streamed bias (2H + U = 20 of them per frame).
//
// So memory holds state only: 2H entries, one read port, no crossbar.
//
// -----------------------------------------------------------------------------
// INPUT STREAM  (host delivers strictly in order -- no addresses, no tags)
//
// Lanes are POSITIONAL, one beat per FMA issue:
//
//   lane 0 (s_data[  W-1:0 ]) = op1 -> fma_opa   always a weight
//   lane 1 (s_data[2*W-1:W ]) = op2 -> fma_opc   at a chain head (bias)
//                                   -> fma_opb   on a u-consuming op
//
// op2 is routed by the FSM, and the two uses never collide: an op that needs u
// never needs a bias, and vice versa. That is what keeps this to two lanes.
// STREAM_LANES must be >= 2; lanes above 1 are reserved/unused.
//
// s_mask says which lanes carry data:
//   01  op1 only
//   11  op1 + op2
//   10  op2 only        (the skip op: opa is the constant 1.0)
//
// Negation is host-side: a token used negated arrives already negated, and so
// costs its own beat (lam.R[i] and lam.C[i] each go out twice per i).
//
// One frame == one timestep == 12*H + U*(2H+1) beats.
// For H=8, U=4 that is 96 + 68 = 164 beats, 248 operand bytes.
//
//   H x 12 beats -- stage 0, per hidden state i
//     lane0        lane1     mask   opb
//     lam.R[i]     b.R[i]     11    mem x.R[i]     <- Re chain head
//     -lam.C[i]    -          01    mem x.C[i]
//     B.R[i,0]     u[0]       11    lane1
//     ..
//     B.R[i,U-1]   u[U-1]     11    lane1
//     lam.C[i]     b.C[i]     11    mem x.R[i]     <- Im chain head
//     lam.R[i]     -          01    mem x.C[i]
//     B.C[i,0]     u[0]       11    lane1
//     ..
//     B.C[i,U-1]   u[U-1]     11    lane1
//
//   U x (2H+1) beats -- stage 1, per output channel i
//     C.R[i,0]     c.R[i]     11    mem x.R[0]     <- chain head
//     -C.C[i,0]    -          01    mem x.C[0]
//     C.R[i,1]     -          01    mem x.R[1]
//     ..
//     -C.C[i,H-1]  -          01    mem x.C[H-1]
//     -            u[i]       10    lane1          <- skip op, opa = 1.0
//
// COST OF STREAMING u: it is resent for every op that reads it, so u goes out
// 2*H*U + U = 68 times per frame instead of U = 4. That is +64 bytes/frame
// (184 -> 248) in exchange for 4 fewer memory entries and no preload state.
// If the stream ever becomes the bottleneck, buffering u again costs U bytes of
// memory and one extra state, and drops the frame to 184 bytes.
//
// -----------------------------------------------------------------------------
// OUTPUT STREAM  (STREAM_LANES byte lanes, valid/ready, mask, plus last)
//
//   y[0] .. y[U-1]                                          <- U bytes/frame
//
// One byte is produced every 2H+1 issues, so the pack unit normally emits a
// single lane per beat and only packs when the consumer backpressures. m_last
// marks the beat carrying y[U-1].
//
// Backpressure reaches the datapath through one gate only: the skip op is the
// sole result-producing issue, so it is the only one that can stall (sink_ok).
// Everything else is unstoppable once issued -- the result lands the next cycle
// whatever the consumer does, which is why the pack FIFO exists at all.
// At OUT_DEPTH = U+2 a whole frame of results fits, so a consumer that drains
// once per frame never stalls the compute.
//
// -----------------------------------------------------------------------------
// LATENCY
//
// FIXED AT 1: fma_res is valid the cycle after fma_issue. That is exactly the
// slack the accumulator recurrence (acc -> FMA -> acc) needs, so the FSM issues
// one op per cycle with no gaps and the writeback pipe is a single register.
//
// To pipeline the FMA deeper later, the recurrence needs an issue gap >= the
// latency, and this file needs:
//   - a gap countdown reloaded after each issue
//   - wb_v / wb_dst / wb_relu / wb_last deepened to match
//
// Stage 0 could then absorb a gap of 2 for free by interleaving the Re and Im
// chains, since each would be touched only every other issue -- but that
// changes the issue order and therefore the host's beat order. Stage 1 could
// not: one acc, nothing independent to interleave, so it would stall outright
// and dominate the frame. Splitting stage 1 into Re/Im partial sums fixes that
// but REASSOCIATES the sum, and posit8 rounding is not associative: it would
// stop bit-matching sequence.py. Change the golden model first if you go there.
//
// -----------------------------------------------------------------------------

`default_nettype none

module ssm_fsm #(
    parameter integer W            = 8,   // posit width
    parameter integer H            = 8,   // n_hidden
    parameter integer U            = 4,   // n_inout
    parameter integer STREAM_LANES = 2    // >= 2; lane 0 = op1, lane 1 = op2
) (
    input  wire                          clk,
    input  wire                          rst_n,

    // ---- stream in ----
    input  wire                          s_valid,
    input  wire [STREAM_LANES*W-1:0]     s_data,
    input  wire [STREAM_LANES-1:0]       s_mask,
    output wire                          s_ready,

    // ---- FMA port ----
    output wire [W-1:0]                  fma_opa,
    output wire [W-1:0]                  fma_opb,
    output wire [W-1:0]                  fma_opc,
    output wire                          fma_issue,
    input  wire [W-1:0]                  fma_res,   // valid 1 cycle after issue

    // ---- state memory: 2H x W, async read, sync write ----
    // Flop array / register file, state only -- u is not buffered here. With a
    // sync-read SRAM the read address must be driven a cycle early: see TODO.
    output wire [4:0]                    mem_raddr,
    input  wire [W-1:0]                  mem_rdata,
    output reg  [4:0]                    mem_waddr,
    output reg  [W-1:0]                  mem_wdata,
    output reg                           mem_we,

    // ---- stream out ----
    output wire                          m_valid,
    output wire [STREAM_LANES*W-1:0]     m_data,
    output wire [STREAM_LANES-1:0]       m_mask,
    output wire                          m_last,    // beat carries y[U-1]
    input  wire                          m_ready,

    output reg                           frame_done
);

    // -------------------------------------------------------------------------
    // derived sizes
    // -------------------------------------------------------------------------
    localparam integer X_R    = 0;                // memory map: x.R | x.C
    localparam integer X_C    = H;
    localparam integer MEMD   = 2*H;

    localparam integer S0_OPS = 2*(U + 2);        // 12 FMAs per hidden state
    localparam integer S0_LEN = S0_OPS + 2;       // + 2 commit cycles
    localparam integer S1_OPS = 2*H + 1;          // 17 FMAs per output channel

    localparam integer OUT_DEPTH = U + 2;         // U results + in-flight + slack

    // posit 1.0 : sign 0, regime "10", exponent 0, fraction 0
    localparam [W-1:0] POSIT_ONE = {2'b01, {(W-2){1'b0}}};

    // writeback destinations
    localparam [1:0] D_XR = 2'd0, D_XC = 2'd1, D_ACC = 2'd2, D_Y = 2'd3;

    // -------------------------------------------------------------------------
    // positional stream lanes
    // -------------------------------------------------------------------------
    wire [W-1:0] lane_op1 = s_data[0*W +: W];
    wire [W-1:0] lane_op2 = s_data[1*W +: W];

    // -------------------------------------------------------------------------
    // stream pack: 1 byte/cycle in -> STREAM_LANES masked lanes out
    //
    // y bytes are produced U times per frame, 2H+1 issues apart, so this almost
    // always emits a single lane. It packs only if the consumer backpressures.
    // -------------------------------------------------------------------------
    reg           out_push;
    reg  [W-1:0]  out_data;
    reg           out_last;
    wire [3:0]    out_level;
    wire          out_empty = (out_level == 0);
    // one slot reserved for the result already in the writeback pipe
    wire          out_space = (out_level < (OUT_DEPTH - 1));

    stream_pack #(
        .W (W), .LANES (STREAM_LANES), .DEPTH (OUT_DEPTH)
    ) u_pack (
        .clk (clk), .rst_n (rst_n),
        .push (out_push), .push_data (out_data), .push_last (out_last),
        .level (out_level),
        .m_valid (m_valid), .m_data (m_data), .m_mask (m_mask),
        .m_last (m_last), .m_ready (m_ready)
    );

    // -------------------------------------------------------------------------
    // control state
    // -------------------------------------------------------------------------
    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_S0     = 3'd1,
                     ST_S0_CMT = 3'd2,   // drain the pipe, then 2 memory writes
                     ST_S1     = 3'd3,
                     ST_DRAIN  = 3'd4,
                     ST_DONE   = 3'd5;

    reg [2:0] st;
    reg [3:0] i_cnt;      // hidden state (stage 0) / output channel (stage 1)
    reg [4:0] k_cnt;      // op index inside the current i iteration

    wire in_s0 = (st == ST_S0);
    wire in_s1 = (st == ST_S1);

    // stage 0 decode of k_cnt -> (slot, part): whole Re chain, then Im chain
    //   slot 0      : lam * x.R[i]   (+ bias on op2)
    //   slot 1      : lam * x.C[i]
    //   slot 2..U+1 : B[i,slot-2] * u[slot-2]   (u on op2)
    wire [4:0] s0_slot = (k_cnt >= (U+2)) ? (k_cnt - (U+2)) : k_cnt;
    wire       s0_part = (k_cnt >= (U+2));

    // stage 1 decode: k = 2*j + part, last k is the skip op
    wire [4:0] s1_j    = k_cnt >> 1;
    wire       s1_part = k_cnt[0];
    wire       s1_skip = (k_cnt == S1_OPS - 1);

    // -------------------------------------------------------------------------
    // accumulators (registers)
    // -------------------------------------------------------------------------
    reg [W-1:0] x_int_r, x_int_c, acc;

    // -------------------------------------------------------------------------
    // operand selection (combinational, meaningful while advancing)
    // -------------------------------------------------------------------------

    // lane 0 -- always a weight, absent only on the skip op
    wire need_op1  = in_s0 || (in_s1 && !s1_skip);

    // lane 1 -- a bias at a chain head, or u on a u-consuming op. Never both:
    // the ops that read u are exactly the ops that do not seed an accumulator.
    wire need_bias = (in_s0 && (s0_slot == 0)) || (in_s1 && (k_cnt == 0));
    wire need_u    = (in_s0 && (s0_slot >= 2)) || (in_s1 && s1_skip);
    wire need_op2  = need_bias || need_u;

    wire beat_req  = need_op1 || need_op2;

    // opa: streamed weight, or the constant 1.0 for the skip op
    assign fma_opa = need_op1 ? lane_op1 : POSIT_ONE;

    // opc: streamed bias at each chain head, otherwise the accumulator
    wire [W-1:0] acc_sel = in_s0 ? (s0_part ? x_int_c : x_int_r) : acc;
    assign fma_opc = need_bias ? lane_op2 : acc_sel;

    // opb: streamed u, otherwise state memory
    // TODO: for a sync-read SRAM, register rd_addr one cycle ahead of issue.
    reg [4:0] rd_addr;
    always @* begin
        rd_addr = 5'd0;
        if (in_s0) begin
            if (s0_slot == 0) rd_addr = X_R + i_cnt;               // x.R[i]
            else              rd_addr = X_C + i_cnt;               // x.C[i]
        end else if (in_s1) begin
            rd_addr = (s1_part ? X_C : X_R) + s1_j;                // x.{R,C}[j]
        end
    end
    assign mem_raddr = rd_addr;
    assign fma_opb   = need_u ? lane_op2 : mem_rdata;

    // -------------------------------------------------------------------------
    // handshake / issue gating
    //
    // s_ready must not depend on s_valid, so it is built from the local
    // conditions only; advance then adds the s_valid term.
    // -------------------------------------------------------------------------

    // only the skip op produces an output byte, so only it can be backpressured
    wire is_emit = in_s1 && s1_skip;
    wire sink_ok = !is_emit || out_space;

    wire step_ok = (in_s0 || in_s1) && sink_ok;
    wire advance = step_ok && (!beat_req || s_valid);

    assign s_ready   = step_ok && beat_req;
    assign fma_issue = advance;

    wire issue_ok = fma_issue;

    // -------------------------------------------------------------------------
    // writeback control: the destination travels with the op. At 1-cycle FMA
    // latency this is a single register stage; deepen it into a shift register
    // if the FMA is ever pipelined.
    // -------------------------------------------------------------------------
    reg       wb_v;
    reg [1:0] wb_dst;
    reg       wb_relu;
    reg       wb_last;

    wire [1:0] issue_dst = in_s0 ? (s0_part ? D_XC : D_XR)
                                 : (s1_skip ? D_Y : D_ACC);

    // y[U-1] closes the output frame
    wire issue_last = is_emit && (i_cnt == U - 1);

    // The gate is on the PRE-skip accumulator but the emitted value is the
    // POST-skip result:  y = (pre > 0) ? (u + pre) : 0   -- sequence.py:220.
    // Sign bit alone is not "> 0": posit zero is 0x00, sign 0.
    wire relu_pos = ~acc[W-1] & (|acc[W-2:0]);

    wire       wb_v_out    = wb_v;
    wire [1:0] wb_dst_out  = wb_dst;
    wire       wb_relu_out = wb_relu;
    wire       wb_last_out = wb_last;
    wire       wb_busy     = wb_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_v    <= 1'b0;
            wb_dst  <= 2'd0;
            wb_relu <= 1'b0;
            wb_last <= 1'b0;
        end else begin
            wb_v    <= issue_ok;
            wb_dst  <= issue_dst;
            wb_relu <= relu_pos;
            wb_last <= issue_last;
        end
    end

    // -------------------------------------------------------------------------
    // accumulator writeback
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_int_r <= {W{1'b0}};
            x_int_c <= {W{1'b0}};
            acc     <= {W{1'b0}};
        end else if (wb_v_out) begin
            case (wb_dst_out)
                D_XR : x_int_r <= fma_res;
                D_XC : x_int_c <= fma_res;
                D_ACC: acc     <= fma_res;
                D_Y  : ;                     // goes to the output stream instead
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // result -> output stream (combinational off the writeback register, so the
    // byte is pushed the same cycle fma_res is valid -- no extra latency)
    // -------------------------------------------------------------------------
    always @* begin
        out_push = wb_v_out && (wb_dst_out == D_Y);
        out_data = wb_relu_out ? fma_res : {W{1'b0}};
        out_last = wb_last_out;
    end

    // -------------------------------------------------------------------------
    // memory write port: the x commit at the end of each stage-0 iteration.
    //
    // The commit is 2 explicit cycles rather than being fused onto the last op
    // of each chain. Fusing saves 2*H cycles but reintroduces a write-after-read
    // hazard on x.R[i]: the Im chain still reads the OLD x.R[i] at its slot 0,
    // and it runs after the whole Re chain. See sequence.py:175-177.
    // -------------------------------------------------------------------------
    always @* begin
        mem_we    = 1'b0;
        mem_waddr = 5'd0;
        mem_wdata = x_int_r;

        if (st == ST_S0_CMT && !wb_busy) begin
            mem_we = 1'b1;
            if (k_cnt == S0_OPS) begin
                mem_waddr = X_R + i_cnt;
                mem_wdata = x_int_r;
            end else begin
                mem_waddr = X_C + i_cnt;
                mem_wdata = x_int_c;
            end
        end
    end

    // -------------------------------------------------------------------------
    // sequencer
    //
    //                            reset
    //                              |
    //                              v
    //                        +-----------+
    //                        |  ST_IDLE  |<--+  !s_valid
    //                        +-----------+---+
    //                              |  s_valid              i_cnt<=0, k_cnt<=0
    //                              v
    //                        +-----------+
    //                    +-->|   ST_S0   |<--+  !s_valid
    //                    |   +-----------+---+
    //                    |         |          12 beats  (k = 0..S0_OPS-1)
    //                    |         |          mask 11 at k=0, k=U+2   (bias)
    //                    |         |          mask 11 at slot >= 2    (u)
    //                    |         |          dst = k < U+2 ? x_int_r : x_int_c
    //                    |         |  k == S0_OPS-1
    //                    |         v
    //                    |   +-----------+
    //                    |   | ST_S0_CMT |<--+  wb_busy
    //                    |   +-----------+---+
    //                    |       |    |       no beats, no issues -- 3 cycles
    //                    +-------+    |       k=12: mem[  i] <= x_int_r
    //           i_cnt < H-1, i_cnt++  |       k=13: mem[H+i] <= x_int_c
    //                                 |  i_cnt == H-1
    //                                 v
    //                        +-----------+
    //                        |   ST_S1   |<--+  !s_valid, or !out_space at k=2H
    //                        +-----------+---+
    //                              |          2H+1 beats (k = 0..2H)
    //                              |          mask 11 at k=0 (bias)
    //                              |          mask 10 at k=2H: skip op, emits y[i]
    //                              |  i_cnt == U-1
    //                              v
    //                        +-----------+
    //                        | ST_DRAIN  |<--+  wb_busy || !out_empty
    //                        +-----------+---+
    //                              |
    //                              v
    //                        +-----------+
    //                        |  ST_DONE  | ----> ST_IDLE   frame_done, 1 cycle
    //                        +-----------+
    //
    // Only ST_S0 and ST_S1 issue FMAs, and both consume one beat per issue.
    // ST_S0_CMT / ST_DRAIN / ST_DONE do neither -- they exist purely to let the
    // 1-cycle FMA result land before it is read back.
    //
    // Cycle budget, H=8 U=4, stream never starved and consumer keeping up:
    //
    //   ST_IDLE      1                            =   1
    //   ST_S0        S0_OPS      x H  = 12 x 8    =  96
    //   ST_S0_CMT    3           x H  =  3 x 8    =  24   (1 drain + 2 writes)
    //   ST_S1        S1_OPS      x U  = 17 x 4    =  68
    //   ST_DRAIN     2 (min)                      =   2
    //   ST_DONE      1                            =   1
    //                                             -------
    //                                               192 cycles / timestep
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= ST_IDLE;
            i_cnt      <= 4'd0;
            k_cnt      <= 5'd0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            case (st)

            // ---- wait for the first beat of a frame -------------------------
            ST_IDLE: begin
                i_cnt <= 4'd0;
                k_cnt <= 5'd0;
                if (s_valid) st <= ST_S0;
            end

            // ---- stage 0: x[k] = lam*x[k-1] + B@u + b -----------------------
            ST_S0: begin
                if (issue_ok) begin
                    if (k_cnt == S0_OPS - 1) begin
                        k_cnt <= S0_OPS[4:0];
                        st    <= ST_S0_CMT;
                    end else begin
                        k_cnt <= k_cnt + 1'b1;
                    end
                end
            end

            // ---- commit x_int -> memory, then next i ------------------------
            ST_S0_CMT: begin
                if (!wb_busy) begin
                    if (k_cnt == S0_LEN - 1) begin
                        k_cnt <= 5'd0;
                        if (i_cnt == H - 1) begin
                            i_cnt <= 4'd0;
                            st    <= ST_S1;
                        end else begin
                            i_cnt <= i_cnt + 1'b1;
                            st    <= ST_S0;
                        end
                    end else begin
                        k_cnt <= k_cnt + 1'b1;
                    end
                end
            end

            // ---- stage 1: y = gate(Re{C@x} + c) + u -------------------------
            ST_S1: begin
                if (issue_ok) begin
                    if (k_cnt == S1_OPS - 1) begin
                        k_cnt <= 5'd0;
                        if (i_cnt == U - 1) st <= ST_DRAIN;
                        else                i_cnt <= i_cnt + 1'b1;
                    end else begin
                        k_cnt <= k_cnt + 1'b1;
                    end
                end
            end

            // wait for the pipe to empty AND the last y byte to be accepted,
            // so a frame never overlaps the tail of the previous one
            ST_DRAIN: if (!wb_busy && out_empty) st <= ST_DONE;

            ST_DONE: begin
                frame_done <= 1'b1;
                st         <= ST_IDLE;
            end

            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// stream_pack -- 1 byte/cycle in, up to LANES masked byte lanes out.
//
// TODO: implement.
//   on (m_valid && m_ready): emit n = min(level, LANES) bytes, oldest in lane 0,
//                            m_mask = (1<<n)-1
//   m_valid = (level != 0)
//   m_last  = the last-tagged byte is in this beat  (tag travels with the byte)
//   push is never asserted when full: the producer checks level first
// -----------------------------------------------------------------------------
module stream_pack #(
    parameter integer W     = 8,
    parameter integer LANES = 2,
    parameter integer DEPTH = 6
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               push,
    input  wire [W-1:0]       push_data,
    input  wire               push_last,
    output wire [3:0]         level,
    output wire               m_valid,
    output wire [LANES*W-1:0] m_data,
    output wire [LANES-1:0]   m_mask,
    output wire               m_last,
    input  wire               m_ready
);
endmodule

`default_nettype wire
