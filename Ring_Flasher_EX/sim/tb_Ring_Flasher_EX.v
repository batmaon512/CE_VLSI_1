`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 04/01/2026 05:48:51 PM
// Design Name:
// Module Name: tb_Ring_Flasher_EX
// Description: Professional task-based testbench for Ring_Flasher_EX
//////////////////////////////////////////////////////////////////////////////////

module tb_Ring_Flasher_EX;

    // Parameters
    localparam CLK_FREQ   = 5000;
    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ;
    localparam NumLed     = 16;
    localparam NumCW      = 12;
    localparam NumACW     = 8;
    localparam TimeStep   = 500;

    // Test signals
    reg clk;
    reg reset;
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
        .n_reset(reset),
        .rep(rep),
        .LedOut(LedOut)
    );

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task automatic wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task automatic apply_reset;
        begin
            reset = 1'b1;
            rep   = 1'b0;
            wait_cycles(10);   // hold reset for 10 cycles
            reset = 1'b0;
            wait_cycles(5);    // settle after reset release
        end
    endtask

    task automatic set_rep_and_run;
        input rep_value;
        input integer cycles;
        begin
            rep = rep_value;
            wait_cycles(cycles);
        end
    endtask

    task automatic pulse_reset_mid_run;
        begin
            wait_cycles(20);
            reset = 1'b1;
            wait_cycles(3);
            reset = 1'b0;
            wait_cycles(10);
        end
    endtask

    task automatic run_normal_case;
        begin
            reset = 1'b1;
            rep   = 1'b0;
            wait_cycles(10);
            reset = 1'b0;
            wait_cycles(100);
            $display("%0t ns : Starting Ring Flasher (rep = 1)", $time);
            rep = 1'b1;
            wait_cycles(40 * CLK_FREQ);
            $display("%0t ns : Stopping Ring Flasher (rep = 0)", $time);
            rep = 1'b0;
            wait_cycles(5  * CLK_FREQ);
            $display("%0t ns : Simulation finished", $time);
        end
    endtask

    task automatic run_short_burst_case;
        begin
            $display("[%0t] TC2: Short burst", $time);
            apply_reset;
            set_rep_and_run(1'b1, 2 * CLK_FREQ);
            set_rep_and_run(1'b0, 2 * CLK_FREQ);
        end
    endtask

    task automatic run_repeat_toggle_case;
        begin
            $display("[%0t] TC3: Repeat toggle", $time);
            apply_reset;
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
        end
    endtask

    task automatic run_reset_reentry_case;
        begin
            $display("[%0t] TC4: Reset re-entry during run", $time);
            apply_reset;
            set_rep_and_run(1'b1, 2 * CLK_FREQ);
            pulse_reset_mid_run;
            set_rep_and_run(1'b1, 3 * CLK_FREQ);
            set_rep_and_run(1'b0, 1 * CLK_FREQ);
        end
    endtask

    task automatic run_long_stability_case;
        begin
            $display("[%0t] TC5: Long stability", $time);
            apply_reset;
            set_rep_and_run(1'b1, 60 * CLK_FREQ);
            set_rep_and_run(1'b0, 5 * CLK_FREQ);
        end
    endtask

    task automatic run_off_all_case;
        begin
            $display("[%0t] TC6: Fade-out / off_all observation window", $time);
            apply_reset;
            set_rep_and_run(1'b1, 10 * CLK_FREQ);
            set_rep_and_run(1'b0, 10 * CLK_FREQ);
        end
    endtask

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

    // Monitor
    initial begin
        // $monitor("[%0t] reset=%b rep=%b LedOut=%b", $time, reset, rep, LedOut);
    end
    initial begin
        $recordfile ("waves");
        $recordvars ("depth=0", testbench);
    end
    // Main sequence
    initial begin
        run_normal_case;
        $display("[%0t] All testcases finished", $time);
        $finish;
    end

endmodule

