`timescale 1ns/1ps
//   make sim-rtl-verilog CELL=fsm TB=fsm_uint8
module fsm_uint8_tb;
  localparam H = 8, U = 4;
  localparam BEATS = 14*H + U*(2*H + 1);          // 180 lines, all consumed
  localparam IN_FILE = "../../../../golden/uint8_tb.txt";
  localparam Y_FILE  = "../../../../golden/uint8_tb_test_vec";
  localparam G_FILE  = "../../../../golden/uint8_tb_golden.txt";
  localparam OPS0 = 2*(U+2), GRP = OPS0+2, S0END = H*GRP, NG = H*OPS0 + U*(2*H+1);

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [15:0] vec [0:BEATS-1];                   // one line: {op1, op2}
  int expy [0:U-1];

  int n = 0, yn = 0, errors = 0, gn = 0;
  int ga [0:NG-1], gb [0:NG-1], gc [0:NG-1], gr [0:NG-1];

  wire        s_ready, m_valid, m_last, frame_done;
  wire [7:0]  m_data;
  logic [7:0] opa, opb, opc, res = 0;
  wire [15:0] s_data = {vec[n][7:0], vec[n][15:8]};   // lane 1 = op2, lane 0 = op1
  wire [7:0]  hwres = opa*opb + opc;
  wire        pad   = (n < S0END) && (n % GRP >= OPS0);

  ssm_fsm #(.H(H), .U(U), .POSIT_ONE(8'd1)) dut (
    .clk(clk), .rst_n(rst_n),
    .s_valid(1'b1), .s_data(s_data), .s_ready(s_ready),
    .fma_opa(opa), .fma_opb(opb), .fma_opc(opc), .fma_res(res),
    .m_valid(m_valid), .m_data(m_data), .m_last(m_last), .m_ready(1'b1),
    .frame_done(frame_done));

  always @(posedge clk) if (rst_n && s_ready) begin
    res <= hwres;
    if (pad) begin
      $display("beat %0d: pad %0d*%0d+%0d=%0d", n, opa, opb, opc, hwres);
    end else begin
      if (hwres !== gr[gn][7:0]) begin
        errors++;
        $display("beat %0d op %0d: hw %0d*%0d+%0d=%0d  gold %0d*%0d+%0d=%0d  DIFF",
                 n, gn, opa, opb, opc, hwres, ga[gn], gb[gn], gc[gn], gr[gn]);
      end else
        $display("beat %0d op %0d: %0d*%0d+%0d=%0d  ok",
                 n, gn, opa, opb, opc, hwres);
      gn <= gn + 1;
    end
    n <= n + 1;
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
    $dumpfile("fsm_uint8_tb.fst");
    $dumpvars;

    fd = $fopen(Y_FILE, "r");
    for (int k = 0; k < U; k++) r = $fscanf(fd, "%d,", expy[k]);
    $fclose(fd);
    fd = $fopen(G_FILE, "r");
    for (int k = 0; k < NG; k++) r = $fscanf(fd, "%d %d %d %d", ga[k], gb[k], gc[k], gr[k]);
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
