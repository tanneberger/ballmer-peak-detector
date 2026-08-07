`timescale 1ns/1ps
// posit FMA is replaced by plain 8-bit multiply-add. Streams golden/uint8_tb.txt
// and compares y against golden/uint8_tb_test_vec. The generator still emits
// 2 commit-padding lines per hidden state which the reworked FSM does not
// consume, so lines 12 and 13 of every 14-line stage-0 block are skipped.
module fsm_uint8_tb;
  localparam H = 8, U = 4;
  localparam S0_LINES = 14;                       // 12 ops + 2 padding lines
  localparam LINES = H*S0_LINES + U*(2*H + 1);    // 180 lines in the file
  localparam BEATS = 12*H + U*(2*H + 1);          // 164 beats the FSM consumes
  localparam IN_FILE = "../../../../../../golden/uint8_tb.txt";
  localparam Y_FILE  = "../../../../../../golden/uint8_tb_test_vec";

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [15:0] vec [0:LINES-1];         // one line: {op1, op2}
  int expy [0:U-1];

  int n = 0, yn = 0, errors = 0;

  // map DUT beat number to file line, skipping the stage-0 padding
  function automatic int line_of(input int b);
    return (b < 12*H) ? (b/12)*S0_LINES + (b%12)
                      : H*S0_LINES + (b - 12*H);
  endfunction

  wire        s_ready, m_valid, m_last, frame_done;
  wire [7:0]  m_data;
  logic [7:0] opa, opb, opc, res = 0;
  wire [15:0] w = vec[line_of(n)];
  wire [15:0] s_data = {w[7:0], w[15:8]};         // lane 1 = op2, lane 0 = op1

  ssm_fsm #(.H(H), .U(U), .POSIT_ONE(8'd1)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_valid(1'b1), .s_data(s_data), .s_ready(s_ready),
    .fma_opa(opa), .fma_opb(opb), .fma_opc(opc), .fma_res(res),
    .m_valid(m_valid), .m_data(m_data), .m_last(m_last), .m_ready(1'b1),
    .frame_done(frame_done));

  // the "FMA": 8-bit multiply-add, result registered
  always @(posedge clk) if (rst_n && s_ready) begin
    res <= opa * opb + opc;
    n   <= n + 1;
  end

  always @(posedge clk) if (rst_n && m_valid) begin
    if (m_data !== expy[yn][7:0]) begin
      errors++;
      $display("y[%0d] = %0d, python says %0d", yn, m_data, expy[yn]);
    end else begin
      $display("y[%0d] = %0d, matches python", yn, m_data);
    end
    yn++;
  end

  initial begin
    int fd, r;
    fd = $fopen(Y_FILE, "r");
    for (int k = 0; k < U; k++) r = $fscanf(fd, "%d,", expy[k]);
    $fclose(fd);
    $readmemb(IN_FILE, vec);

    repeat (2) @(posedge clk);
    rst_n = 1;
    fork
      wait (yn == U);
      begin repeat (3*BEATS) @(posedge clk); $display("TIMEOUT"); errors++; end
    join_any
    if (errors == 0) $display("PASS: %0d beats, %0d/%0d y bytes match", n, yn, U);
    else             $display("FAIL: %0d of %0d y bytes differ", errors, U);
    $finish;
  end
endmodule
