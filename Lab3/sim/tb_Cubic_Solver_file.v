`timescale 1ns / 1ps

module tb_Cubic_Solver_file;

    localparam CLK_PERIOD = 10; 
    localparam integer MAX_CYCLES_PER_CASE = 3000;
    localparam integer MAX_CASES = 100000;
    localparam [1023:0] INPUT_FILE  = "C:/Users/chith/Downloads/Study/Project/testcode/testcode.srcs/sim_1/new/random_tests.txt";
    localparam [1023:0] OUTPUT_FILE = "C:/Users/chith/Downloads/Study/HK252/VLSI/Lab/CE_VLSI_1/Lab3/sim/cubic_solver_output.txt";
    localparam [1023:0] DEBUG_FILE  = "C:/Users/chith/Downloads/Study/HK252/VLSI/Lab/CE_VLSI_1/Lab3/sim/cubic_solver_debug.txt";
    localparam [1023:0] WAVE_FILE   = "C:/Users/chith/Downloads/Study/HK252/VLSI/Lab/CE_VLSI_1/Lab3/sim/tb_Cubic_Solver_file.vcd";

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

    integer input_fd;
    integer output_fd;
    integer debug_fd;
    integer scan_status;
    integer case_index;

    Cubic_Solver #(
        .Iteration_Sqrt(16),
        .Iteration_Cbrt(16)
    ) dut (
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

    task automatic apply_reset;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    initial begin : main
        input_fd = $fopen(INPUT_FILE, "r");
        if (input_fd == 0) begin
            $fatal(1, "Cannot open input file: %0s", INPUT_FILE);
        end

        output_fd = $fopen(OUTPUT_FILE, "w");
        if (output_fd == 0) begin
            $fatal(1, "Cannot open output file: %0s", OUTPUT_FILE);
        end

        debug_fd = $fopen(DEBUG_FILE, "w");
        if (debug_fd == 0) begin
            $fatal(1, "Cannot open debug file: %0s", DEBUG_FILE);
        end

        $dumpfile(WAVE_FILE);
        $dumpvars(0, tb_Cubic_Solver_file);

        rst_n = 1'b0;
        start = 1'b0;
        FP_a = 32'd0;
        FP_b = 32'd0;
        FP_c = 32'd0;
        FP_d = 32'd0;
        case_index = 0;

        apply_reset();

        while (!$feof(input_fd) && case_index < MAX_CASES) begin
            scan_status = $fscanf(input_fd, "%h %h %h %h", FP_a, FP_b, FP_c, FP_d);
            if (scan_status != 4) begin
                if (!$feof(input_fd)) begin
                    $fatal(1, "Malformed input line at case %0d", case_index + 1);
                end
                disable main;
            end

            case_index = case_index + 1;
            $display("Running case %0d: a=%h b=%h c=%h d=%h", case_index, FP_a, FP_b, FP_c, FP_d);

            apply_reset();

            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            begin : wait_for_done
                integer timeout_count;

                for (timeout_count = 0; timeout_count < MAX_CYCLES_PER_CASE; timeout_count = timeout_count + 1) begin
                    @(posedge clk);
                    if (done === 1'b1) begin
                        #1;
                        $fwrite(
                            debug_fd,
                            "%08h %08h %08h %08h %08h\n",
                            dut.r_delta,
                            dut.r_delta_0,
                            dut.r_delta_1,
                            dut.r_C_re,
                            dut.r_C_im
                        );
                        $fwrite(
                            output_fd,
                            "%08h %08h %08h %08h %08h %08h\n",
                            FP_x0_re,
                            FP_x0_im,
                            FP_x1_re,
                            FP_x1_im,
                            FP_x2_re,
                            FP_x2_im
                        );
                        disable wait_for_done;
                    end
                end

                $fatal(1, "Timeout while waiting for done at case %0d", case_index);
            end
        end

        $display("Completed %0d test cases.", case_index);
        $fclose(input_fd);
        $fclose(output_fd);
        $fclose(debug_fd);
        $finish;
    end

endmodule
