`timescale 1ns / 1ps

module tb_Mul_FP;

    // =========================================================
    // 1. SIGNAL DECLARATION
    // =========================================================
    reg clk;
    reg [31:0] FP_in1;
    reg [31:0] FP_in2;
    wire [31:0] FP_out;

    // Parameters
    localparam PERIOD = 10;       // 10ns = 100MHz
    localparam LATENCY = 7;       // 6 Stages (Mul) + 1 Stage (Norm) = 7
    localparam TEST_COUNT = 20;   // Số lượng testcase

    // Arrays lưu trữ vector test
    reg [31:0] input_a [0:TEST_COUNT-1];
    reg [31:0] input_b [0:TEST_COUNT-1];
    reg [31:0] expected [0:TEST_COUNT-1];

    // =========================================================
    // 2. DUT INSTANTIATION
    // =========================================================
    Mul_FP u_dut (
        .clk(clk),
        .FP_in1(FP_in1),
        .FP_in2(FP_in2),
        .FP_out(FP_out)
    );

    // =========================================================
    // 3. CLOCK GENERATION
    // =========================================================
    initial begin
        clk = 0;
        forever #(PERIOD/2) clk = ~clk;
    end

    // =========================================================
    // 4. SETUP TEST VECTORS (IEEE 754 Hex)
    // =========================================================
    initial begin
input_a[0] = 32'hc3ca7486; input_b[0] = 32'h447797e5; expected[0] = 32'hc8c3ce8d; // -404.9 * 990.4 = -4.01e+05
input_a[1] = 32'hc3ece0f5; input_b[1] = 32'hc317d506; expected[1] = 32'h478c7dcd; // -473.8 * -151.8 = 7.193e+04
input_a[2] = 32'h00000000; input_b[2] = 32'hc19e0e2b; expected[2] = 32'h80000000; // 0 * -19.76 = -0
input_a[3] = 32'h43fd7e1f; input_b[3] = 32'h43053930; expected[3] = 32'h4783eb27; // 507 * 133.2 = 6.754e+04
input_a[4] = 32'hc46b9034; input_b[4] = 32'hc43699f2; expected[4] = 32'h4928062d; // -942.3 * -730.4 = 6.882e+05
input_a[5] = 32'hc34f5d96; input_b[5] = 32'hc419d276; expected[5] = 32'h47f932d2; // -207.4 * -615.3 = 1.276e+05
input_a[6] = 32'h00000000; input_b[6] = 32'h42597832; expected[6] = 32'h00000000; // 0 * 54.37 = 0
input_a[7] = 32'h7e0dfd91; input_b[7] = 32'h3f10456a; expected[7] = 32'h7da00a43; // 4.718e+37 * 0.5636 = 2.659e+37
input_a[8] = 32'h439d3e0b; input_b[8] = 32'h44259a18; expected[8] = 32'h484b6f46; // 314.5 * 662.4 = 2.083e+05
input_a[9] = 32'hc41537cb; input_b[9] = 32'h445888c9; expected[9] = 32'hc8fc6d9c; // -596.9 * 866.1 = -5.17e+05
input_a[10] = 32'hc20013d7; input_b[10] = 32'h442dde61; expected[10] = 32'hc6adf954; // -32.02 * 695.5 = -2.227e+04
input_a[11] = 32'hc454e47d; input_b[11] = 32'h43c18a79; expected[11] = 32'hc8a0f36a; // -851.6 * 387.1 = -3.296e+05
input_a[12] = 32'h00000000; input_b[12] = 32'hc262fa58; expected[12] = 32'h80000000; // 0 * -56.74 = -0
input_a[13] = 32'h44659f5f; input_b[13] = 32'hc430d130; expected[13] = 32'hc91e9933; // 918.5 * -707.3 = -6.496e+05
input_a[14] = 32'h43a8d880; input_b[14] = 32'h4420c559; expected[14] = 32'h485412f3; // 337.7 * 643.1 = 2.172e+05
input_a[15] = 32'h7e408d7f; input_b[15] = 32'h3f9fe23b; expected[15] = 32'h7e708416; // 6.399e+37 * 1.249 = 7.993e+37
input_a[16] = 32'h440f4450; input_b[16] = 32'h43698d52; expected[16] = 32'h4802b443; // 573.1 * 233.6 = 1.338e+05
input_a[17] = 32'h00000000; input_b[17] = 32'hc2994236; expected[17] = 32'h80000000; // 0 * -76.63 = -0
input_a[18] = 32'hc415f296; input_b[18] = 32'h441a4d3d; expected[18] = 32'hc8b4c258; // -599.8 * 617.2 = -3.702e+05
input_a[19] = 32'hc416e41e; input_b[19] = 32'h43d2ad56; expected[19] = 32'hc8785a97; // -603.6 * 421.4 = -2.543e+05
    end

    // =========================================================
    // 5. DRIVER PROCESS (Feed inputs rapidly)
    // =========================================================
    integer i;
    initial begin
        FP_in1 = 0;
        FP_in2 = 0;
        
        // Reset system slightly
        @(posedge clk);
        #(PERIOD*2); 

        $display("-------------------------------------------------------------");
        $display("STARTING MUL_FP PIPELINE TEST (LATENCY = %0d)", LATENCY);
        $display("-------------------------------------------------------------");

        // BURST MODE: Feed inputs every clock cycle
        for (i = 0; i < TEST_COUNT; i = i + 1) begin
            @(posedge clk); 
            // Non-blocking assignment to mimic real hardware pipeline feed
            FP_in1 <= input_a[i];
            FP_in2 <= input_b[i];
            
            $display("[%0t ns] INPUT  Case %2d: %h * %h", $time, i, input_a[i], input_b[i]);
        end
        
        // Feed zeros after done
        @(posedge clk);
        FP_in1 <= 0;
        FP_in2 <= 0;
    end

    // =========================================================
    // 6. MONITOR PROCESS (Check outputs with Latency)
    // =========================================================
    integer k;
    integer pass_cnt;
    initial begin
        pass_cnt = 0;
        
        // Wait for Pipeline Latency
        // Time = Initial Delay + (Latency * Period)
        #(PERIOD * 2); 
        #(PERIOD * LATENCY); 
        
        $display("-------------------------------------------------------------");
        $display("CHECKING RESULTS");
        $display("-------------------------------------------------------------");

        for (k = 0; k < TEST_COUNT; k = k + 1) begin
            @(posedge clk); 
            #1; // Wait a tiny bit for data to settle
            
            if (FP_out === expected[k]) begin
                $display("[%0t ns] OUTPUT Case %2d: %h (PASS)", $time, k, FP_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                // Check if error is very small (LSB rounding difference)
                if ((FP_out > expected[k] && FP_out - expected[k] <= 1) || 
                    (expected[k] > FP_out && expected[k] - FP_out <= 1)) begin
                     $display("[%0t ns] OUTPUT Case %2d: %h (PASS - LSB Diff)", $time, k, FP_out);
                     pass_cnt = pass_cnt + 1;
                end else begin
                     $display("[%0t ns] OUTPUT Case %2d: %h (FAIL) - Exp: %h", $time, k, FP_out, expected[k]);
                end
            end
        end
        
        $display("-------------------------------------------------------------");
        $display("TEST COMPLETE: %0d/%0d Passed", pass_cnt, TEST_COUNT);
        $display("-------------------------------------------------------------");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("dump_mul.vcd");
        $dumpvars(0, tb_Mul_FP);
    end

endmodule