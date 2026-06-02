`timescale 1ns/1ps

module tb_Div_FP;

    localparam W = 32;
    localparam LATENCY = 15;

    reg         clk;
    reg  [31:0] FP_in1;
    reg  [31:0] FP_in2;
    wire [31:0] FP_out;

    integer pass_count;
    integer fail_count;

    Div_FP #(.W(W)) dut (
        .clk    (clk),
        .FP_in1 (FP_in1),
        .FP_in2 (FP_in2),
        .FP_out (FP_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic run_test_pipeline;
        input integer start_delay_cycles;
        input [31:0]  a;
        input [31:0]  b;
        input [31:0]  expected;
        input [255:0] name;
        begin
            repeat (start_delay_cycles) @(negedge clk);

            @(negedge clk);
            FP_in1 = a;
            FP_in2 = b;

            $display("[LOAD] %s | time=%0t | A=%h B=%h",
                     name, $time, a, b);

            @(posedge clk);

            repeat (LATENCY) @(posedge clk);
            #1;

            if (FP_out === expected) begin
                $display("[PASS] %s | time=%0t | OUT=%h",
                         name, $time, FP_out);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s | time=%0t | OUT=%h EXPECT=%h",
                         name, $time, FP_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        FP_in1 = 32'h00000000;
        FP_in2 = 32'h3F800000;

        repeat (3) @(posedge clk);

        fork
            run_test_pipeline(0,  32'h3F800000, 32'h00000000, 32'h7F800000, "T1: 1.0 / 0.0 = +Inf");
            run_test_pipeline(1,  32'hBF800000, 32'h00000000, 32'hFF800000, "T2: -1.0 / 0.0 = -Inf");
            run_test_pipeline(2,  32'h00000000, 32'h40000000, 32'h00000000, "T3: 0.0 / 2.0 = +0.0");
            run_test_pipeline(3,  32'h00000000, 32'hC0000000, 32'h80000000, "T4: 0.0 / -2.0 = -0.0");
            run_test_pipeline(4,  32'h00000000, 32'h00000000, 32'h7FC00000, "T5: 0.0 / 0.0 = NaN");
            run_test_pipeline(5,  32'h3F800000, 32'h7F800000, 32'h00000000, "T6: 1.0 / +Inf = +0.0 IEEE");
            run_test_pipeline(6,  32'h40C00000, 32'h40000000, 32'h40400000, "T7: 6.0 / 2.0 = 3.0");
            run_test_pipeline(7,  32'h41100000, 32'h40200000, 32'h40666666, "T8: 9.0 / 2.5 = 3.6");
            run_test_pipeline(8,  32'h3F800000, 32'h40400000, 32'h3EAAAAAB, "T9: 1.0 / 3.0");
            run_test_pipeline(9,  32'h3F800000, 32'h41200000, 32'h3DCCCCCD, "T10: 1.0 / 10.0");
            run_test_pipeline(10, 32'h7F7FFFFF, 32'h00800000, 32'h7F800000, "T11: max_float / min_normal = +Inf");
            run_test_pipeline(11, 32'hFF7FFFFF, 32'h00800000, 32'hFF800000, "T12: -max_float / min_normal = -Inf");
            run_test_pipeline(12, 32'h40490FDB, 32'h402DF854, 32'h3F93EEE0, "T13: pi / e");
            run_test_pipeline(13, 32'h3FB504F3, 32'h3FDDB3D7, 32'h3F5105EC, "T14: sqrt2 / sqrt3");
            run_test_pipeline(14, 32'h40490FDB, 32'h3FB504F3, 32'h400E2C19, "T15: pi / sqrt2");
        join

        $display("================================================");
        $display("PIPELINE TEST DONE");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $display("================================================");

        $finish;
    end

endmodule