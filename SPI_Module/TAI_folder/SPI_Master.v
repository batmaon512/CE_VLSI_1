module Buf_P2S #(
    parameter N = 8
)(
    input wire [N-1:0] Input,
    input wire load,
    input wire clk,
    input wire ena,
    output wire Output,
    output wire [N-1:0] Buffer
);

reg [N-1:0] buffer ;
integer i;
generate
    always @(posedge clk or posedge load) begin
        if (load) begin
            buffer <= Input;
        end
        else if (ena) begin
            buffer[N-1] <= 0; // flush buffer
            for (i = N-1; i > 0; i = i-1) begin
                buffer[i-1] <= buffer[i];
            end
        end
    end
endgenerate

assign Output = buffer[0];
assign Buffer = buffer;
endmodule

module Buf_S2P #(
    parameter N = 8
)(
    input wire Input,
    input wire clk,
    input wire ena,
    output wire [N-1:0] Output
);
reg [N-1:0] buffer;
integer i;
generate
    always @(posedge clk) begin
        if (ena) begin
            buffer[N-1] <= Input;
            for (i = N-1; i > 0; i = i-1) begin
                buffer[i-1] <= buffer[i];
            end
        end
    end
endgenerate
assign Output = buffer;
endmodule

module SPI_Master_CRC #(
    parameter Frame_Size = 8,
    parameter Number_Slave = 8,
    parameter CPOL = 0,
    parameter CPAH = 0
)(
    input wire [Frame_Size-1:0]     INPUT,
    input wire [1:0]                CNTL,
    input wire                      REFCLK,
    input wire                      MISO,
    
    output wire [Frame_Size-1:0]    OUTPUT,
    output reg                     SCLK,
    output reg                     MOSI,
    output reg [Number_Slave-1:0]  SS,
    output reg                     READY,
    output wire [Frame_Size-1:0] buf_input,
    //optional
    output reg                     VALID
   
);
    localparam CLK_CTRL = CPOL ^ CPAH;
    localparam SIZE_FRAME = $clog2(Frame_Size + 5);
    reg M_load;
    reg M_ena;
    reg S_ena;
    reg C_ena;
    wire out_buf_P2S;
    reg reset_crc;
    reg reset_crc_checker;
    wire t_valid;
//    wire [Frame_Size-1:0] buf_input;
    wire [4:0] crc_out;
    reg [SIZE_FRAME-1:0] count;
    
    Buf_P2S #(
        .N(Frame_Size)
    ) u_buf_P2S (
        .Input(INPUT),
        .load(M_load),
        .clk(~SCLK),
        .ena(M_ena),
        .Output(out_buf_P2S),
        .Buffer(buf_input)
    );

    Buf_S2P #(
        .N(Frame_Size)
    ) u_buf_S2P (
        .Input(MISO),
        .clk(SCLK),
        .ena(S_ena),
        .Output(OUTPUT)
    );

    crc5 u_crc5 (
        .clk(SCLK),
        .reset(reset_crc),
        .enable(S_ena),
        .serial_in(out_buf_P2S),
        .crc_out(crc_out)
    );

    crc5_checker u_crc5_checker (
        .clk(SCLK),
        .reset(reset_crc_checker),
        .enable(M_ena),
        .serial_in(MISO),
        .data_valid(t_valid)
    );
localparam IDLE = 0, LOAD = 1, TRANSFER = 2, COMPLETE = 3;
reg [1:0] state = IDLE;
reg [1:0] next_state;

always @(posedge REFCLK) begin
    state <= next_state;
    case (state)
        IDLE: begin
            count <= 0;
            SS <= (CNTL == 2)? (INPUT < Number_Slave) ? {Number_Slave{1'b1}} & ~(1 << INPUT[$clog2(Number_Slave)-1:0]) : {Number_Slave{1'b1}} : SS;
        end
        TRANSFER: begin
            if(count < Frame_Size + 4) begin
                count <= count + 1;
            end
        end
        COMPLETE: begin
            count <= 0;
        end
    endcase
end

// fix M_ena and S_ena in IDLE State
// add C_ena used for checker
always @(*) begin
    case (state)
        IDLE: begin
            READY <= 1'b1;
            VALID <= 1'b1;
            M_load <= (CNTL == 1);
            M_ena <= (CNTL == 3)? 1 : 0;
            S_ena <= (CNTL == 3)? 1 : 0;
            C_ena <= (CNTL == 3)? 1 : 0;
            reset_crc <= (CNTL == 3)? 0 : 1;
            reset_crc_checker <= (CNTL == 3)? 0 : 1;
            MOSI <= out_buf_P2S;
            SCLK <= 0;
            next_state <= (CNTL == 3)? TRANSFER : IDLE;
        end
        TRANSFER: begin
            READY <= 1'b0;
            VALID <= (count == Frame_Size + 4)? t_valid : 1'b1;
            M_load <= 0;
            M_ena <= 1;
            S_ena <= count < Frame_Size - 1;
//            C_ena <= count <= Frame_Size + 4;
            reset_crc <= 1'b0;
            reset_crc_checker <= 1'b0;
            MOSI <= (count < Frame_Size - 1) ? out_buf_P2S : crc_out[Frame_Size + 4 - count - 1];
            SCLK <= (count == Frame_Size + 4)? 1: REFCLK;
            next_state <= (count == Frame_Size + 4)? ((CNTL == 3)? COMPLETE : IDLE) : TRANSFER;
        end
        COMPLETE: begin
            READY <= 1'b0;
            VALID <= 1'b1;
            M_load <= 0;
            M_ena <= 0;
            S_ena <= 0;
            reset_crc <= 1'b1;
            reset_crc_checker <= 1'b1;
            MOSI <= 1'b1;
            SCLK <= 0;
            next_state <= (CNTL == 3)? COMPLETE : IDLE;
        end
        default: begin
            READY <= 1'b0;
            VALID <= 1'b0;
            M_load <= 0;
            M_ena <= 0;
            S_ena <= 0;
            reset_crc <= 1'b1;
            reset_crc_checker <= 1'b1;
            MOSI <= 1'b1;
            SCLK <= 0;
            next_state <= IDLE;
        end
    endcase


end


endmodule
