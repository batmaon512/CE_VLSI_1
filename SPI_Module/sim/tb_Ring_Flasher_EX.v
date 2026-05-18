`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 04/01/2026 05:48:51 PM
// Design Name:
// Module Name: tb_Ring_Flasher_EX
// Description: Task-based testbench for Ring_Flasher_EX
//////////////////////////////////////////////////////////////////////////////////

module tb_Ring_Flasher_EX;

    // Parameters
    localparam CLK_FREQ   = 5000;
    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ; // ns, for 5 kHz clock
    localparam NumLed     = 16;
    localparam NumCW      = 12;
    localparam NumACW     = 8;
    localparam TimeStep   = 500;

    // Test signals
    reg clk;
    reg n_reset;     // active-low reset
    reg rep;
    wire [NumLed-1:0] LedOut;

    // DUT
    Ring_Flasher_EX #(
        .ClockSpeed(CLK_FREQ),
        .NumLed(NumLed),
        .NumCW(NumCW),
        .NumACW(NumACW),
        .TimeStep(TimeStep)
    ) dut (
        .clk(clk),
        .n_reset(n_reset),
        .rep(rep),
        .LedOut(LedOut)
    );

    //========================================================
    // Clock generation: 5 kHz
    //========================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //========================================================
    // Utility task: wait N clock cycles
    //========================================================
    task automatic wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    //========================================================
    // Reset task: active-low
    // n_reset = 0 -> reset asserted
    // n_reset = 1 -> normal operation
    //========================================================
    task automatic apply_reset;
        begin
            $display("[%0t ns] Applying active-low reset", $time);
            n_reset = 1'b0;
            rep     = 1'b0;
            wait_cycles(10);   // keep reset active for 10 cycles
            n_reset = 1'b1;
            wait_cycles(5);    // wait 5 cycles after release
        end
    endtask

    //========================================================
    // Set rep and keep running for some cycles
    //========================================================
    task automatic set_rep_and_run;
        input reg rep_value;
        input integer cycles;
        begin
            rep = rep_value;
            wait_cycles(cycles);
        end
    endtask

    //========================================================
    // Pulse reset in the middle of operation
    //========================================================
    task automatic pulse_reset_mid_run;
        begin
            $display("[%0t ns] Pulsing active-low reset during run", $time);
            wait_cycles(20);
            n_reset = 1'b0;
            wait_cycles(3);
            n_reset = 1'b1;
            wait_cycles(10);
        end
    endtask

    //========================================================
    // Test case 1: Normal case
    //========================================================
    task automatic run_normal_case;
        begin
            $display("\n[%0t ns] TC1: Normal case", $time);
            apply_reset;

            $display("[%0t ns] Starting Ring Flasher (rep = 1)", $time);
            rep = 1'b1;
            wait_cycles(40 * CLK_FREQ);

            $display("[%0t ns] Stopping Ring Flasher (rep = 0)", $time);
            rep = 1'b0;
            wait_cycles(5 * CLK_FREQ);

            $display("[%0t ns] TC1 finished", $time);
        end
    endtask

    //========================================================
    // Test case 2: Short burst
    //========================================================
    task automatic run_short_burst_case;
        begin
            $display("\n[%0t ns] TC2: Short burst", $time);
            apply_reset;
            set_rep_and_run(1'b1, 2 * CLK_FREQ);
            set_rep_and_run(1'b0, 2 * CLK_FREQ);
            $display("[%0t ns] TC2 finished", $time);
        end
    endtask

    //========================================================
    // Test case 3: Repeat toggle
    //========================================================
    task automatic run_repeat_toggle_case;
        begin
            $display("\n[%0t ns] TC3: Repeat toggle", $time);
            apply_reset;
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
            $display("[%0t ns] TC3 finished", $time);
        end
    endtask

    //========================================================
    // Test case 4: Reset re-entry during run
    //========================================================
    task automatic run_reset_reentry_case;
        begin
            $display("\n[%0t ns] TC4: Reset re-entry during run", $time);
            apply_reset;
            set_rep_and_run(1'b1, 2 * CLK_FREQ);
            pulse_reset_mid_run;
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
            $display("[%0t ns] TC4 finished", $time);
        end
    endtask

    //========================================================
    // Test case 5: Long stability
    //========================================================
    task automatic run_long_stability_case;
        begin
            $display("\n[%0t ns] TC5: Long stability", $time);
            apply_reset;
            set_rep_and_run(1'b1, 60 * CLK_FREQ);
            set_rep_and_run(1'b0, 5 * CLK_FREQ);
            $display("[%0t ns] TC5 finished", $time);
        end
    endtask

    //========================================================
    // Test case 6: Off/fade-out observation
    //========================================================
    task automatic run_off_all_case;
        begin
            $display("\n[%0t ns] TC6: Fade-out / off_all observation window", $time);
            apply_reset;
            set_rep_and_run(1'b1, 10 * CLK_FREQ);
            set_rep_and_run(1'b0, 10 * CLK_FREQ);
            $display("[%0t ns] TC6 finished", $time);
        end
    endtask

    //========================================================
    // Run all testcases
    //========================================================
    task automatic run_all_tests;
        begin
            run_normal_case;
            run_short_burst_case;
            run_repeat_toggle_case;
            run_reset_reentry_case;
            run_long_stability_case;
            run_off_all_case;
        end
    endtask

    //========================================================
    // Optional monitor
    //========================================================
    initial begin
        $monitor("[%0t ns] n_reset=%b rep=%b LedOut=%b", $time, n_reset, rep, LedOut);
    end

    //========================================================
    // Main sequence
    //========================================================
    initial begin
        // Initial values
        n_reset = 1'b1;   // not in reset
        rep     = 1'b0;

        // Small delay before starting tests
        wait_cycles(2);

        run_all_tests;

        $display("\n[%0t ns] All testcases finished", $time);
        $finish;
    end
    
    initial begin
        $recordfile ("waves");
        $recordvars ("depth=0", tb_Ring_Flasher_EX);
    end

endmodule