module Cubic_Solver #(
    parameter Iteration_Sqrt = 10,
    parameter Iteration_Cbrt = 10
)(
    input wire        clk,
    input wire        rst_n,
    input wire        start,
    output wire        done,
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
//Input in FP operation, output in FP operation
reg [31:0] MulInput1, MulInput2;
wire [31:0] MulOutput;

reg  [31:0] AddInput1, AddInput2;
wire [31:0] AddOutput;

reg  [31:0] DivInput1, DivInput2;
wire [31:0] DivOutput;

//FP operation
Mul_FP Mul_FP_0 (.clk(clk),.FP_in1(MulInput1),.FP_in2(MulInput2),.FP_out(MulOutput));

Add_FP Add_FP_0 (.clk(clk),.in1(AddInput1),.in2(AddInput2),.data_out(AddOutput));

Div_FP #(32) Div_FP_0 (.clk(clk),.FP_in1(DivInput1),.FP_in2(DivInput2),.FP_out(DivOutput));

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
// STATE: C_COMPUTE
reg [31:0] r_C_re, r_C_im;


// State Machine
reg [3:0] state;
reg [3:0] next_state;
reg [1:0] case_index; // 00: Case 1, 01: Case 2a, 10: Case 2b.
reg [4:0] iteration_count; // For iterative methods like sqrt and cbrt.
reg [6:0] delay_count; // For multi-cycle operations.
localparam  IDLE = 4'b0000,
            STANDARDIZE = 4'b0001,
            DELTA_COMPUTE = 4'b0010,
            Sqrt_COMPUTE = 4'b0011,
            BRANCH_CHECK = 4'b0100,
            Cbrt_COMPUTE_R = 4'b0101,
            Cbrt_COMPUTE_C = 4'b0110,
            CASE1_COMPUTE = 4'b0111,
            CASE2A_COMPUTE = 4'b1000,
            CASE2B_COMPUTE = 4'b1001,
            DONE = 4'b1010;
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
            next_state = (delay_count == 23) ? DELTA_COMPUTE : STANDARDIZE;
        DELTA_COMPUTE:
            next_state = (delay_count == 35) ? Sqrt_COMPUTE : DELTA_COMPUTE;
        Sqrt_COMPUTE:
            next_state = (iteration_count == Iteration_Sqrt) | (r_sqrt_input[30:23] < 2)? BRANCH_CHECK : Sqrt_COMPUTE;
        BRANCH_CHECK:
            next_state = case_index[1] ? Cbrt_COMPUTE_R : Cbrt_COMPUTE_C;
        Cbrt_COMPUTE_R:
            next_state = (iteration_count == Iteration_Cbrt) | (r_cbrt_re_input[30:23] < 2) ? (case_index == 2'b01 ? CASE2A_COMPUTE : CASE2B_COMPUTE) : Cbrt_COMPUTE_R;
        Cbrt_COMPUTE_C:
            next_state = (iteration_count == Iteration_Cbrt)? CASE1_COMPUTE : Cbrt_COMPUTE_C;
        CASE1_COMPUTE:
            next_state = (iteration_count == Iteration_Cbrt) ? DONE : CASE1_COMPUTE;
        CASE2A_COMPUTE:
            next_state = (iteration_count == Iteration_Cbrt) ? DONE : CASE2A_COMPUTE;
        CASE2B_COMPUTE:
            next_state = (iteration_count == Iteration_Cbrt) ? DONE : CASE2B_COMPUTE;
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
    case(state)
        IDLE: begin
        end
        STANDARDIZE: begin
            if(delay_count == 0) begin
                AddInput1 = {r_a[31], r_a[30:23] + 8'd1, r_a[22:0]};
                AddInput2 = r_a;
            end
            if(delay_count == 5) begin
                DivInput1 = r_b;
                DivInput2 = {~AddOutput[31], AddOutput[30:0]};
            end
            if(delay_count == 6) begin
                DivInput1 = r_c;
                DivInput2 = {~r_a[31], r_a[30:0]};
            end
            if(delay_count == 7) begin
                DivInput1 = r_d;
                DivInput2 = {~r_a[31], r_a[30:0]};
            end
        end
        DONE: begin
            done <= 1'b1;
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
                    if(delay_count < 24) begin
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
                default: begin
                end
            endcase
        end
    end


endmodule