module Inv_FP#(
    parameter integer TW_W = 32
)(
    input  wire signed [TW_W-1:0] in_val,
    output wire signed [TW_W-1:0] out_val
);
    assign out_val = {~in_val[TW_W-1], in_val[TW_W-2:0]};
endmodule

module priority_encoder #(
    parameter WIDTH = 8
) (
    input  [WIDTH-1:0] in,
    output reg [$clog2(WIDTH)-1:0] out,
    output reg valid
);
    integer i;
    always @(*) begin
        out = 0;
        valid = 1'b0;
        for (i = WIDTH-1; i >= 0; i = i - 1) begin
            if (in[i] & !valid) begin
                out = WIDTH - 1 - i;
                valid = 1'b1;
            end
        end
    end
endmodule

module AFP_Compare_Exponents(
input wire [31:0]   in1,
input wire [31:0]   in2,
input clk,
//Output
output reg [4:0]    shift,
output reg          compare,
output reg [7:0]    exp1,
output reg [7:0]    exp2,
output reg          sign1,
output reg          sign2,
output reg [22:0]   fra1,
output reg [22:0]   fra2
);
wire [8:0] w1;
wire [8:0] w2;
assign w1 = {1'b0, in2[30:23]} - {1'b0, in1[30:23]};
//assign compare = w1[8];
assign w2 = w1[8]? -w1 : w1;
//assign shift = (w2 > 9'd24)? 5'd24 : w2[4:0];

always @(posedge clk) begin
    compare <= w1[8];
    shift   <= (w2 > 9'd25)? 5'd25 : w2[4:0];
    exp1    <= in1[30:23];
    exp2    <= in2[30:23];
    sign1   <= in1[31];
    sign2   <= in2[31];
    fra1    <= in1[22:0];
    fra2    <= in2[22:0];
end
endmodule

module AFP_Shift(
input               clk,
input wire [4:0]    shift,
input wire          compare,// 0: 1 < 2, 1: 1 > 2
input wire [7:0]    exp1,
input wire [7:0]    exp2,
input wire          sign1,
input wire          sign2,
input wire [22:0]   fra1,
input wire [22:0]   fra2,
//Output
output reg [7:0]    exp,
output reg [24:0]   fra_out1,
output reg [24:0]   fra_out2,
output reg          op,
output reg          sign
);
wire [7:0]  exp_temp;
wire [24:0] data1;
wire [24:0] data2;
wire [24:0] w1;
wire        n_zero;
assign exp_temp = compare? exp1 : exp2;
assign n_zero = |exp_temp;
assign data1 = compare? {n_zero, fra2, 1'b0} : {n_zero, fra1, 1'b0};
assign data2 = compare? {1'b1, fra1, 1'b0} : {1'b1, fra2, 1'b0};
assign w1 = data1 >> shift;
always @(posedge clk) begin
    op <= sign1 ^ sign2; // 0: + , 1: -
    sign <= compare? sign1 : sign2;
    exp <= compare? exp1 : exp2;
    fra_out1 <= w1;
    fra_out2 <= data2;
end
endmodule

module AFP_Add(
input               clk,
input wire [7:0]    exp,
input wire [24:0]   fra1,
input wire [24:0]   fra2,
input wire          op,
input wire          sign,

output reg [7:0]    exp_out,
output reg [25:0]   fra,
output reg          sign_out
);
wire [26:0] w1;
assign w1 = op? {2'b00, fra2} - {2'b00, fra1} : {2'b00, fra2} + {2'b00, fra1};

always @(posedge clk) begin
    exp_out <= exp;
    fra <= w1[26]? -w1 : w1;
    sign_out <= w1[26] ^ sign;
end
endmodule

module AFP_Normal(
input               clk,
input wire [7:0]    exp_in,
input wire [25:0]   fra_in,
input wire          sign_in,
output reg [4:0]    shift_left,
output reg          non_zero,
output reg [7:0]    exp,
output reg [25:0]   fra,
output reg          sign
);
wire w1;
wire [4:0] w2;
priority_encoder #(.WIDTH(25)) H1 (.in(fra_in[24:0]), .out(w2), .valid(w1));
always @(posedge clk) begin
    exp <= exp_in;
    fra <= fra_in;
    sign <= sign_in;
    shift_left <= w2;
    non_zero <= w1;
end
endmodule

module AFP_Rounding(
input               clk,
input wire [4:0]    shift_left,
input wire          non_zero,
input wire [7:0]    exp,
input wire [25:0]   fra,
input wire          sign,
output reg [31:0]    FP_out
);
wire [25:0] w1;
wire [23:0] fra_out;
wire [7:0] w2;
//assign data_out[31] = data_in[25];
assign w1 = (fra << shift_left);
assign w2 = fra[25]? exp + 1'b1 : exp - shift_left;
//assign data_out[30:23] = (non_zero | w1[24])? w2 : 8'd0;
//assign data_out[22:0] = w1[24]? w1[23:1] : w1[22:0] << shift_left;
assign fra_out = fra[25]? fra[24:1] : w1[23:0];
always @(posedge clk) begin
    FP_out[31] <= sign;
    FP_out[30:23] <= (non_zero | fra[25])? w2 : 8'd0;
    FP_out[22:0] <= fra_out[23:1];
end
endmodule


module Add_FP(
    input  wire        clk,
    input  wire [31:0] in1,
    input  wire [31:0] in2,
    output wire [31:0] data_out
);

    // =================================================================
    // 1. INTERCONNECT WIRES
    // =================================================================

    // --- Stage 1 (Compare) -> Stage 2 (Shift) ---
    wire [4:0]  w1_shift;
    wire        w1_compare;
    wire [7:0]  w1_exp1;
    wire [7:0]  w1_exp2;
    wire        w1_sign1;
    wire        w1_sign2;
    wire [22:0] w1_fra1;
    wire [22:0] w1_fra2;

    // --- Stage 2 (Shift) -> Stage 3 (Add) ---
    wire [7:0]  w2_exp;
    wire [26:0] w2_fra1; // Width 27 (24 data + 3 GRS)
    wire [26:0] w2_fra2;
    wire        w2_op;
    wire        w2_sign;

    // --- Stage 3 (Add) -> Stage 4 (Normalize) ---
    wire [7:0]  w3_exp;
    wire [27:0] w3_fra;  // Width 28 (1 Carry + 27 Data)
    wire        w3_sign;

    // --- Stage 4 (Normalize) -> Stage 5 (Rounding) ---
    wire [4:0]  w4_shift;
    wire        w4_nzero;
    wire [7:0]  w4_exp;
    wire [27:0] w4_fra;
    wire        w4_sign;

    // --- Stage 5 (Rounding) -> Output ---
    wire [31:0] w5_fp_out;

    // =================================================================
    // 2. PIPELINE STAGES
    // =================================================================

    // --- STAGE 1: Compare Exponents ---
    AFP_Compare_Exponents u_stage1 (
        .clk(clk),
        .in1(in1),
        .in2(in2),
        // Outputs
        .shift(w1_shift),
        .compare(w1_compare),
        .exp1(w1_exp1),
        .exp2(w1_exp2),
        .sign1(w1_sign1),
        .sign2(w1_sign2),
        .fra1(w1_fra1),
        .fra2(w1_fra2)
    );

    // --- STAGE 2: Alignment Shift ---
    AFP_Shift u_stage2 (
        .clk(clk),
        // Inputs
        .shift(w1_shift),
        .compare(w1_compare),
        .exp1(w1_exp1),
        .exp2(w1_exp2),
        .sign1(w1_sign1),
        .sign2(w1_sign2),
        .fra1(w1_fra1),
        .fra2(w1_fra2),
        // Outputs
        .exp(w2_exp),
        .fra_out1(w2_fra1),
        .fra_out2(w2_fra2),
        .op(w2_op),
        .sign(w2_sign)
    );

    // --- STAGE 3: Mantissa Add/Sub ---
    AFP_Add u_stage3 (
        .clk(clk),
        // Inputs
        .exp(w2_exp),
        .fra1(w2_fra1),
        .fra2(w2_fra2),
        .op(w2_op),
        .sign(w2_sign),
        // Outputs
        .exp_out(w3_exp),
        .fra(w3_fra),
        .sign_out(w3_sign)
    );

    // --- STAGE 4: Normalize Detection ---
    AFP_Normal u_stage4 (
        .clk(clk),
        // Inputs
        .exp_in(w3_exp),
        .fra_in(w3_fra),
        .sign_in(w3_sign),
        // Outputs
        .shift_left(w4_shift),
        .non_zero(w4_nzero),
        .exp(w4_exp),
        .fra(w4_fra),
        .sign(w4_sign)
    );

    // --- STAGE 5: Rounding & Packing ---
    AFP_Rounding u_stage5 (
        .clk(clk),
        // Inputs
        .shift_left(w4_shift),
        .non_zero(w4_nzero),
        .exp(w4_exp),
        .fra(w4_fra),
        .sign(w4_sign),
        // Output
        .FP_out(w5_fp_out)
    );

    // =================================================================
    // 3. FINAL OUTPUT
    // =================================================================
    assign data_out = w5_fp_out;

endmodule

module Mul24x4(
input wire [3:0] in1,
input wire [23:0] in2,
output wire [27:0] out
);
wire [23:0] off [0:3];
genvar i;

generate
    for (i = 0; i < 4; i = i+1) begin : gen_pp
        assign off[i] = in1[i]? in2 : 24'b0;
    end 
endgenerate 
assign out = {4'd0, off[0]} + {3'd0, off[1], 1'd0} + {2'd0, off[2], 2'd0} + {1'd0, off[3], 3'd0};
endmodule

module MFP_Mul(
    input  wire        clk,
    input  wire [31:0] FP_in1,
    input  wire [31:0] FP_in2,
    output reg  [47:0] fra,      // Final 48-bit Mantissa Product
    output reg  [8:0]  exp,      // Final Exponent
    output reg         sign,     // Final Sign
    output reg         non_zero  // Zero flag (1 if Result != 0)
);

    // =========================================================
    // 1. SIGNAL & REGISTER DECLARATIONS
    // =========================================================
    
    // --- Control Signal Pipeline Buffers ---
    // Propagate Exp, Sign, and Zero-flag through 5 stages
    reg [8:0] exp_buf      [0:4];
    reg       sign_buf     [0:4];
    reg       non_zero_buf [0:4];

    // --- Partial Product Accumulation Buffers ---
    // buffers grow in size as we shift and add
    reg [27:0] buf_stage1; // Result after Stage 0 (24x4)
    reg [31:0] buf_stage2; // Result after Stage 1
    reg [35:0] buf_stage3; // Result after Stage 2
    reg [39:0] buf_stage4; // Result after Stage 3
    reg [43:0] buf_stage5; // Result after Stage 4
    
    // --- Mantissa Pipeline Registers ---
    // pipe_mant1: Stores Multiplicand (A) - kept constant across stages
    reg [23:0] pipe_mant1 [0:4]; 
    
    // pipe_mant2: Stores Multiplier (B) - shifts out 4 bits per stage
    reg [19:0] pipe_mant2_s1; // Remainder after Stage 0
    reg [15:0] pipe_mant2_s2; // Remainder after Stage 1
    reg [11:0] pipe_mant2_s3; // Remainder after Stage 2
    reg [7:0]  pipe_mant2_s4; // Remainder after Stage 3
    reg [3:0]  pipe_mant2_s5; // Remainder after Stage 4

    // --- Pre-calculation Wires ---
    wire [23:0] mant1_in;   // Mantissa A with hidden bit
    wire [23:0] mant2_in;   // Mantissa B with hidden bit
    wire [8:0]  exp_cal;    // Tentative Exponent
    wire        sign_cal;   // Tentative Sign
    wire        nz_in1, nz_in2; // Input Non-Zero flags

    // --- Sub-module Outputs ---
    wire [27:0] prod [0:5]; // Outputs from 24x4 multipliers

    // =========================================================
    // 2. COMBINATIONAL INPUT LOGIC
    // =========================================================
    
    // Check if inputs are non-zero (checking all exponent bits)
    assign nz_in1 = |FP_in1[30:23]; 
    assign nz_in2 = |FP_in2[30:23];
    
    // Append Hidden Bit '1' to Mantissas
    assign mant1_in = {1'b1, FP_in1[22:0]}; 
    assign mant2_in = {1'b1, FP_in2[22:0]};
    
    // Calculate Exponent: E1 + E2 - Bias(127)
    assign exp_cal  = FP_in1[30:23] + FP_in2[30:23] - 9'd127;
    
    // Calculate Sign: XOR
    assign sign_cal = FP_in1[31] ^ FP_in2[31];

    // =========================================================
    // 3. INSTANTIATE 24x4 LOGIC MULTIPLIERS
    // =========================================================
    
    // Stage 0: Multiply A * B[3:0]
    Mul24x4 u_mul0 (.in1(mant2_in[3:0]), .in2(mant1_in), .out(prod[0]));

    // Stage 1: Multiply A * B[7:4] (using pipeline reg)
    Mul24x4 u_mul1 (.in1(pipe_mant2_s1[3:0]), .in2(pipe_mant1[0]), .out(prod[1]));

    // Stage 2: Multiply A * B[11:8]
    Mul24x4 u_mul2 (.in1(pipe_mant2_s2[3:0]), .in2(pipe_mant1[1]), .out(prod[2]));

    // Stage 3: Multiply A * B[15:12]
    Mul24x4 u_mul3 (.in1(pipe_mant2_s3[3:0]), .in2(pipe_mant1[2]), .out(prod[3]));

    // Stage 4: Multiply A * B[19:16]
    Mul24x4 u_mul4 (.in1(pipe_mant2_s4[3:0]), .in2(pipe_mant1[3]), .out(prod[4]));

    // Stage 5: Multiply A * B[23:20]
    Mul24x4 u_mul5 (.in1(pipe_mant2_s5[3:0]), .in2(pipe_mant1[4]), .out(prod[5]));

    // =========================================================
    // 4. SEQUENTIAL PIPELINE LOGIC (Accumulate & Shift)
    // =========================================================
    always @(posedge clk) begin
    
        // --- STAGE 0: Initialization ---
        // Multiplication result is non-zero ONLY if BOTH inputs are non-zero
        non_zero_buf[0] <= nz_in1 & nz_in2; 
        exp_buf[0]      <= exp_cal;
        sign_buf[0]     <= sign_cal;
        
        // Direct assignment for the first partial product
        buf_stage1      <= prod[0]; 

        // Store Mantissa A and remaining Mantissa B
        pipe_mant1[0]   <= mant1_in;
        pipe_mant2_s1   <= mant2_in[23:4]; // Shift out used 4 bits

        // --- STAGE 1: Accumulate B[7:4] ---
        non_zero_buf[1] <= non_zero_buf[0];
        exp_buf[1]      <= exp_buf[0];
        sign_buf[1]     <= sign_buf[0];

        // Algorithm: Current_Sum = (New_Product << 4) + Previous_Sum
        // {prod[1], 4'd0} acts as a 4-bit left shift
        buf_stage2      <= {prod[1] + buf_stage1[27:4], buf_stage1[3:0]};

        pipe_mant1[1]   <= pipe_mant1[0];
        pipe_mant2_s2   <= pipe_mant2_s1[19:4];

        // --- STAGE 2: Accumulate B[11:8] ---
        non_zero_buf[2] <= non_zero_buf[1];
        exp_buf[2]      <= exp_buf[1];
        sign_buf[2]     <= sign_buf[1];

        // Shift 8 bits (implicitly handled by adding to previous buffer)
        buf_stage3      <= {prod[2] + buf_stage2[31:8], buf_stage2[7:0]};

        pipe_mant1[2]   <= pipe_mant1[1];
        pipe_mant2_s3   <= pipe_mant2_s2[15:4];

        // --- STAGE 3: Accumulate B[15:12] ---
        non_zero_buf[3] <= non_zero_buf[2];
        exp_buf[3]      <= exp_buf[2];
        sign_buf[3]     <= sign_buf[2];

        buf_stage4      <= {prod[3] + buf_stage3[35:12], buf_stage3[11:0]};

        pipe_mant1[3]   <= pipe_mant1[2];
        pipe_mant2_s4   <= pipe_mant2_s3[11:4];

        // --- STAGE 4: Accumulate B[19:16] ---
        non_zero_buf[4] <= non_zero_buf[3];
        exp_buf[4]      <= exp_buf[3];
        sign_buf[4]     <= sign_buf[3];

        buf_stage5      <= {prod[4] + buf_stage4[39:16], buf_stage4[15:0]};

        pipe_mant1[4]   <= pipe_mant1[3];
        pipe_mant2_s5   <= pipe_mant2_s4[7:4]; // Only 4 bits left

        // --- STAGE 5: Final Accumulation B[23:20] ---
        non_zero        <= non_zero_buf[4];
        exp             <= exp_buf[4];
        sign            <= sign_buf[4];

        // Final addition: (Prod5 << 20) + Previous_Sum
        fra             <= {prod[5] + buf_stage5[43:20], buf_stage5[19:0]};
    end

endmodule


module MFP_Norm_Rounding(
input               clk,
input wire [47:0]   fra,
input wire [8:0]    exp,
input wire          non_zero,
input wire          sign,
output reg [31:0]   FP_out
);
wire [23:0] w1;
wire [8:0] w2;
wire [7:0] w3;
assign w1 = fra[47] ? fra[46:23] : fra[45:22];
assign w2 = exp + fra[47];
assign w3 = (!non_zero | w2[8])? 8'b0 : w2[7:0];
always @(posedge clk) begin
    FP_out[22:0] <= (w3 == 0)? 23'd0 : w1[23:1] + w1[0];
    FP_out[31] <= sign;
    FP_out[30:23] <= w3;
end
endmodule

module Mul_FP(
    input  wire        clk,
    input  wire [31:0] FP_in1,  // Input Float A
    input  wire [31:0] FP_in2,  // Input Float B
    output wire [31:0] FP_out   // Output Float Result
);

    // =========================================================
    // 1. INTERCONNECT WIRES
    // =========================================================
    // Signals to connect the Multiplier Core to the Normalizer
    
    wire [47:0] w_fra_raw;   // 48-bit Raw Product
    wire [8:0]  w_exp_raw;   // Raw Exponent
    wire        w_sign_raw;  // Sign bit
    wire        w_non_zero;  // Zero flag

    // =========================================================
    // 2. MODULE INSTANTIATIONS
    // =========================================================

    // --- Instance 1: Mantissa Multiplier Core (6-Stage Pipeline) ---
    // Calculates the 48-bit product and tentative exponent
    MFP_Mul u_core_mul (
        .clk      (clk),
        .FP_in1   (FP_in1),
        .FP_in2   (FP_in2),
        // Outputs mapped to wires
        .fra      (w_fra_raw),
        .exp      (w_exp_raw),
        .sign     (w_sign_raw),
        .non_zero (w_non_zero)
    );

    // --- Instance 2: Normalization & Rounding Unit (1 Stage) ---
    // Standardizes the result to IEEE 754 format
    MFP_Norm_Rounding u_core_norm (
        .clk      (clk),
        // Inputs from Multiplier Core
        .fra   (w_fra_raw),
        .exp   (w_exp_raw),
        .sign  (w_sign_raw),
        .non_zero (w_non_zero),
        // Final Output
        .FP_out   (FP_out)
    );

endmodule

// ============================================================
// Radix-4 Divider Combinational Stage
// q_digit = floor((rem_in << 2) / divisor)
// Implemented by compare-subtract: 2D, 1D
// ============================================================

module radix4_div_stage #(
    parameter W = 32
)(
    input  wire [W-1:0] rem_in,
    input  wire [W-1:0] divisor,
    output reg  [1:0]   q_digit,
    output reg  [W-1:0] rem_out
);

    reg [W-1:0] r;

    always @(*) begin
        r       = rem_in << 2;
        q_digit = 2'b00;

        if (r >= (divisor << 1)) begin
            r = r - (divisor << 1);
            q_digit[1] = 1'b1;
        end

        if (r >= divisor) begin
            r = r - divisor;
            q_digit[0] = 1'b1;
        end

        rem_out = r;
    end

endmodule


// ============================================================
// Input Pipeline Register Stage
// Sequential block
// ============================================================

module divfp_input_stage #(
    parameter W = 32
)(
    input  wire clk,

    input  wire [W-1:0] rem_in,
    input  wire [W-1:0] div_in,
    input  wire [27:0]  quot_in,
    input  wire signed [10:0] exp_in,
    input  wire sign_in,
    input  wire zero_in,
    input  wire div_by_zero_in,
    input  wire nan_in,

    output reg [W-1:0] rem_out,
    output reg [W-1:0] div_out,
    output reg [27:0]  quot_out,
    output reg signed [10:0] exp_out,
    output reg sign_out,
    output reg zero_out,
    output reg div_by_zero_out,
    output reg nan_out
);

    always @(posedge clk) begin
        rem_out         <= rem_in;
        div_out         <= div_in;
        quot_out        <= quot_in;
        exp_out         <= exp_in;
        sign_out        <= sign_in;
        zero_out        <= zero_in;
        div_by_zero_out <= div_by_zero_in;
        nan_out         <= nan_in;
    end

endmodule


// ============================================================
// One Registered Radix-4 Pipeline Stage
// Sequential block: only non-blocking assignments
// ============================================================

module divfp_radix4_pipe_stage #(
    parameter W = 32
)(
    input  wire clk,

    input  wire [W-1:0] rem_in,
    input  wire [W-1:0] div_in,
    input  wire [27:0]  quot_in,
    input  wire signed [10:0] exp_in,
    input  wire sign_in,
    input  wire zero_in,
    input  wire div_by_zero_in,
    input  wire nan_in,

    output reg [W-1:0] rem_out,
    output reg [W-1:0] div_out,
    output reg [27:0]  quot_out,
    output reg signed [10:0] exp_out,
    output reg sign_out,
    output reg zero_out,
    output reg div_by_zero_out,
    output reg nan_out
);

    wire [1:0]   q_digit;
    wire [W-1:0] rem_next;

    radix4_div_stage #(.W(W)) u_radix4_comb (
        .rem_in   (rem_in),
        .divisor  (div_in),
        .q_digit  (q_digit),
        .rem_out  (rem_next)
    );

    always @(posedge clk) begin
        rem_out         <= rem_next;
        div_out         <= div_in;
        quot_out        <= {quot_in[25:0], q_digit};

        exp_out         <= exp_in;
        sign_out        <= sign_in;
        zero_out        <= zero_in;
        div_by_zero_out <= div_by_zero_in;
        nan_out         <= nan_in;
    end

endmodule


// ============================================================
// Rounding + Pack Combinational Block
// Round to nearest, ties to even
// ============================================================

module divfp_round_pack #(
    parameter W = 32
)(
    input  wire [W-1:0] rem_in,
    input  wire [27:0]  quot_in,
    input  wire signed [10:0] exp_in,
    input  wire sign_in,
    input  wire zero_in,
    input  wire div_by_zero_in,
    input  wire nan_in,

    output reg  [31:0] FP_result
);

    wire [28:0] q_full;
    wire [23:0] mant_pre_round;
    wire        guard_bit;
    wire        round_bit;
    wire        sticky_bit;
    wire        round_inc;

    wire [24:0] mant_rounded;
    wire signed [10:0] exp_after_round;
    wire [23:0] mant_final;
    wire [7:0]  exp_final;

    assign q_full = {1'b1, quot_in};

    assign mant_pre_round = q_full[28:5];

    assign guard_bit  = q_full[4];
    assign round_bit  = q_full[3];
    assign sticky_bit = |q_full[2:0] | (|rem_in);

    assign round_inc = guard_bit & (round_bit | sticky_bit | mant_pre_round[0]);

    assign mant_rounded = {1'b0, mant_pre_round} + round_inc;

    assign exp_after_round =
        mant_rounded[24] ? (exp_in + 11'sd1) : exp_in;

    assign mant_final =
        mant_rounded[24] ? mant_rounded[24:1] : mant_rounded[23:0];

    assign exp_final =
        (exp_after_round <= 0)   ? 8'd0  :
        (exp_after_round >= 255) ? 8'hFF :
                                   exp_after_round[7:0];

    always @(*) begin
        if (nan_in) begin
            FP_result = 32'h7FC00000;
        end else if (div_by_zero_in) begin
            FP_result = {sign_in, 8'hFF, 23'd0};
        end else if (zero_in || (exp_final == 8'd0)) begin
            FP_result = {sign_in, 8'd0, 23'd0};
        end else if (exp_final == 8'hFF) begin
            FP_result = {sign_in, 8'hFF, 23'd0};
        end else begin
            FP_result = {sign_in, exp_final, mant_final[22:0]};
        end
    end

endmodule


// ============================================================
// Top FP32 Divider
// Radix-4 version
//
// 14 radix-4 stages generate 28 quotient bits.
// Total quotient bits = 28 bits.
//
// Latency:
// input register stage  : 1 cycle
// radix-4 stages        : 14 cycles
// output register stage : 1 cycle
// Total latency         : 16 cycles
//
// Throughput: 1 input / cycle
// ============================================================

module Div_FP #(
    parameter W = 32
)(
    input  wire        clk,
    input  wire [31:0] FP_in1,
    input  wire [31:0] FP_in2,
    output reg  [31:0] FP_out
);

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam RADIX4_STAGES = 14;
    localparam TOTAL_STAGES  = 14;

    // ------------------------------------------------------------
    // Preprocess wires/registers
    // ------------------------------------------------------------
    reg [W-1:0] pre_rem;
    reg [W-1:0] pre_div;
    reg [27:0]  pre_quot;
    reg signed [10:0] pre_exp;
    reg pre_sign;
    reg pre_zero;
    reg pre_div_by_zero;
    reg pre_nan;

    wire        sign_a = FP_in1[31];
    wire        sign_b = FP_in2[31];

    wire [7:0]  exp_a  = FP_in1[30:23];
    wire [7:0]  exp_b  = FP_in2[30:23];

    wire [22:0] frac_a = FP_in1[22:0];
    wire [22:0] frac_b = FP_in2[22:0];

    wire a_zero = (exp_a == 8'd0) && (frac_a == 23'd0);
    wire b_zero = (exp_b == 8'd0) && (frac_b == 23'd0);

    wire a_special = (exp_a == 8'hFF);
    wire b_special = (exp_b == 8'hFF);

    wire [23:0] mant_a = {1'b1, frac_a};
    wire [23:0] mant_b = {1'b1, frac_b};

    reg [24:0] dividend_mant;
    reg [24:0] divisor_mant;

    always @(*) begin
        pre_sign        = sign_a ^ sign_b;
        pre_zero        = (a_zero & ~b_zero) | b_special;
        pre_div_by_zero = b_zero & ~a_zero;
        pre_nan         = (a_zero & b_zero) | a_special;

        divisor_mant = {1'b0, mant_b};

        if (mant_a < mant_b) begin
            dividend_mant = {mant_a, 1'b0};   // 25-bit: mant_a << 1
            pre_exp = $signed({3'b000, exp_a}) - $signed({3'b000, exp_b}) + 11'sd126;
        end else begin
            dividend_mant = {1'b0, mant_a};
            pre_exp = $signed({3'b000, exp_a}) - $signed({3'b000, exp_b}) + 11'sd127;
        end

        pre_div   = {{(W-25){1'b0}}, divisor_mant};

        pre_rem   = {{(W-25){1'b0}}, dividend_mant}
                  - {{(W-25){1'b0}}, divisor_mant};

        pre_quot  = 28'd0;
    end

    // ------------------------------------------------------------
    // Pipeline buses
    // stage 0 = registered preprocess output
    // stage 1..14 = radix-4 stages
    // ------------------------------------------------------------
    wire [W-1:0] rem_s [0:TOTAL_STAGES];
    wire [W-1:0] div_s [0:TOTAL_STAGES];
    wire [27:0]  quot_s[0:TOTAL_STAGES];

    wire signed [10:0] exp_s [0:TOTAL_STAGES];
    wire sign_s[0:TOTAL_STAGES];

    wire zero_s[0:TOTAL_STAGES];
    wire div_by_zero_s[0:TOTAL_STAGES];
    wire nan_s[0:TOTAL_STAGES];

    divfp_input_stage #(.W(W)) u_input_stage (
        .clk            (clk),

        .rem_in         (pre_rem),
        .div_in         (pre_div),
        .quot_in        (pre_quot),
        .exp_in         (pre_exp),
        .sign_in        (pre_sign),
        .zero_in        (pre_zero),
        .div_by_zero_in (pre_div_by_zero),
        .nan_in         (pre_nan),

        .rem_out        (rem_s[0]),
        .div_out        (div_s[0]),
        .quot_out       (quot_s[0]),
        .exp_out        (exp_s[0]),
        .sign_out       (sign_s[0]),
        .zero_out       (zero_s[0]),
        .div_by_zero_out(div_by_zero_s[0]),
        .nan_out        (nan_s[0])
    );

    // ------------------------------------------------------------
    // Radix-4 pipeline stages
    // Each stage generates 2 quotient bits
    // ------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < RADIX4_STAGES; gi = gi + 1) begin : gen_radix_pipe
            divfp_radix4_pipe_stage #(.W(W)) u_radix_pipe (
                .clk            (clk),

                .rem_in         (rem_s[gi]),
                .div_in         (div_s[gi]),
                .quot_in        (quot_s[gi]),
                .exp_in         (exp_s[gi]),
                .sign_in        (sign_s[gi]),
                .zero_in        (zero_s[gi]),
                .div_by_zero_in (div_by_zero_s[gi]),
                .nan_in         (nan_s[gi]),

                .rem_out        (rem_s[gi+1]),
                .div_out        (div_s[gi+1]),
                .quot_out       (quot_s[gi+1]),
                .exp_out        (exp_s[gi+1]),
                .sign_out       (sign_s[gi+1]),
                .zero_out       (zero_s[gi+1]),
                .div_by_zero_out(div_by_zero_s[gi+1]),
                .nan_out        (nan_s[gi+1])
            );
        end
    endgenerate

    // ------------------------------------------------------------
    // Rounding + packing
    // ------------------------------------------------------------
    wire [31:0] rounded_result;

    divfp_round_pack #(.W(W)) u_round_pack (
        .rem_in        (rem_s[TOTAL_STAGES]),
        .quot_in       (quot_s[TOTAL_STAGES]),
        .exp_in        (exp_s[TOTAL_STAGES]),
        .sign_in       (sign_s[TOTAL_STAGES]),
        .zero_in       (zero_s[TOTAL_STAGES]),
        .div_by_zero_in(div_by_zero_s[TOTAL_STAGES]),
        .nan_in        (nan_s[TOTAL_STAGES]),
        .FP_result     (rounded_result)
    );

    // ------------------------------------------------------------
    // Output register stage
    // ------------------------------------------------------------
    always @(posedge clk) begin
        FP_out <= rounded_result;
    end

endmodule



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