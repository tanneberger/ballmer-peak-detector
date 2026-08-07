`default_nettype none

module ssm_fsm #(
    parameter integer W            = 8,   // posit width
    parameter integer H            = 8,   // n_hidden
    parameter integer U            = 4,   // n_inout
    parameter integer STREAM_LANES_IN = 2,   // >= 2; lane 0 = op1, lane 1 = op2
    parameter integer STREAM_LANES_OUT = 1
) (
    input  wire                          clk,
    input  wire                          rst_n,


    // in_intrf
    input  wire                          s_valid,
    input  wire [STREAM_LANES_IN*W-1:0]     s_data,
    input  wire [STREAM_LANES_IN-1:0]       s_mask,
    output wire                          s_ready,

    // FMA datapath
    output reg  [W-1:0]                  fma_opa,
    output reg  [W-1:0]                  fma_opb,
    output reg  [W-1:0]                  fma_opc,
    input  wire [W-1:0]                  fma_res,   // combinational: valid now

    // out_intrf 
    output wire                          m_valid,
    output wire [STREAM_LANES_OUT*W-1:0]     m_data,
    output wire [STREAM_LANES_OUT-1:0]       m_mask,
    output wire                          m_last,    // beat carries y[U-1]
    input  wire                          m_ready,

    output reg                           frame_done
);

    localparam integer XDEPTH = 2*H;

    localparam integer S0_OPS = 2*(U + 2);
    localparam integer S1_OPS = 2*H + 1;

    localparam [4:0] S0_HALF  = S0_OPS[4:0] >> 1;
    localparam [4:0] S0_LAST  = S0_OPS[4:0] - 5'd1;
    localparam [4:0] S1_LAST  = S1_OPS[4:0] - 5'd1;
    localparam [3:0] H_LAST   = H[3:0] - 4'd1;
    localparam [3:0] U_LAST   = U[3:0] - 4'd1;
    localparam [1:0] CMT_LAST = 2'd1;

    localparam [W-1:0] POSIT_ONE = {2'b01, {(W-2){1'b0}}};

    // legal states
    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_S0     = 3'd1,
                     ST_S0_CMT = 3'd2,
                     ST_S1     = 3'd3,
                     ST_DRAIN  = 3'd4,
                     ST_DONE   = 3'd5;

    // writeback destination IDs
    localparam [1:0] DST_XINT_R = 2'd0,
                     DST_XINT_C = 2'd1,
                     DST_ACC    = 2'd2,
                     DST_Y      = 2'd3;

    reg [2:0] state_reg;
    reg [3:0] i_cnt;
    reg [4:0] k_cnt;
    reg [1:0] cmt_cnt;

    // accumulators
    reg [W-1:0] x_int_r, x_int_c, acc;

    // streaming inputs data 
    wire [W-1:0] lane0 = s_data[0*W +: W];
    wire [W-1:0] lane1 = s_data[1*W +: W];

    wire [4:0] s0_slot = (k_cnt >= S0_HALF) ? (k_cnt - S0_HALF) : k_cnt;
    wire       s0_part = (k_cnt >= S0_HALF);
    wire       s1_skip = (k_cnt == S1_LAST);

    // ========================================================================
    // Shift register
    wire [W-1:0] x_head;   // x.R[i]
    wire [W-1:0] x_next;   // x.C[i]

    reg          x_shift;
    reg          x_load;
    reg  [W-1:0] x_inject;

    shift_register #(
        .WIDTH    (W),
        .DEPTH    (XDEPTH)
    ) shift_register_inst_0 (
        .clk_i    (clk),
        .rst_ni   (rst_n),
        .shift_i  (x_shift),
        .load_i   (x_load),
        .inject_i (x_inject),
        .out0_o   (x_head),
        .out1_o   (x_next)
    );
    // ========================================================================

    reg       wb_v;
    reg [1:0] wb_dst;
    reg       wb_gate;
    reg       wb_last;

    // input mux -- opa*opb + opc
    //
    //   ST_S0 slot 0      :  lam.{R,C}[i] * x.{R,R}[i] + bias   (chain head)
    //   ST_S0 slot 1      : -lam.{C,R}[i] * x.{C,C}[i] + x_int
    //   ST_S0 slot 2..U+1 :  B.{R,C}[i,j] * u[j]       + x_int
    //   ST_S1 k == 0      :  C[i,0]       * x[0]       + bias   (chain head)
    //   ST_S1 k <  2H     :  C[i,k]       * x[k]       + acc
    //   ST_S1 skip        :  1.0          * u[i]       + acc
    //
    // The sign on the Re-chain lam.C term is folded into the streamed weight.
    
    always @* begin
        fma_opa = lane0;                                        // 2:1
        fma_opb = x_head;                                       // 3:1
        fma_opc = acc;                                          // 4:1

        if (state_reg == ST_S0) begin
            fma_opc = s0_part ? x_int_c : x_int_r;

            if (s0_slot == 5'd0)
                fma_opc = lane1;                                // bias seeds it
            else if (s0_slot == 5'd1)
                fma_opb = x_next;                               // other x half
            else
                fma_opb = lane1;                                // streamed u
        end else if (state_reg == ST_S1) begin
            if (k_cnt == 5'd0)
                fma_opc = lane1;                                // bias seeds it

            if (s1_skip) begin
                fma_opa = POSIT_ONE;                            // y = u + acc
                fma_opb = lane1;
            end
        end
    end

    reg [W-1:0] y_data;
    reg         y_valid;
    reg         y_last;

    wire emit    = (state_reg == ST_S1) && s1_skip;
    wire step_ok = ((state_reg == ST_S0) || (state_reg == ST_S1)) && (!emit || !y_valid);

    assign s_ready = step_ok;

    // "commit this step": operands on the bus are real, so keep the result and
    // advance. The FMA has no enable of its own -- it is always computing.
    wire step = step_ok && s_valid;

    wire [1:0] issue_dst  = (state_reg == ST_S0) ? (s0_part ? DST_XINT_C : DST_XINT_R)
                                          : (s1_skip ? DST_Y : DST_ACC);
    wire       issue_last = emit && (i_cnt == U_LAST);

    // acc as it will read once any in-flight writeback lands. The ReLU gate is
    // sampled at issue time, one cycle before the previous FMA result reaches
    // the acc register, so the register alone is stale for the skip op.
    wire [W-1:0] acc_fwd  = (wb_v && (wb_dst == DST_ACC)) ? fma_res : acc;
    wire       acc_pos    = ~acc_fwd[W-1] & (|acc_fwd[W-2:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_v    <= 1'b0;
            wb_dst  <= DST_XINT_R;
            wb_gate <= 1'b0;
            wb_last <= 1'b0;
        end else begin
            wb_v    <= step;
            wb_dst  <= issue_dst;
            wb_gate <= acc_pos;
            wb_last <= issue_last;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_int_r <= {W{1'b0}};
            x_int_c <= {W{1'b0}};
            acc     <= {W{1'b0}};
        end else if (wb_v) begin
            case (wb_dst)
                DST_XINT_R: x_int_r <= fma_res;
                DST_XINT_C: x_int_c <= fma_res;
                DST_ACC   : acc     <= fma_res;
                DST_Y     : ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_data  <= {W{1'b0}};
            y_valid <= 1'b0;
            y_last  <= 1'b0;
        end else if (wb_v && (wb_dst == DST_Y)) begin
            y_data  <= wb_gate ? fma_res : {W{1'b0}};
            y_valid <= 1'b1;
            y_last  <= wb_last;
        end else if (y_valid && m_ready) begin
            y_valid <= 1'b0;
            y_last  <= 1'b0;
        end
    end

    assign m_valid = y_valid;
    assign m_data  = y_data;
    assign m_mask  = 1'b1;
    assign m_last  = y_last;

    always @* begin
        x_shift  = 1'b0;
        x_load   = 1'b0;
        x_inject = x_int_r;

        if (state_reg == ST_S0_CMT) begin
            x_shift  = 1'b1;
            x_load   = 1'b1;
            x_inject = (cmt_cnt == 2'd0) ? x_int_r : x_int_c;
        end else if ((state_reg == ST_S1) && step && !s1_skip) begin
            x_shift = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg         <= ST_IDLE;
            i_cnt      <= 4'd0;
            k_cnt      <= 5'd0;
            cmt_cnt    <= 2'd0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            case (state_reg)

            ST_IDLE: begin
                i_cnt   <= 4'd0;
                k_cnt   <= 5'd0;
                cmt_cnt <= 2'd0;
                if (s_valid) state_reg <= ST_S0;
            end

            ST_S0: begin
                if (step) begin
                    if (k_cnt == S0_LAST) begin
                        k_cnt   <= 5'd0;
                        cmt_cnt <= 2'd0;
                        state_reg      <= ST_S0_CMT;
                    end else begin
                        k_cnt <= k_cnt + 1'b1;
                    end
                end
            end

            ST_S0_CMT: begin
                if (cmt_cnt == CMT_LAST) begin
                    cmt_cnt <= 2'd0;
                    if (i_cnt == H_LAST) begin
                        i_cnt <= 4'd0;
                        state_reg    <= ST_S1;
                    end else begin
                        i_cnt <= i_cnt + 1'b1;
                        state_reg    <= ST_S0;
                    end
                end else begin
                    cmt_cnt <= cmt_cnt + 1'b1;
                end
            end

            ST_S1: begin
                if (step) begin
                    if (k_cnt == S1_LAST) begin
                        k_cnt <= 5'd0;
                        if (i_cnt == U_LAST) state_reg <= ST_DRAIN;
                        else                 i_cnt <= i_cnt + 1'b1;
                    end else begin
                        k_cnt <= k_cnt + 1'b1;
                    end
                end
            end

            ST_DRAIN: if (!wb_v && !y_valid) state_reg <= ST_DONE;

            ST_DONE: begin
                frame_done <= 1'b1;
                state_reg         <= ST_IDLE;
            end

            default: state_reg <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
