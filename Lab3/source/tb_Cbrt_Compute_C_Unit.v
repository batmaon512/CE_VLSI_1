`timescale 1ns/1ps

module tb_Cbrt_Compute_C_Unit;

parameter CLK_PERIOD     = 10;
parameter ITERATION_CBRT = 5;

reg         clk;
reg         rst_n;
reg         start;
reg  [31:0] r_cbrt_re_input;
reg  [31:0] r_cbrt_im_input;
reg  [31:0] r_cbrt_re_init;
reg  [31:0] r_cbrt_im_init;

wire        busy;
wire        done;
wire [31:0] r_cbrt_re_output;
wire [31:0] r_cbrt_im_output;
wire [4:0]  iteration_count;
wire [6:0]  delay_count;

integer exp_unbias;
real    mantissa_val;
real    scale_val;
real    fp_value_re;
real    fp_value_im;

Cbrt_Compute_C_Unit #(
    .Iteration_Cbrt(ITERATION_CBRT)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .r_cbrt_re_input(r_cbrt_re_input),
    .r_cbrt_im_input(r_cbrt_im_input),
    .r_cbrt_re_init(r_cbrt_re_init),
    .r_cbrt_im_init(r_cbrt_im_init),
    .busy(busy),
    .done(done),
    .r_cbrt_re_output(r_cbrt_re_output),
    .r_cbrt_im_output(r_cbrt_im_output),
    .iteration_count(iteration_count),
    .delay_count(delay_count)
);

always begin
    #(CLK_PERIOD/2) clk = ~clk;
end

function real fp32_to_real;
    input [31:0] fp;
    integer i;
    integer exponent;
    real mantissa;
    real scale;
    begin
        if ((fp[30:23] == 8'd0) && (fp[22:0] == 23'd0)) begin
            fp32_to_real = 0.0;
        end else begin
            if (fp[30:23] == 8'd0) begin
                exponent = -126;
                mantissa = 0.0;
            end else begin
                exponent = fp[30:23] - 127;
                mantissa = 1.0;
            end

            for (i = 22; i >= 0; i = i - 1) begin
                if (fp[i]) begin
                    mantissa = mantissa + (2.0 ** (i - 23));
                end
            end

            scale = 2.0 ** exponent;
            fp32_to_real = mantissa * scale;

            if (fp[31]) begin
                fp32_to_real = -fp32_to_real;
            end
        end
    end
endfunction

task log_complex;
    input [8*32-1:0] tag;
    input [31:0]     re_val;
    input [31:0]     im_val;
    real re_real;
    real im_real;
    begin
        re_real = fp32_to_real(re_val);
        im_real = fp32_to_real(im_val);
        $display("[%0t] iter=%0d delay=%0d %0s", $time, iteration_count, delay_count, tag);
        $display("         re = 0x%08h (%0f)", re_val, re_real);
        $display("         im = 0x%08h (%0f)", im_val, im_real);
    end
endtask

task log_real;
    input [8*32-1:0] tag;
    input [31:0]     val;
    real val_real;
    begin
        val_real = fp32_to_real(val);
        $display("[%0t] iter=%0d delay=%0d %0s = 0x%08h (%0f)",
                 $time, iteration_count, delay_count, tag, val, val_real);
    end
endtask

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    start = 1'b0;

    // Example:
    // S = 2.0 + j1.0
    // P0 = 1.0 + j0.0
    r_cbrt_re_input = 32'h40000000;
    r_cbrt_im_input = 32'h3f800000;
    r_cbrt_re_init  = 32'h3f800000;
    r_cbrt_im_init  = 32'h00000000;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    @(posedge clk);
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    wait(done);
    @(posedge clk);

    $display("============================================================");
    $display("FINAL RESULT AFTER %0d ITERATIONS", ITERATION_CBRT);
    $display("r_cbrt_re_output = 0x%08h (%0f)", r_cbrt_re_output, fp32_to_real(r_cbrt_re_output));
    $display("r_cbrt_im_output = 0x%08h (%0f)", r_cbrt_im_output, fp32_to_real(r_cbrt_im_output));
    $display("============================================================");
    $finish;
end

always @(posedge clk) begin
    #1;
    if (busy) begin
        case (delay_count)
            7'd14: begin
                log_complex("After P^2", dut.r_temp[1], dut.r_temp[4]);
            end
            7'd18: begin
                log_complex("After P.S", dut.r_temp[2], dut.r_temp[3]);
            end
            7'd28: begin
                log_complex("After P^4", dut.r_temp[8], dut.r_temp[5]);
            end
            7'd33: begin
                log_complex("After 2P^3", dut.fp_mul2(dut.r_temp[9]), dut.fp_mul2(dut.r_temp[10]));
            end
            7'd35: begin
                log_complex("After numerator", dut.r_temp[11], dut.r_temp[12]);
            end
            7'd39: begin
                log_complex("After denominator", dut.r_temp[13], dut.r_temp[14]);
            end
            7'd53: begin
                log_real("Divide numerator real", dut.r_temp[15]);
            end
            7'd55: begin
                log_real("Divide numerator imag", dut.r_temp[16]);
            end
            7'd57: begin
                log_real("Denominator magnitude", dut.r_temp[17]);
            end
            7'd73: begin
                log_real("Divide result real", dut.DivOutput);
            end
            7'd74: begin
                log_real("Divide result imag", dut.DivOutput);
            end
            default: begin
            end
        endcase
    end
end

always @(posedge done) begin
    #1;
    log_complex("After final divide", r_cbrt_re_output, r_cbrt_im_output);
end

endmodule
