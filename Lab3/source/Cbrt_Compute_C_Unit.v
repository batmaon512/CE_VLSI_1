module Cbrt_Compute_C_Unit #(
    parameter Iteration_Cbrt = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] r_cbrt_re_input,
    input  wire [31:0] r_cbrt_im_input,
    input  wire [31:0] r_cbrt_re_init,
    input  wire [31:0] r_cbrt_im_init,
    output wire        busy,
    output wire        done,
    output reg  [31:0] r_cbrt_re_output,
    output reg  [31:0] r_cbrt_im_output,
    output reg  [4:0]  iteration_count,
    output reg  [6:0]  delay_count
);

reg [31:0] MulInput1, MulInput2;
wire [31:0] MulOutput;

reg  [31:0] AddInput1, AddInput2;
wire [31:0] AddOutput;

reg  [31:0] DivInput1, DivInput2;
wire [31:0] DivOutput;

reg [31:0] r_temp [0:17];
reg        active;

Mul_FP Mul_FP_0 (
    .clk(clk),
    .FP_in1(MulInput1),
    .FP_in2(MulInput2),
    .FP_out(MulOutput)
);

Add_FP Add_FP_0 (
    .clk(clk),
    .in1(AddInput1),
    .in2(AddInput2),
    .data_out(AddOutput)
);

Div_FP #(32) Div_FP_0 (
    .clk(clk),
    .FP_in1(DivInput1),
    .FP_in2(DivInput2),
    .FP_out(DivOutput)
);

function [31:0] fp_neg;
    input [31:0] value;
    begin
        fp_neg = {~value[31], value[30:0]};
    end
endfunction

function [31:0] fp_mul2;
    input [31:0] value;
    begin
        if (value[30:23] == 8'd0 || value[30:23] == 8'hFF) begin
            fp_mul2 = value;
        end else begin
            fp_mul2 = {value[31], value[30:23] + 8'd1, value[22:0]};
        end
    end
endfunction

assign busy = active;
assign done = (!active) && (iteration_count == Iteration_Cbrt);

always @(*) begin
    AddInput1 = 32'd0;
    AddInput2 = 32'd0;
    DivInput1 = 32'd0;
    DivInput2 = 32'd0;
    MulInput1 = 32'd0;
    MulInput2 = 32'd0;

    if (active) begin
        case (delay_count)
            // P^2 and S*P
            7'd0: begin
                MulInput1 = r_cbrt_re_output;
                MulInput2 = r_cbrt_re_output;
            end
            7'd1: begin
                MulInput1 = r_cbrt_im_output;
                MulInput2 = r_cbrt_im_output;
            end
            7'd2: begin
                MulInput1 = r_cbrt_re_input;
                MulInput2 = r_cbrt_re_output;
            end
            7'd3: begin
                MulInput1 = r_cbrt_im_input;
                MulInput2 = r_cbrt_im_output;
            end
            7'd4: begin
                MulInput1 = r_cbrt_re_input;
                MulInput2 = r_cbrt_im_output;
            end
            7'd5: begin
                MulInput1 = r_cbrt_im_input;
                MulInput2 = r_cbrt_re_output;
            end
            7'd6: begin
                MulInput1 = fp_mul2(r_cbrt_re_output);
                MulInput2 = r_cbrt_im_output;
            end
            7'd8: begin
                AddInput1 = r_temp[0];
                AddInput2 = fp_neg(MulOutput);
            end
            7'd10: begin
                AddInput1 = r_temp[2];
                AddInput2 = fp_neg(MulOutput);
            end
            7'd12: begin
                AddInput1 = r_temp[3];
                AddInput2 = MulOutput;
            end

            // P^4 and P^3
            7'd14: begin
                MulInput1 = r_temp[1];
                MulInput2 = r_temp[1];
            end
            7'd15: begin
                MulInput1 = r_temp[4];
                MulInput2 = r_temp[4];
            end
            7'd16: begin
                MulInput1 = fp_mul2(r_temp[1]);
                MulInput2 = r_temp[4];
            end
            7'd17: begin
                MulInput1 = r_temp[1];
                MulInput2 = r_cbrt_re_output;
            end
            7'd18: begin
                MulInput1 = r_temp[4];
                MulInput2 = r_cbrt_im_output;
            end
            7'd19: begin
                MulInput1 = r_temp[1];
                MulInput2 = r_cbrt_im_output;
            end
            7'd20: begin
                MulInput1 = r_temp[4];
                MulInput2 = r_cbrt_re_output;
            end
            7'd22: begin
                AddInput1 = r_temp[0];
                AddInput2 = fp_neg(MulOutput);
            end
            7'd25: begin
                AddInput1 = r_temp[6];
                AddInput2 = fp_neg(MulOutput);
            end
            7'd27: begin
                AddInput1 = r_temp[7];
                AddInput2 = MulOutput;
            end
            7'd28: begin
                AddInput1 = r_temp[8];
                AddInput2 = fp_mul2(r_temp[2]);
            end
            7'd29: begin
                AddInput1 = r_temp[5];
                AddInput2 = fp_mul2(r_temp[3]);
            end
            7'd31: begin
                AddInput1 = fp_mul2(r_temp[9]);
                AddInput2 = r_cbrt_re_input;
            end
            7'd33: begin
                AddInput1 = fp_mul2(r_temp[10]);
                AddInput2 = r_cbrt_im_input;
            end

            // Complex divide: (num_re + j*num_im) / (den_re + j*den_im)
            7'd39: begin
                MulInput1 = r_temp[11];
                MulInput2 = r_temp[13];
            end
            7'd40: begin
                MulInput1 = r_temp[12];
                MulInput2 = r_temp[14];
            end
            7'd41: begin
                MulInput1 = r_temp[12];
                MulInput2 = r_temp[13];
            end
            7'd42: begin
                MulInput1 = r_temp[11];
                MulInput2 = r_temp[14];
            end
            7'd43: begin
                MulInput1 = r_temp[13];
                MulInput2 = r_temp[13];
            end
            7'd44: begin
                MulInput1 = r_temp[14];
                MulInput2 = r_temp[14];
            end
            7'd47: begin
                AddInput1 = r_temp[0];
                AddInput2 = MulOutput;
            end
            7'd49: begin
                AddInput1 = r_temp[1];
                AddInput2 = fp_neg(MulOutput);
            end
            7'd51: begin
                AddInput1 = r_temp[2];
                AddInput2 = MulOutput;
            end
            7'd57: begin
                DivInput1 = r_temp[15];
                DivInput2 = r_temp[17];
            end
            7'd58: begin
                DivInput1 = r_temp[16];
                DivInput2 = r_temp[17];
            end
            default: begin
            end
        endcase
    end
end

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_cbrt_re_output <= 32'd0;
        r_cbrt_im_output <= 32'd0;
        iteration_count <= 5'd0;
        delay_count <= 7'd0;
        active <= 1'b0;
        for (i = 0; i < 18; i = i + 1) begin
            r_temp[i] <= 32'd0;
        end
    end else begin
        if (start && !active) begin
            r_cbrt_re_output <= r_cbrt_re_init;
            r_cbrt_im_output <= r_cbrt_im_init;
            iteration_count <= 5'd0;
            delay_count <= 7'd0;
            active <= 1'b1;
        end else if (active) begin
            case (delay_count)
                7'd7:  r_temp[0]  <= MulOutput;
                7'd9:  r_temp[2]  <= MulOutput;
                7'd11: r_temp[3]  <= MulOutput;
                7'd13: begin
                    r_temp[1] <= AddOutput;
                    r_temp[4] <= MulOutput;
                end
                7'd15: r_temp[2] <= AddOutput;
                7'd17: r_temp[3] <= AddOutput;

                7'd21: r_temp[0] <= MulOutput;
                7'd23: r_temp[5] <= MulOutput;
                7'd24: r_temp[6] <= MulOutput;
                7'd26: r_temp[7] <= MulOutput;
                7'd27: r_temp[8] <= AddOutput;
                7'd30: r_temp[9] <= AddOutput;
                7'd32: r_temp[10] <= AddOutput;
                7'd33: r_temp[11] <= AddOutput;
                7'd34: r_temp[12] <= AddOutput;
                7'd36: r_temp[13] <= AddOutput;
                7'd38: r_temp[14] <= AddOutput;

                7'd46: r_temp[0] <= MulOutput;
                7'd48: r_temp[1] <= MulOutput;
                7'd50: r_temp[2] <= MulOutput;
                7'd52: r_temp[15] <= AddOutput;
                7'd54: r_temp[16] <= AddOutput;
                7'd56: r_temp[17] <= AddOutput;

                7'd73: r_cbrt_re_output <= DivOutput;
                7'd74: r_cbrt_im_output <= DivOutput;
                default: begin
                end
            endcase

            if (delay_count < 7'd74) begin
                delay_count <= delay_count + 1'b1;
            end else if (iteration_count + 1'b1 >= Iteration_Cbrt) begin
                delay_count <= 7'd74;
                iteration_count <= iteration_count + 1'b1;
                active <= 1'b0;
            end else begin
                delay_count <= 7'd0;
                iteration_count <= iteration_count + 1'b1;
            end
        end
    end
end

endmodule
