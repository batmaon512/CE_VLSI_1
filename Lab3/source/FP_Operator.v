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
