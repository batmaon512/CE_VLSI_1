`timescale 1ns / 1ps

module tb_Cubic_Solver;

    localparam CLK_PERIOD = 10;
    localparam integer MAX_CYCLES = 2000;

    localparam [3:0] IDLE             = 4'b0000;
    localparam [3:0] STANDARDIZE      = 4'b0001;
    localparam [3:0] DELTA_COMPUTE    = 4'b0010;
    localparam [3:0] CASE_CHECK       = 4'b0011;
    localparam [3:0] Sqrt_COMPUTE     = 4'b0100;
    localparam [3:0] BRANCH_CHECK     = 4'b0101;
    localparam [3:0] Cbrt_COMPUTE_R   = 4'b0110;
    localparam [3:0] Cbrt_COMPUTE_C   = 4'b0111;
    localparam [3:0] CASE1_COMPUTE    = 4'b1000;
    localparam [3:0] CASE2A_COMPUTE   = 4'b1001;
    localparam [3:0] CASE2B_COMPUTE   = 4'b1010;
    localparam [3:0] DONE             = 4'b1011;

    reg clk;
    reg rst_n;
    reg start;
    reg [31:0] FP_a;
    reg [31:0] FP_b;
    reg [31:0] FP_c;
    reg [31:0] FP_d;

    wire done;
    wire [31:0] FP_x0_re;
    wire [31:0] FP_x0_im;
    wire [31:0] FP_x1_re;
    wire [31:0] FP_x1_im;
    wire [31:0] FP_x2_re;
    wire [31:0] FP_x2_im;
    wire [127:0] FP_input = 128'hbd6f8d3ac0b32f10410200c5411edf3e;
    Cubic_Solver dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .FP_a(FP_a),
        .FP_b(FP_b),
        .FP_c(FP_c),
        .FP_d(FP_d),
        .FP_x0_re(FP_x0_re),
        .FP_x0_im(FP_x0_im),
        .FP_x1_re(FP_x1_re),
        .FP_x1_im(FP_x1_im),
        .FP_x2_re(FP_x2_re),
        .FP_x2_im(FP_x2_im)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic wait_cycles;
        input integer count;
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    initial begin
        start = 1'b0;
        FP_a = FP_input[127:96];
        FP_b = FP_input[95:64];
        FP_c = FP_input[63:32];
        FP_d = FP_input[31:0];

        rst_n = 1'b0;
        wait_cycles(3);
        rst_n = 1'b1;

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        begin : finish_test
            repeat (MAX_CYCLES) begin
                @(posedge clk);
                if (dut.state == BRANCH_CHECK) begin
                    if (dut.iteration_count >= 2) begin
                        wait_cycles(2);
                        disable finish_test;
                    end else begin
                    end
                end
            end
            $finish;
        end
    end

endmodule