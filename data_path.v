`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/31/2026 02:59:21 PM
// Design Name: 
// Module Name: data_path
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Ring_Flasher_EX #(
    parameter ClockSpeed   = 5000, //Hz
    parameter NumLed       = 16,
    parameter NumCW        = 12,
    parameter NumACW       = 8,
    parameter TimeStep     = 500 //ms
)(
    input wire                          clk,
    input wire                          reset,
    input wire                          rep,
    output wire [NumLed-1:0]    LedOut
);
reg [2:0] Level_LED [0:NumLed-1];
wire [2:0] n_Level_LED [0:NumLed-1];
wire [$clog2(NumLed):0] cur;
wire [NumLed-1:0] off_led;
wire off_all_led;
wire ena_div;
wire divclk;

genvar i;
generate
    for (i = 0; i < NumLed; i = i + 1) begin
        wire [2:0] t;
        assign t = (Level_LED[i] == 0)? 0 : Level_LED[i] - 1;
        assign n_Level_LED[i] = (cur == i)? 5 : t;
        PWM P(.clk(clk), .level(Level_LED[i]), .ledout(LedOut[i]), .reset(reset));
        assign off_led[i] = !Level_LED[i];
    end
endgenerate
integer j;
integer k;
always @(posedge divclk or posedge reset) begin
    if(reset) begin
        for (j = 0; j < NumLed; j = j + 1) begin
            Level_LED[j] <= 0;
        end
    end else begin
        for (k = 0; k < NumLed; k = k + 1) begin
            Level_LED[k] <= n_Level_LED[k];
        end
    end
end
assign off_all_led = &off_led;
Control #(.NumLed(NumLed), .NumCW(NumCW), .NumACW(NumACW)) C(.cur(cur), .ena_div(ena_div), .clk(clk), .divclk(divclk), .rep(rep), .rst(reset), .off_all(off_all_led));
clock_divider_module #(.CLK_FREQ_HZ(ClockSpeed), .STEP_TIME_S(TimeStep/1000.0)) CDM(.clk(clk), .rst_n(~reset), .enable_timer(ena_div), .step_tick(divclk));
endmodule



module PWM(
    input wire clk,          // Xung nhịp hệ thống (5kHz)
    input wire [2:0] level,  // Mức độ sáng từ 0 đến 5 (Cần 3-bit để biểu diễn số 5)
    input wire reset,        // Tín hiệu reset để khởi động lại bộ đếm
    output reg ledout        // Tín hiệu băm xung ngõ ra cấp cho LED
);

    // Thanh ghi đếm chu kỳ PWM (cần 3-bit để đếm từ 0 đến 4)
    reg [2:0] pwm_cnt;
    // Khối cập nhật bộ đếm PWM
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pwm_cnt <= 3'd0;
        end else if (pwm_cnt >= 3'd4) begin
            pwm_cnt <= 3'd0; // Reset bộ đếm khi đạt đỉnh chu kỳ
        end else begin
                pwm_cnt <= pwm_cnt + 1'b1;
            end
    end

    // Khối so sánh để tạo Duty Cycle
    always @(posedge clk) begin
            // Tránh lỗi glitch ngõ ra do level[2:0] nhận giá trị ngoài vùng 0-5
            if (level > 3'd5) begin
                ledout <= 1'b1; // Ép về 100% nếu giá trị nhập vào bị sai (VD: 6, 7)
            end else if (pwm_cnt < level) begin
                ledout <= 1'b1;
            end else begin
                ledout <= 1'b0;
            end
    end

endmodule

module Control#(
    // Number of led will be cavias of 2
    parameter NumLed = 16,
    parameter NumCW = 12,
    parameter NumACW =8,
    parameter IDLE_STATE = 0,
    parameter CW_STATE = 1,
    parameter ACW_STATE = 2,
    parameter OFF_STATE =3
)(cur, ena_div, clk, divclk, rep, rst, off_all);
    output [$clog2(NumLed):0] cur;
    output reg ena_div;
    input clk;
    input divclk;
    input rep;
    input rst;
    input off_all;
    
    reg [1:0] State;
    reg [1:0] NextState;
    reg [$clog2(NumCW+NumACW):0] Counter;
    reg [$clog2(NumCW+NumACW):0] NextCounter;
    reg [$clog2(NumLed):0] cur_pos;
    reg [$clog2(NumLed):0] next_pos;
    
    assign cur = cur_pos;
    
    // Chô này cần check lại xem còn cách nào hay hơn không
    always @(posedge clk) begin
        if ((rep == 0) && (State == IDLE_STATE)) begin
            ena_div <= 0;
        end
        else begin
            ena_div <= 1;
        end
    end
    
    always @(posedge divclk or posedge rst) begin
        if (rst == 1) begin
            State <= IDLE_STATE;
            Counter <= -1;
            cur_pos <= -1;
        end
        else begin
            State <= NextState;
            Counter <= NextCounter;
            cur_pos <= next_pos;
        end
    end
    
    always @(*) begin
    // default value
        NextState  = State;
        NextCounter = Counter;
        next_pos   = cur_pos;
    
        case (State) 
            IDLE_STATE: begin
                if (rep == 1) begin
                    NextState = CW_STATE;
                    NextCounter = 0;
                    next_pos = 0;
                end
                else begin
                    NextState = IDLE_STATE;
                end
            end
            CW_STATE: begin                     
                if(Counter == NumCW - 1) begin
                    NextState = ACW_STATE;
                    NextCounter = NextCounter + 1'b1;
                    next_pos[$clog2(NumLed)] = 0;
                    next_pos[$clog2(NumLed)-1:0] = next_pos[$clog2(NumLed)-1:0] - 1'b1;
                end
                else begin 
                    NextState = CW_STATE;
                    NextCounter = NextCounter + 1'b1;
                    next_pos[$clog2(NumLed)] = 0;
                    next_pos[$clog2(NumLed)-1:0] = next_pos[$clog2(NumLed)-1:0] + 1'b1;
                end
            end
            ACW_STATE: begin                     
                if(Counter == NumCW + NumACW - 1) begin
                    if(rep == 1) begin
                        NextState = CW_STATE;
                        NextCounter = 0;
                        next_pos[$clog2(NumLed)] = 0;
                        next_pos[$clog2(NumLed)-1:0] = next_pos[$clog2(NumLed)-1:0] + 1'b1;
                    end
                    else begin 
                        NextState = OFF_STATE;
                        next_pos = -1;
                        NextCounter = 0;
                    end
                end
                else begin 
                    NextState = ACW_STATE;
                    NextCounter = NextCounter + 1'b1;
                    next_pos[$clog2(NumLed)] = 0;
                    next_pos[$clog2(NumLed)-1:0] = next_pos[$clog2(NumLed)-1:0] - 1'b1;
                end
            end
            OFF_STATE: begin
                next_pos = -1;
                if (off_all == 1) begin
                    NextState = IDLE_STATE;
                end
                else begin
                    NextState = OFF_STATE;
                end
            end
        endcase
    end
    
endmodule

module clock_divider_module #(
    parameter CLK_FREQ_HZ = 5000,
    parameter STEP_TIME_S = 0.5
)(
    input  wire clk,
    input  wire rst_n,     
    input  wire enable_timer, 
    output reg  step_tick    
);

    localparam MAX_COUNT = $rtoi((CLK_FREQ_HZ * STEP_TIME_S) + 0.5);
    localparam COUNT_WIDTH = $clog2(MAX_COUNT);

    reg [COUNT_WIDTH-1:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= MAX_COUNT - 1;
            step_tick <= 1'b0;
        end else begin
            if (enable_timer) begin
                if (counter == MAX_COUNT - 1) begin
                    counter   <= 0;
                    step_tick <= 1'b1; 
                end else begin
                    counter   <= counter + 1;
                    step_tick <= 1'b0;
                end
            end else begin
                counter <= MAX_COUNT - 1;
                step_tick <= 1'b0;
            end
        end
    end

endmodule