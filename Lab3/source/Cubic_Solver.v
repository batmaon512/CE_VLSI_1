module Divide_int #(
    parameter WIDTH = 8,
    parameter DIVIDER = 21845,
    parameter SHIFT = 16
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] input_scale,
    output wire [WIDTH-1:0] output_scale
);
    wire signed [8:0]  diff = $signed({1'b0, input_scale}) - 9'sd127;
    wire signed [23:0] mult_res = diff * $signed({1'b0, DIVIDER});
    wire signed [13:0] shift_res = mult_res >>> SHIFT;
    wire signed [13:0] cbrt_scale_raw = 14'sd127 + shift_res;

    reg [WIDTH-1:0] output_scale_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_scale_r <= {WIDTH{1'b0}};
        end else begin
            output_scale_r <= cbrt_scale_raw[WIDTH-1:0];
        end
    end

    assign output_scale = output_scale_r;
endmodule

module Cubic_Solver #(
    parameter Iteration_Sqrt = 10,
    parameter Iteration_Cbrt = 20
)(
    input wire        clk,
    input wire        rst_n,
    input wire        start,
    output reg        done,
//   
    input  wire [31:0] FP_a,
    input  wire [31:0] FP_b,
    input  wire [31:0] FP_c,
    input  wire [31:0] FP_d,
    output reg [31:0] FP_x0_re,
    output reg [31:0] FP_x0_im,
    output reg [31:0] FP_x1_re,
    output reg [31:0] FP_x1_im,
    output reg [31:0] FP_x2_re,
    output reg [31:0] FP_x2_im
);

//Registers
/////////////////////////
reg [31:0] r_a, r_b, r_c, r_d;
reg [31:0] r_temp [0:63];
// STATE: DELTA_COMPUTE
reg [31:0] r_delta, r_delta_0, r_delta_1, r_delta_0_Compare;
// STATE: Sqrt_COMPUTE
reg [31:0] r_sqrt_input, r_sqrt_output; // r_squrt_input: S, r_sqrt_output: P
// STATE: Cbrt_COMPUTE
reg [31:0] r_cbrt_re_input, r_cbrt_im_input, r_cbrt_re_output, r_cbrt_im_output;
reg [7:0] exponent_max;
// STATE: C_COMPUTE
reg [31:0] r_C_re, r_C_im;

// State Machine
reg [3:0] state;
reg [3:0] next_state;
reg [1:0] case_index; // 01: Case 1, 10: Case 2a, 11: Case 2b.
reg [4:0] iteration_count; // For iterative methods like sqrt and cbrt.
reg [6:0] delay_count; // For multi-cycle operations.
// STATE: BRANCH_CHECK
reg READY_BRANCH_CHECK;
localparam  IDLE = 4'b0000,
            STANDARDIZE = 4'b0001,
            DELTA_COMPUTE = 4'b0010,
            CASE_CHECK = 4'b0011,
            Sqrt_COMPUTE = 4'b0100,
            BRANCH_CHECK = 4'b0101,
            Cbrt_COMPUTE_R = 4'b0110,
            Cbrt_COMPUTE_C = 4'b0111,
            CASE1_COMPUTE = 4'b1000,
            CASE2A_COMPUTE = 4'b1001,
            CASE2B_COMPUTE = 4'b1010,
            DONE = 4'b1011;
localparam  DELAY_STANDARDIZE = 7'd23,
            DELAY_DELTA_COMPUTE = 7'd35,
            DELAY_Sqrt_COMPUTE = 7'd35,
            DELAY_Cbrt_COMPUTE_R = 7'd36,
            DELAY_Cbrt_COMPUTE_C = 7'd74,
            DELAY_CASE1_COMPUTE = 7'd18,
            DELAY_CASE2A_COMPUTE = 7'd12,
            DELAY_CASE2B_COMPUTE = 7'd29;

localparam [31:0] EPSILON_RE = 32'hBF000000; // -0.5 in FP32
localparam [31:0] EPSILON_IM = 32'h3F5DB3D8; 
//Input in FP operation, output in FP operation
reg [31:0] MulInput1, MulInput2;
wire [31:0] MulOutput;

reg  [31:0] AddInput1, AddInput2;
wire [31:0] AddOutput;

reg  [31:0] DivInput1, DivInput2;
wire [31:0] DivOutput;

reg [7:0] cbrt_scale_in;
wire [7:0] cbrt_scale_out;
wire [31:0] add_output_div2 = {AddOutput[31], AddOutput[30:23] - 8'd1, AddOutput[22:0]}; // AddOutput / 2
wire [7:0] sqrt_output_exp = (({1'b0, r_delta[30:23]} + 9'd127) >> 1);
wire [31:0] sqrt_output_init = {1'b0, sqrt_output_exp, r_delta[22:0]};
wire [7:0] r_delta_1_exp_minus1 = r_delta_1[30:23] != 0 ? r_delta_1[30:23] - 8'd1 : 0;
wire [7:0] r_sqrt_output_exp_minus1 = r_sqrt_output[30:23] != 0 ? r_sqrt_output[30:23] - 8'd1 : 0;
wire [7:0] r_a_exp_plus1 = r_a[30:23] + 8'd1;
wire [31:0] r_a_shift_left1 = {r_a[31], r_a_exp_plus1, r_a[22:0]};
wire [31:0] neg_r_a = {~r_a[31], r_a[30:0]};
wire [31:0] neg_add_output = {~AddOutput[31], AddOutput[30:0]};
wire [7:0] r_b_exp_plus1 = r_b[30:23] + 8'd1;
wire [31:0] r_b_shift_left1 = {r_b[31], r_b_exp_plus1, r_b[22:0]};
wire [7:0] add_output_exp_plus1 = AddOutput[30:23] + 8'd1;
wire [31:0] add_output_shift_left1 = {AddOutput[31], add_output_exp_plus1, AddOutput[22:0]};
wire [7:0] r_delta_0_exp_plus2 = r_delta_0[30:23] + 8'd2;
wire [31:0] neg_r_delta_0_shift_left2 = {~r_delta_0[31], r_delta_0_exp_plus2, r_delta_0[22:0]};
wire [7:0] r_sqrt_input_exp_plus1 = r_sqrt_input[30:23] + 8'd1;
wire [31:0] r_sqrt_input_shift_left1 = {r_sqrt_input[31], r_sqrt_input_exp_plus1, r_sqrt_input[22:0]};
wire [7:0] r_temp1_exp_plus1 = r_temp[1][30:23] + 8'd1;
wire [31:0] r_temp1_shift_left1 = {r_temp[1][31], r_temp1_exp_plus1, r_temp[1][22:0]};
wire [7:0] r_cbrt_re_input_exp_plus1 = r_cbrt_re_input[30:23] + 8'd1;
wire [31:0] r_cbrt_re_input_shift_left1 = {r_cbrt_re_input[31], r_cbrt_re_input_exp_plus1, r_cbrt_re_input[22:0]};
wire [7:0] r_cbrt_re_output_exp_plus1 = r_cbrt_re_output[30:23] + 8'd1;
wire [31:0] r_cbrt_re_output_shift_left1 = {r_cbrt_re_output[31], r_cbrt_re_output_exp_plus1, r_cbrt_re_output[22:0]};
wire [7:0] r_C_re_exp_plus1 = r_C_re[30:23] + 8'd1;
wire [31:0] r_C_re_shift_left1 = {r_C_re[31], r_C_re_exp_plus1, r_C_re[22:0]};
wire [7:0] mul_output_exp_plus1 = MulOutput[30:23] + 8'd1;
wire [31:0] mul_output_shift_left1 = {MulOutput[31], mul_output_exp_plus1, MulOutput[22:0]};
wire [7:0] r_temp0_exp_plus1 = r_temp[0][30:23] + 8'd1;
wire [31:0] r_temp0_shift_left1 = {r_temp[0][31], r_temp0_exp_plus1, r_temp[0][22:0]};
wire [31:0] neg_r_delta = {~r_delta[31], r_delta[30:0]};
wire [31:0] neg_mul_output = {~MulOutput[31], MulOutput[30:0]};
//FP operation
Mul_FP Mul_FP_0 (.clk(clk),.FP_in1(MulInput1),.FP_in2(MulInput2),.FP_out(MulOutput));

Add_FP Add_FP_0 (.clk(clk),.in1(AddInput1),.in2(AddInput2),.data_out(AddOutput));

Div_FP #(32) Div_FP_0 (.clk(clk),.FP_in1(DivInput1),.FP_in2(DivInput2),.FP_out(DivOutput));

Divide_int #(8, 85, 8) Divide_int_0 (
    .clk(clk),
    .rst_n(rst_n),
    .input_scale(cbrt_scale_in),
    .output_scale(cbrt_scale_out)
);

wire [31:0] temp_cbrt_re = {r_delta_1[31], r_delta_1_exp_minus1, r_delta_1[22:0]};
wire [31:0] temp_cbrt_im = {r_sqrt_output[31], r_sqrt_output_exp_minus1, r_sqrt_output[22:0]};

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


// State Transition
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end
// Next State Logic
always @(*) begin
    case(state)
        IDLE:
            next_state = start ? STANDARDIZE : IDLE;
        STANDARDIZE:
            next_state = (delay_count == DELAY_STANDARDIZE) ? DELTA_COMPUTE : STANDARDIZE;
        DELTA_COMPUTE:
            next_state = (delay_count == DELAY_DELTA_COMPUTE) ? CASE_CHECK : DELTA_COMPUTE;
        CASE_CHECK:
            next_state = case_index == 2'b00 ? CASE_CHECK : Sqrt_COMPUTE;
        Sqrt_COMPUTE:
            next_state = (iteration_count == Iteration_Sqrt) | (r_sqrt_input[30:23] < 2)? BRANCH_CHECK : Sqrt_COMPUTE;
        BRANCH_CHECK:
            next_state = READY_BRANCH_CHECK ? ((case_index[1] == 1'b0) ? Cbrt_COMPUTE_C : Cbrt_COMPUTE_R) : BRANCH_CHECK;
        Cbrt_COMPUTE_R:
            next_state = (iteration_count == Iteration_Cbrt) | (r_cbrt_re_input[30:23] < 2) ? (case_index[0] == 1'b0 ? CASE2A_COMPUTE : CASE2B_COMPUTE) : Cbrt_COMPUTE_R;
        Cbrt_COMPUTE_C:
            next_state = (iteration_count == Iteration_Cbrt)? CASE1_COMPUTE : Cbrt_COMPUTE_C;
        CASE1_COMPUTE:
            next_state = (delay_count == DELAY_CASE1_COMPUTE) ? DONE : CASE1_COMPUTE;
        CASE2A_COMPUTE:
            next_state = (delay_count == DELAY_CASE2A_COMPUTE) ? DONE : CASE2A_COMPUTE;
        CASE2B_COMPUTE:
            next_state = (delay_count == DELAY_CASE2B_COMPUTE) ? DONE : CASE2B_COMPUTE;
        DONE:
            next_state = DONE;
        default:
            next_state = IDLE;
    endcase
end
// Output Logic
always @(*) begin
    AddInput1 = 32'd0;
    AddInput2 = 32'd0;
    DivInput1 = 32'd0;
    DivInput2 = 32'd0;
    MulInput1 = 32'd0;
    MulInput2 = 32'd0;
    cbrt_scale_in = 8'd0;
    done = 1'b0;
    READY_BRANCH_CHECK = 1'b0;
    case(state)
        IDLE: begin
        end
        STANDARDIZE: begin
            if(delay_count == 0) begin
                AddInput1 = r_a_shift_left1;
                AddInput2 = r_a;
            end
            if(delay_count == 5) begin
                DivInput1 = r_b;
                DivInput2 = neg_add_output;
            end
            if(delay_count == 6) begin
                DivInput1 = r_c;
                DivInput2 = neg_r_a;
            end
            if(delay_count == 7) begin
                DivInput1 = r_d;
                DivInput2 = neg_r_a;
            end
        end
        DELTA_COMPUTE: begin
            // Clock 0: r_b * r_b
            if(delay_count == 0) begin
                MulInput1 = r_b;
                MulInput2 = r_b;
            end
            // Clock 1: r_b * r_c
            if(delay_count == 1) begin
                MulInput1 = r_b;
                MulInput2 = r_c;
            end
            // Clock 7: (r_b<<1) * MulOutput; MulOutput + r_c
            if(delay_count == 7) begin
                MulInput1 = r_b_shift_left1; // r_b << 1
                MulInput2 = MulOutput;
                AddInput1 = MulOutput;
                AddInput2 = r_c;
            end
            // Clock 8: MulOutput + r_d
            if(delay_count == 8) begin
                AddInput1 = MulOutput;
                AddInput2 = r_d;
            end
            // Clock 12: AddOutput * AddOutput; AddOutput -> r_delta_0
            if(delay_count == 12) begin
                MulInput1 = AddOutput;
                MulInput2 = AddOutput;
            end
            // Clock 13: (AddOutput<<1) + AddOutput
            if(delay_count == 13) begin
                AddInput1 = add_output_shift_left1; // AddOutput << 1
                AddInput2 = AddOutput;
            end
            // Clock 14: MulOutput -> r_temp[0]
            if(delay_count == 14) begin
                // Will be stored in sequential logic
            end
            // Clock 18: r_temp[0] + AddOutput
            if(delay_count == 18) begin
                AddInput1 = r_temp[0];
                AddInput2 = AddOutput;
            end
            // Clock 19: MulOutput * (-r_delta_0<<2)
            if(delay_count == 19) begin
                MulInput1 = MulOutput;
                MulInput2 = neg_r_delta_0_shift_left2;
            end
            // Clock 23: AddOutput * AddOutput -> r_delta_1
            if(delay_count == 23) begin
                MulInput1 = AddOutput;
                MulInput2 = AddOutput;
            end
            // Clock 26: MulOutput -> r_delta_0_Compare
            if(delay_count == 26) begin
                // Will be stored in sequential logic
            end
            // Clock 30: MulOutput + r_delta_0_Compare
            if(delay_count == 30) begin
                AddInput1 = MulOutput;
                AddInput2 = r_delta_0_Compare;
            end
        end
        CASE_CHECK: begin

        end
        Sqrt_COMPUTE: begin
            // Clock 0: r_sqrt_output * r_sqrt_output; r_sqrt_input + (r_sqrt_input << 1)
            if(delay_count == 0) begin
                MulInput1 = r_sqrt_output;
                MulInput2 = r_sqrt_output;
                AddInput1 = r_sqrt_input;
                AddInput2 = r_sqrt_input_shift_left1;
            end
            // Clock 7: r_temp[0] + MulOutput
            if(delay_count == 7) begin
                AddInput1 = r_temp[0];
                AddInput2 = MulOutput;
            end
            // Clock 8: r_temp[1] + (r_temp[1] << 1)
            if(delay_count == 8) begin
                AddInput1 = r_temp[1];
                AddInput2 = r_temp1_shift_left1;
            end
            // Clock 12: r_sqrt_output * AddOutput
            if(delay_count == 12) begin
                MulInput1 = r_sqrt_output;
                MulInput2 = AddOutput;
            end
            // Clock 13: AddOutput + r_sqrt_input
            if(delay_count == 13) begin
                AddInput1 = AddOutput;
                AddInput2 = r_sqrt_input;
            end
            // Clock 19: MulOutput / r_temp[2]
            if(delay_count == 19) begin
                DivInput1 = MulOutput;
                DivInput2 = r_temp[2];
            end
        end
        BRANCH_CHECK: begin
            if(case_index == 2'b01) begin
                READY_BRANCH_CHECK = (delay_count == 2) ? 1'b1 : 1'b0;
                cbrt_scale_in = exponent_max;
            end else if(case_index == 2'b10) begin
                READY_BRANCH_CHECK = (delay_count == 1) ? 1'b1 : 1'b0;
                cbrt_scale_in = r_delta_1[30:23];
            end else if(case_index == 2'b11) begin
                if(delay_count == 0) begin
                    AddInput1 = r_sqrt_output;
                    AddInput2 = r_delta_1;
                end
                cbrt_scale_in = r_cbrt_re_input[30:23];
                READY_BRANCH_CHECK = (delay_count == 7) ? 1'b1 : 1'b0;
            end
        end

        Cbrt_COMPUTE_R: begin
            if(delay_count == 0) begin
                MulInput1 = r_cbrt_re_output;
                MulInput2 = r_cbrt_re_output;
            end

            if(delay_count == 1) begin
                MulInput1 = r_cbrt_re_input_shift_left1;
                MulInput2 = r_cbrt_re_output;
            end

            if(delay_count == 7) begin
                MulInput1 = MulOutput;
                MulInput2 = MulOutput;
            end

            if(delay_count == 8) begin
                MulInput1 = r_temp[0];
                MulInput2 = r_cbrt_re_output_shift_left1;
            end

            if(delay_count == 14) begin
                AddInput1 = MulOutput;
                AddInput2 = r_temp[1];
            end

            if(delay_count == 15) begin
                AddInput1 = MulOutput;
                AddInput2 = r_cbrt_re_input;
            end

            if(delay_count == 19) begin
                AddInput1 = AddOutput;
                AddInput2 = r_cbrt_re_input;
            end

            if(delay_count == 20) begin
                DivInput1 = r_temp[2];
                DivInput2 = AddOutput;
            end
        end

        Cbrt_COMPUTE_C: begin
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
        CASE1_COMPUTE: begin
            if(delay_count == 0) begin
                MulInput1 = r_C_re;
                MulInput2 = EPSILON_RE;
                AddInput1 = r_C_re_shift_left1;
                AddInput2 = r_b;
            end

            if(delay_count == 1) begin
                MulInput1 = r_C_im;
                MulInput2 = EPSILON_IM;
            end

            if(delay_count == 7) begin
                AddInput1 = mul_output_shift_left1;
                AddInput2 = r_b;
            end

            if(delay_count == 12) begin
                AddInput1 = r_temp0_shift_left1;
                AddInput2 = AddOutput;
            end

            if(delay_count == 13) begin
                AddInput1 = {~r_temp[0][31], r_temp0_exp_plus1, r_temp[0][22:0]};
                AddInput2 = r_temp[1];
            end
        end

        CASE2A_COMPUTE: begin
            if(delay_count == 0) begin
                MulInput1 = r_C_re;
                MulInput2 = EPSILON_RE;
                AddInput1 = r_C_re;
                AddInput2 = r_b;
            end

            if(delay_count == 1) begin
                MulInput1 = r_C_re;
                MulInput2 = EPSILON_IM;
            end

            if(delay_count == 7) begin
                AddInput1 = MulOutput;
                AddInput2 = r_b;
            end
        end
        CASE2B_COMPUTE: begin
            // Clock 0: start multiply/add/div chains
            if(delay_count == 0) begin
                MulInput1 = r_C_re;
                MulInput2 = EPSILON_RE;
                AddInput1 = r_C_re;
                AddInput2 = r_b;
                DivInput1 = r_delta_0;
                DivInput2 = r_C_re;
            end
            // Clock 1: refine multiply (imag part)
            if(delay_count == 1) begin
                MulInput1 = r_C_re;
                MulInput2 = EPSILON_IM;
            end
            // Clock 7: use earlier MulOutput with r_b
            if(delay_count == 7) begin
                AddInput1 = MulOutput;
                AddInput2 = r_b;
            end
            // Clock 16: use DivOutput with EPSILON_RE and add with r_temp[0]
            if(delay_count == 16) begin
                MulInput1 = DivOutput;
                MulInput2 = EPSILON_RE;
                AddInput1 = DivOutput;
                AddInput2 = r_temp[0];
            end
            // Clock 17: multiply r_temp[3] (just produced by DivOutput at 16) with EPSILON_IM
            if(delay_count == 17) begin
                MulInput1 = r_temp[3];
                MulInput2 = EPSILON_IM;
            end
            // Clock 23: prepare Add using latest MulOutput and r_temp[2]
            if(delay_count == 23) begin
                AddInput1 = MulOutput;
                AddInput2 = r_temp[2];
            end
            // Clock 24: subtract (negate MulOutput) with r_temp[1]
            if(delay_count == 24) begin
                AddInput1 = neg_mul_output;
                AddInput2 = r_temp[1];
            end
        end

        DONE: begin
            done = 1'b1;
        end
        default: begin
            // For other states, you can keep the outputs unchanged or set them to some intermediate values if needed for debugging.
        end
    endcase
end

always @(posedge clk) begin
        if (!rst_n) begin
            r_a <= 32'd0;
            r_b <= 32'd0;
            r_c <= 32'd0;
            r_d <= 32'd0;
            r_delta <= 32'd0;
            r_delta_0 <= 32'd0;
            r_delta_1 <= 32'd0;
            r_delta_0_Compare <= 32'd0;
            r_sqrt_input <= 32'd0;
            r_sqrt_output <= 32'd0;
            r_cbrt_re_input <= 32'd0;
            r_cbrt_im_input <= 32'd0;
            r_cbrt_re_output <= 32'd0;
            r_cbrt_im_output <= 32'd0;
            r_C_re <= 32'd0;
            r_C_im <= 32'd0;
            FP_x0_re <= 32'd0;
            FP_x0_im <= 32'd0;
            FP_x1_re <= 32'd0;
            FP_x1_im <= 32'd0;
            FP_x2_re <= 32'd0;
            FP_x2_im <= 32'd0;
            delay_count <= 7'd0;
            iteration_count <= 5'd0;
            case_index <= 2'd0;
            exponent_max <= 8'd0;
        end else begin
            case(state)
                IDLE: begin
                    r_a <= FP_a;
                    r_b <= FP_b;
                    r_c <= FP_c;
                    r_d <= FP_d;
                    delay_count <= 7'd0;
                    iteration_count <= 5'd0;
                    case_index <= 2'd0;
                end
                STANDARDIZE: begin
                    if(delay_count < DELAY_STANDARDIZE) begin
                        delay_count <= delay_count + 1;
                    end else begin
                        delay_count <= 0; // Reset for next state
                    end
                    if(delay_count == 5) begin
                        r_a <= AddOutput;
                    end
                    if(delay_count == 21) begin
                        r_b <= DivOutput;
                    end
                    if(delay_count == 22) begin
                        r_c <= DivOutput;
                    end
                    if(delay_count == 23) begin
                        r_d <= DivOutput;
                    end
                end
                DELTA_COMPUTE: begin
                    if(delay_count < DELAY_DELTA_COMPUTE) begin
                        delay_count <= delay_count + 1;
                    end else begin
                        delay_count <= 0;
                    end
                    // Clock 12: Store r_delta_0 = AddOutput
                    if(delay_count == 12) begin
                        r_delta_0 <= AddOutput;
                    end
                    // Clock 14: Store r_temp[0] = MulOutput
                    if(delay_count == 14) begin
                        r_temp[0] <= MulOutput;
                    end
                    // Clock 23: Store r_delta_1 = MulOutput
                    if(delay_count == 23) begin
                        r_delta_1 <= AddOutput;
                    end
                    // Clock 26: Store r_delta_0_Compare = MulOutput
                    if(delay_count == 26) begin
                        r_delta_0_Compare <= MulOutput;
                    end
                    // Clock 35: Store r_delta = AddOutput
                    if(delay_count == 35) begin
                        r_delta <= AddOutput;
                    end
                end
                CASE_CHECK: begin
                    case_index <= (r_delta[31] == 1'b1 && r_delta[30:23] != 0) ? 2'b01 : (r_delta_1[31] == 1'b1 && r_delta_0_Compare[30:23] < 100) ? 2'b10 : 2'b11;
                    r_sqrt_input <= (case_index == 2'b01 ? neg_r_delta : r_delta);
                    r_sqrt_output <= sqrt_output_init;
                    iteration_count <= 5'd0;
                end
                Sqrt_COMPUTE: begin
                    if(r_sqrt_input[30:23] < 2) r_sqrt_output <= r_sqrt_input;
                    else if(delay_count == DELAY_Sqrt_COMPUTE | iteration_count == Iteration_Sqrt) begin
                        delay_count <= 0;
                        if(iteration_count < Iteration_Sqrt) begin
                            iteration_count <= iteration_count + 1;
                        end else begin
                            iteration_count <= 0;
                        end
                    end
                    else begin
                        delay_count <= delay_count + 1;
                    end

                    // One iteration pipeline checkpoints for Sqrt_COMPUTE
                    if(delay_count == 5) begin
                        r_temp[0] <= AddOutput;
                    end
                    if(delay_count == 7) begin
                        r_temp[1] <= MulOutput;
                    end
                    if(delay_count == 18) begin
                        r_temp[2] <= AddOutput;
                    end
                    if(delay_count == DELAY_Sqrt_COMPUTE) begin
                        r_sqrt_output <= DivOutput;
                    end
                    
                end
                BRANCH_CHECK: begin
                    if(case_index == 2'b01) begin
                        r_cbrt_re_input <= temp_cbrt_re;
                        r_cbrt_im_input <= temp_cbrt_im;
                        if(delay_count == 0) begin
                            exponent_max <= temp_cbrt_re[30:23] > temp_cbrt_im[30:23] ? temp_cbrt_re[30:23] : temp_cbrt_im[30:23];
                            delay_count <= delay_count + 1;
                        end else if(delay_count == 2) begin
                            r_cbrt_re_output <= {r_cbrt_re_input[31], r_cbrt_re_input[30:23] != 0 ? cbrt_scale_out : 8'd0 , r_cbrt_re_input[22:0]};
                            r_cbrt_im_output <= {r_cbrt_im_input[31], r_cbrt_im_input[30:23] != 0 ? cbrt_scale_out : 8'd0, r_cbrt_im_input[22:0]};
                            delay_count <= 0;
                        end else begin
                            delay_count <= delay_count + 1;
                        end
                    end else if(case_index == 2'b10) begin
                        if(delay_count == 0) begin
                            r_cbrt_re_input <= r_delta_1;
                            r_cbrt_im_input <= 0;
                            r_cbrt_im_output <= 0;
                            delay_count <= 1;
                        end else begin
                            r_cbrt_re_output <= {r_delta_1[31], cbrt_scale_out, r_delta_1[22:0]};
                            delay_count <= 0;
                        end
                    end else if(case_index == 2'b11) begin
                        if(delay_count == 5) begin
                            r_cbrt_re_input <= add_output_div2;
                            r_cbrt_im_input <= 0;
                            r_cbrt_im_output <= 0;
                            delay_count <= delay_count + 1;
                        end
                        else if(delay_count == 7) begin
                            delay_count <= 0;
                            r_cbrt_re_output <= {r_cbrt_re_input[31], cbrt_scale_out, r_cbrt_re_input[22:0]};
                        end 
                        else delay_count <= delay_count + 1;
                    end
                end
                Cbrt_COMPUTE_R: begin
                    if(r_cbrt_re_input[30:23] < 2) begin 
                        r_cbrt_re_output <= 0;
                    end
                    else if(delay_count == DELAY_Cbrt_COMPUTE_R | iteration_count == Iteration_Cbrt) begin
                        delay_count <= 0;
                        if(iteration_count < Iteration_Cbrt) begin
                            iteration_count <= iteration_count + 1;
                        end else begin
                            iteration_count <= 0;
                        end
                    end
                    else begin
                        delay_count <= delay_count + 1;
                    end

                    if(delay_count == 7) begin
                        r_temp[0] <= MulOutput;
                    end
                    if(delay_count == 8) begin
                        r_temp[1] <= MulOutput;
                    end
                    if(delay_count == 19) begin
                        r_temp[2] <= AddOutput;
                    end
                    if(delay_count == DELAY_Cbrt_COMPUTE_R) begin
                        r_cbrt_re_output <= DivOutput;
                        r_C_re <= DivOutput;
                        r_C_im <= r_cbrt_im_output;
                    end
                end
                Cbrt_COMPUTE_C: begin
                    if(delay_count == DELAY_Cbrt_COMPUTE_C | iteration_count == Iteration_Cbrt) begin
                        delay_count <= 0;
                        if(iteration_count < Iteration_Cbrt) begin
                            iteration_count <= iteration_count + 1;
                        end else begin
                            iteration_count <= 0;
                        end
                    end
                    else begin
                        delay_count <= delay_count + 1;
                    end

                    case (delay_count)
                        7'd7:  r_temp[0]  <= MulOutput;   // Re(P^2) partial: pr*pr
                        7'd9:  r_temp[2]  <= MulOutput;   // Re(S*P) partial: sr*pr
                        7'd11: r_temp[3]  <= MulOutput;   // Im(S*P) partial: sr*pi
                        7'd13: begin
                            r_temp[1] <= AddOutput;       // P^2 real
                            r_temp[4] <= MulOutput;       // P^2 imag = 2*pr*pi
                        end
                        7'd15: r_temp[2] <= AddOutput;    // S*P real
                        7'd17: r_temp[3] <= AddOutput;    // S*P imag

                        7'd21: r_temp[0] <= MulOutput;    // P^4 real partial
                        7'd23: r_temp[5] <= MulOutput;    // P^4 imag
                        7'd24: r_temp[6] <= MulOutput;    // P^3 real partial
                        7'd26: r_temp[7] <= MulOutput;    // P^3 imag partial
                        7'd27: r_temp[8] <= AddOutput;    // P^4 real
                        7'd30: r_temp[9] <= AddOutput;    // P^3 real
                        7'd32: r_temp[10] <= AddOutput;   // P^3 imag
                        7'd33: r_temp[11] <= AddOutput;   // numerator real = P^4 + 2SP
                        7'd34: r_temp[12] <= AddOutput;   // numerator imag = P^4_im + 2SP_im
                        7'd36: r_temp[13] <= AddOutput;   // denominator real = 2P^3 + S
                        7'd38: r_temp[14] <= AddOutput;   // denominator imag = 2P^3 + S

                        7'd46: r_temp[0] <= MulOutput;    // num_re * den_re
                        7'd48: r_temp[1] <= MulOutput;    // num_im * den_re
                        7'd50: r_temp[2] <= MulOutput;    // den_re^2
                        7'd52: r_temp[15] <= AddOutput;   // division real numerator
                        7'd54: r_temp[16] <= AddOutput;   // division imag numerator
                        7'd56: r_temp[17] <= AddOutput;   // |den|^2

                        7'd73: r_cbrt_re_output <= DivOutput;
                        7'd74: begin 
                            r_cbrt_im_output <= DivOutput;
                            r_C_re <= r_cbrt_re_output;
                            r_C_im <= DivOutput;
                        end
                        default: begin
                        end
                    endcase
                end
                CASE1_COMPUTE: begin
                    if(delay_count < DELAY_CASE1_COMPUTE) begin
                        delay_count <= delay_count + 1;
                    end else begin
                        delay_count <= 0;
                    end

                    if(delay_count == 5) begin
                        FP_x0_re <= AddOutput;
                        FP_x0_im <= 32'd0;
                    end
                    if(delay_count == 8) begin
                        r_temp[0] <= MulOutput;
                    end
                    if(delay_count == 12) begin
                        r_temp[1] <= AddOutput;
                    end
                    if(delay_count == 17) begin
                        FP_x1_re <= AddOutput;
                        FP_x1_im <= 32'd0;
                    end
                    if(delay_count == 18) begin
                        FP_x2_re <= AddOutput;
                        FP_x2_im <= 32'd0;
                    end
                end
                CASE2A_COMPUTE: begin
                    if(delay_count < DELAY_CASE2A_COMPUTE) begin
                        delay_count <= delay_count + 1;
                    end else begin
                        delay_count <= 0;
                    end

                    if(delay_count == 5) begin
                        FP_x0_re <= AddOutput;
                        FP_x0_im <= 32'd0;
                    end
                    if(delay_count == 8) begin
                        FP_x1_im <= MulOutput;
                        FP_x2_im <= neg_mul_output;
                    end
                    if(delay_count == 12) begin
                        FP_x1_re <= AddOutput;
                        FP_x2_re <= AddOutput;
                    end
                end
                CASE2B_COMPUTE: begin
                    if(delay_count < DELAY_CASE2B_COMPUTE) begin
                        delay_count <= delay_count + 1;
                    end else begin
                        delay_count <= 0;
                    end
                    if(delay_count == 5) begin
                        r_temp[0] <= AddOutput;
                    end
                    // Clock 8: capture intermediate MulOutput -> r_temp[1]
                    if(delay_count == 8) begin
                        r_temp[1] <= MulOutput;
                    end
                    // Clock 12: capture AddOutput -> r_temp[2]
                    if(delay_count == 12) begin
                        r_temp[2] <= AddOutput;
                    end
                    // Clock 16: capture DivOutput -> r_temp[3]
                    if(delay_count == 16) begin
                        r_temp[3] <= DivOutput;
                    end

                    // Clock 21: FP_x0_re := AddOutput (from earlier add)
                    if(delay_count == 21) begin
                        FP_x0_re <= AddOutput;
                        FP_x0_im <= 32'd0;
                    end

                    // Clock 28: FP_x1_re and FP_x2_re := AddOutput (paired)
                    if(delay_count == 28) begin
                        FP_x1_re <= AddOutput;
                        FP_x2_re <= AddOutput;
                    end

                    // Clock 29: FP_x1_im := AddOutput; FP_x2_im := -AddOutput
                    if(delay_count == 29) begin
                        FP_x1_im <= AddOutput;
                        FP_x2_im <= neg_add_output;
                    end
                end
                default: begin
                end
            endcase
        end
    end


endmodule