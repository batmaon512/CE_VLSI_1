`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/01/2026 05:48:51 PM
// Design Name: 
// Module Name: tb_Ring_Flasher_EX
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Testbench cho module Ring_Flasher_EX
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_Ring_Flasher_EX(
    );

    // Parameters
    localparam CLK_FREQ = 5000;           // 5kHz
    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ;  // 200us in ns
    localparam NumLed = 16;
    localparam NumCW = 12;
    localparam NumACW = 8;
    localparam TimeStep = 500;
    
localparam integer RUN20_CYCLES = 40 * CLK_FREQ;  // 100000 cycles at 5kHz
localparam integer RUN5_CYCLES  = 5  * CLK_FREQ;  // 25000 cycles at 5kHz
    // Test signals
    reg clk;
    reg reset;
    reg rep;
    wire [NumLed-1:0] LedOut;
    
    // Instantiate DUT (Device Under Test)
    Ring_Flasher_EX #(
        .ClockSpeed(CLK_FREQ),
        .NumLed(NumLed),
        .NumCW(NumCW),
        .NumACW(NumACW),
        .TimeStep(TimeStep)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rep(rep),
        .LedOut(LedOut)
    );
    
    // Clock generation: 5kHz
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialization
        reset = 1;
        rep = 0;
        
        // Reset the system
        #(CLK_PERIOD * 10);  // Hold reset for 10 clock cycles
        reset = 0;
        
        // Wait a bit before activating
        #(CLK_PERIOD * 100);
        
        // ===== Phase 1: rep = 1 for 20 seconds =====
        $display($time, " ns : Starting Ring Flasher (rep = 1)");
        rep = 1;
        repeat (RUN20_CYCLES) @(posedge clk);

        // ===== Phase 2: rep = 0 for 5 seconds =====
        $display($time, " ns : Stopping Ring Flasher (rep = 0)");
        rep = 0;
        repeat (RUN5_CYCLES) @(posedge clk);

        $display($time, " ns : Simulation finished");
        $finish;
    end
    
    // Monitor outputs
    initial begin
        $monitor($time, " ns | LedOut = %b | rep = %b | reset = %b", 
                 LedOut, rep, reset);
    end

endmodule

