`default_nettype none

module shift_register #(
  parameter int unsigned WIDTH = 8,    // bits per element
  parameter int unsigned DEPTH = 16    // number of elements
)(
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             shift_i,    // shift by one when set
  input  logic             load_i,     // tail takes inject_i instead of the head
  input  logic [WIDTH-1:0] inject_i,
  output logic [WIDTH-1:0] out0_o,     // head
  output logic [WIDTH-1:0] out1_o      // head + 1
);

    // Shift register implementation
    // For Phase 2 we only need to iterate through states of x and dont update anything --> shift_i
    logic [WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            for (int i = 0; i < DEPTH; i++) mem[i] <= '0;
        end else if(shift_i) begin
            for (int i = 0; i < DEPTH-1; i++) mem[i] <= mem[i+1];
            mem[DEPTH-1] <= load_i ? inject_i : mem[0]; // if shift AND load_i then inject_i, if only shift, just shift in the head (circular)
        end
    end

    assign out0_o = mem[0];
    assign out1_o = mem[1];

    // Two outputs because we need to be able to read the head and the next element in the shift register for the calc phase 1 (real and complex part of xi)

    endmodule

`default_nettype wire
