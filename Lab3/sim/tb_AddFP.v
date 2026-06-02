`timescale 1ns / 1ps

module tb_Add_FP;

    // =========================================================
    // 1. SIGNAL DECLARATION
    // =========================================================
    reg clk;
    reg [31:0] in1;
    reg [31:0] in2;
    wire [31:0] data_out;

    // Parameters
    localparam PERIOD = 10;       // 100MHz
    localparam LATENCY = 5;       // Độ trễ Pipeline
    localparam TEST_COUNT = 30;   // Tăng lên 15 testcase

    // Arrays
    reg [31:0] test_a [0:TEST_COUNT-1];
    reg [31:0] test_b [0:TEST_COUNT-1];
    reg [31:0] expected_res [0:TEST_COUNT-1];

    // =========================================================
    // 2. DUT INSTANTIATION
    // =========================================================
    Add_FP u_dut (
        .clk(clk),
        .in1(in1),
        .in2(in2),
        .data_out(data_out)
    );

    // =========================================================
    // 3. CLOCK GENERATION
    // =========================================================
    initial begin
        clk = 0;
        forever #(PERIOD/2) clk = ~clk;
    end

    // =========================================================
    // 4. SETUP TEST VECTORS
    // =========================================================
    initial begin

test_a[0] = 32'hc1a00000; test_b[0] = 32'h41a00000; expected_res[0] = 32'h00000000; // -20.0 + 20.0 = 0.0
test_a[1] = 32'h41c80000; test_b[1] = 32'h80000000; expected_res[1] = 32'h41c80000; // 25.0 - 0 = 25.0
test_a[2] = 32'hc28de666; test_b[2] = 32'h42a7fae1; expected_res[2] = 32'h4150a3d7; // -70.95 + 83.99 = 13.039999999999992
test_a[3] = 32'h42b7eb85; test_b[3] = 32'hc11f5c29; expected_res[3] = 32'h42a40000; // 91.96 + -9.96 = 82.0
test_a[4] = 32'h41dfeb85; test_b[4] = 32'hc2078f5c; expected_res[4] = 32'hc0bccccd; // 27.99 + -33.89 = -5.900000000000002
test_a[5] = 32'hc257a3d7; test_b[5] = 32'h4284b852; expected_res[5] = 32'h41473333; // -53.91 + 66.36 = 12.450000000000003
test_a[6] = 32'h422647ae; test_b[6] = 32'hc2c12e14; expected_res[6] = 32'hc25c147b; // 41.57 + -96.59 = -55.02
test_a[7] = 32'hc28323d7; test_b[7] = 32'h421a28f6; expected_res[7] = 32'hc1d83d71; // -65.57 + 38.54 = -27.029999999999994
test_a[8] = 32'hc272d70a; test_b[8] = 32'hc0033333; expected_res[8] = 32'hc27b0a3d; // -60.71 + -2.05 = -62.76
test_a[9] = 32'hc2b28f5c; test_b[9] = 32'h422af5c3; expected_res[9] = 32'hc23a28f6; // -89.28 + 42.74 = -46.54
test_a[10] = 32'h4290e666; test_b[10] = 32'hc264e148; expected_res[10] = 32'h4173ae14; // 72.45 + -57.22 = 15.230000000000004
test_a[11] = 32'h411e147b; test_b[11] = 32'hc2bb3852; expected_res[11] = 32'hc2a775c3; // 9.88 + -93.61 = -83.73
test_a[12] = 32'h42701eb8; test_b[12] = 32'hc14bae14; expected_res[12] = 32'h423d3333; // 60.03 + -12.73 = 47.3
test_a[13] = 32'hc21e147b; test_b[13] = 32'hc2a9e148; expected_res[13] = 32'hc2f8eb85; // -39.52 + -84.94 = -124.46000000000001
test_a[14] = 32'hc23ef5c3; test_b[14] = 32'hc166147b; expected_res[14] = 32'hc2787ae1; // -47.74 + -14.38 = -62.120000000000005
test_a[15] = 32'h419b1eb8; test_b[15] = 32'h412bd70a; expected_res[15] = 32'h41f10a3d; // 19.39 + 10.74 = 30.130000000000003
test_a[16] = 32'hc199c28f; test_b[16] = 32'hc280c7ae; expected_res[16] = 32'hc2a73852; // -19.22 + -64.39 = -83.61
test_a[17] = 32'hc135eb85; test_b[17] = 32'h3f9851ec; expected_res[17] = 32'hc122e148; // -11.37 + 1.19 = -10.18
test_a[18] = 32'hc150a3d7; test_b[18] = 32'hc22aae14; expected_res[18] = 32'hc25ed70a; // -13.04 + -42.67 = -55.71
test_a[19] = 32'hc201f5c3; test_b[19] = 32'hc28d9eb8; expected_res[19] = 32'hc2ce999a; // -32.49 + -70.81 = -103.30000000000001
test_a[20] = 32'h41cc6666; test_b[20] = 32'hc2938000; expected_res[20] = 32'hc240cccd; // 25.55 + -73.75 = -48.2
test_a[21] = 32'hc13fd70a; test_b[21] = 32'h425bc28f; expected_res[21] = 32'h422bcccd; // -11.99 + 54.94 = 42.949999999999996
test_a[22] = 32'h4106b852; test_b[22] = 32'hc25d0000; expected_res[22] = 32'hc23b51ec; // 8.42 + -55.25 = -46.83
test_a[23] = 32'hc1287ae1; test_b[23] = 32'hc2170000; expected_res[23] = 32'hc2411eb8; // -10.53 + -37.75 = -48.28
test_a[24] = 32'h40ffae14; test_b[24] = 32'hc2a02e14; expected_res[24] = 32'hc2903333; // 7.99 + -80.09 = -72.10000000000001
test_a[25] = 32'h42ac999a; test_b[25] = 32'hc200c28f; expected_res[25] = 32'h425870a4; // 86.3 + -32.19 = 54.11
test_a[26] = 32'hc29e8a3d; test_b[26] = 32'hc2c73d71; expected_res[26] = 32'hc332e3d7; // -79.27 + -99.62 = -178.89
test_a[27] = 32'h41cab852; test_b[27] = 32'h417c51ec; expected_res[27] = 32'h422470a4; // 25.34 + 15.77 = 41.11
test_a[28] = 32'h4258999a; test_b[28] = 32'hc0f6147b; expected_res[28] = 32'h4239d70a; // 54.15 + -7.69 = 46.46
test_a[29] = 32'hc279c28f; test_b[29] = 32'h3e99999a; expected_res[29] = 32'hc2788f5c; // -62.44 + 0.3 = -62.14
    end

    // =========================================================
    // 5. DRIVER PROCESS
    // =========================================================
    integer i;
    initial begin
        in1 = 0; in2 = 0;
        @(posedge clk);
        #(PERIOD*2); 

        $display("-------------------------------------------------------------");
        $display("STARTING PIPELINE TEST - %0d CASES", TEST_COUNT);
        $display("-------------------------------------------------------------");

        for (i = 0; i < TEST_COUNT; i = i + 1) begin
            @(posedge clk); 
            in1 <= test_a[i];
            in2 <= test_b[i];
            $display("[%0t ns] INPUT  Case %2d: %h + %h", $time, i, test_a[i], test_b[i]);
        end
        
        @(posedge clk);
        in1 <= 0; in2 <= 0;
    end

    // =========================================================
    // 6. MONITOR PROCESS
    // =========================================================
    integer k;
    integer pass_count;
    initial begin
        pass_count = 0;
        // Wait Latency
        #(PERIOD * 2); 
        #(PERIOD * LATENCY); 
        
        for (k = 0; k < TEST_COUNT; k = k + 1) begin
            @(posedge clk); 
            #1; // Delay để lấy giá trị ổn định
            
            if ((data_out >= expected_res[k] && data_out - expected_res[k] < 8) || (data_out < expected_res[k] && expected_res[k] - data_out < 8)) begin
            
                $display("[%0t ns] OUTPUT Case %2d: %h (PASS)", $time, k, data_out);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t ns] OUTPUT Case %2d: %h (FAIL) - Exp: %h", $time, k, data_out, expected_res[k]);
            end
        end
        
        $display("-------------------------------------------------------------");
        $display("RESULT: %0d/%0d PASSED", pass_count, TEST_COUNT);
        $display("-------------------------------------------------------------");
        $finish;
    end
    
endmodule