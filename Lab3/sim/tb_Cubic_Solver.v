`timescale 1ns / 1ps

module tb_Cubic_Solver;

    localparam CLK_PERIOD = 10;

    localparam [3:0] IDLE             = 4'b0000;
    localparam [3:0] STANDARDIZE      = 4'b0001;
    localparam [3:0] DELTA_COMPUTE    = 4'b0010;
    localparam [3:0] Sqrt_COMPUTE     = 4'b0011;
    localparam [3:0] BRANCH_CHECK     = 4'b0100;
    localparam [3:0] Cbrt_COMPUTE_R   = 4'b0101;
    localparam [3:0] Cbrt_COMPUTE_C   = 4'b0110;
    localparam [3:0] CASE1_COMPUTE    = 4'b0111;
    localparam [3:0] CASE2A_COMPUTE   = 4'b1000;
    localparam [3:0] CASE2B_COMPUTE   = 4'b1001;
    localparam [3:0] DONE             = 4'b1010;

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

    function [8*16-1:0] state_name;
        input [3:0] s;
        begin
            case (s)
                IDLE:           state_name = "IDLE";
                STANDARDIZE:    state_name = "STANDARDIZE";
                DELTA_COMPUTE:  state_name = "DELTA_COMPUTE";
                Sqrt_COMPUTE:   state_name = "SQRT_COMPUTE";
                BRANCH_CHECK:   state_name = "BRANCH_CHECK";
                Cbrt_COMPUTE_R: state_name = "CBRT_R";
                Cbrt_COMPUTE_C: state_name = "CBRT_C";
                CASE1_COMPUTE:  state_name = "CASE1";
                CASE2A_COMPUTE: state_name = "CASE2A";
                CASE2B_COMPUTE: state_name = "CASE2B";
                DONE:           state_name = "DONE";
                default:        state_name = "UNKNOWN";
            endcase
        end
    endfunction

    task automatic show_cycle;
        begin
            $display(
                "[%0t] state=%s next=%s done=%b delay=%0d iter=%0d case=%0d r_a=%h r_b=%h r_c=%h r_d=%h x0=%h x1=%h x2=%h",
                $time,
                state_name(dut.state),
                state_name(dut.next_state),
                done,
                dut.delay_count,
                dut.iteration_count,
                dut.case_index,
                dut.r_a,
                dut.r_b,
                dut.r_c,
                dut.r_d,
                FP_x0_re,
                FP_x1_re,
                FP_x2_re
            );
        end
    endtask

    initial begin
        $dumpfile("Lab3/sim/tb_Cubic_Solver.vcd");
        $dumpvars(0, tb_Cubic_Solver);

        start = 1'b0;
        FP_a = 32'h3f800000; // 1.0
        FP_b = 32'hc0c00000; // -6.0
        FP_c = 32'h41300000; // 11.0
        FP_d = 32'hc0c00000; // -6.0

        rst_n = 1'b0;
        wait_cycles(3);
        rst_n = 1'b1;

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        begin : finish_test
            repeat (120) begin
                @(posedge clk);
                show_cycle();
                if (done) begin
                    $display("[%0t] Done asserted, stopping simulation.", $time);
                    wait_cycles(2);
                    disable finish_test;
                end
            end

            $display("[%0t] Timeout before reaching the target state.", $time);
            $finish;
        end
    end

endmodule