`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/26/2026 07:16:43 AM
// Design Name: 
// Module Name: SPI_Slave
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

// Transfer MSB first
module Parallel_to_serial #(
    parameter n = 8 
)(
    input wire [n-1:0] data_in,
    input wire load,
    input wire clk,
    input wire ena,
    
    output wire data_out
);
   reg [n-1:0] buffer;
   integer i;
   // this case can use tri-state
   //assign data_out = ena? buffer[0]: 1'b0;
   assign data_out = buffer[0];
   // main block par2ser
   // characteristic: catch posedge trigger of load -> load data from input to buffer
   always @(posedge clk or posedge load) begin
        if (load == 1) begin
            for(i = n-1; i >= 0; i = i-1) begin
                buffer[i] <= data_in[i];
            end
        end
        else begin
            buffer[n-1] <= 1'b0;
            for(i = n-1; i > 0; i = i-1) begin
                buffer[i-1] <= buffer[i];
            end
        end
   end
   
endmodule

module serial_to_parallel #(
    parameter n = 8
)(
    input wire data_in,
    input wire clk,
    input wire ena,
    
    output wire [n-1:0] data_out
);
    reg [n-1:0] buffer;
    integer i;
    
    genvar j;
    generate 
        for(j = n-1; j >=0; j = j-1) begin : bit_assign
            assign data_out[j] = buffer[j];
        end
    endgenerate 
    
    always @(posedge clk) begin
        if (ena) begin
            buffer[n-1] <= data_in;
            for (i = n-1; i > 0; i = i-1) begin
                buffer[i-1] <= buffer[i];
            end
        end
    end
endmodule

module crc5 (
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    input  wire       serial_in,
    
    output reg  [4:0] crc_out,
    output wire check_feedback
);

    wire feedback;

// fix this bug
    assign feedback = serial_in ^ crc_out[4];
    assign check_feedback = feedback;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            crc_out <= 5'b00000;
        end 
        else if (enable) begin
            crc_out[0] <= feedback;
            crc_out[1] <= crc_out[0];
            crc_out[2] <= crc_out[1] ^ feedback;
            crc_out[3] <= crc_out[2];
            crc_out[4] <= crc_out[3];
        end
    end

endmodule

module crc5_checker (
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    input  wire       serial_in,
    
    output wire       data_valid,
    output wire       check_feedback
);

    wire [4:0] current_crc;

    crc5 u_crc5 (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .serial_in(serial_in),
        .crc_out(current_crc),
        .check_feedback(check_feedback)
    );

    assign data_valid = ~(|current_crc);

endmodule


//  state machine: active cs -> idle state -> transmission state if master generate multiple of 8 cycles -> idle state -> deactivate cs

// Một số điểm lưu ý của submodule
// Chuẩn thì sẽ có xung clk hệ thống riêng của sensor chứa submodule này để đồng bộ tín hiệu load
// -> Nhưng nếu lấy thêm clk system thì clk system nó cần xác định là liệu nó sẽ lm nhanh hay lm chậm hơn clk từ master
module SPI_Slave#(
    parameter n = 8,
    parameter cnum = $clog2(n),
    parameter CPOL = 0,
    parameter CPAH = 0,
    parameter CLK_CTRL = CPOL ^ CPAH 
)(  
    input wire n_rst,
    input wire [n-1:0] data_in,
    input wire load,
    input wire sclk,
    input wire MOSI,
    input wire n_cs,
    
    output wire [n-1:0] data_out,
    output wire MISO,
    output reg ready
);  
    reg [cnum-1:0] counter;
    wire inter_clk;
    
    assign inter_clk = sclk ^ CLK_CTRL; // generate internal clock to serve CPHA and CPOL
    
    serial_to_parallel MOSI_Block(.data_in(MOSI), .clk(inter_clk), .ena(~n_cs), .data_out(data_out));
    Parallel_to_serial MISO_Block(.data_in(data_in), .load(load), .clk(inter_clk), .ena(~n_cs), .data_out(MISO));
    
// the operation of slave
    // when transmission is happening -> counter will increase by 1 (counter != 0 -> transmission).
    always @(posedge inter_clk or negedge n_rst ) begin
        if (n_rst == 0) begin
            counter <= 0;
        end
        else begin
            counter <= counter + 1;
        end
    end
    
    
    // combination to check ready by checking the value of counter. 
    always @(*) begin
        if (counter) begin
            ready = 0;
        end
        else begin
            ready = 1;
        end
    end

endmodule




// The behavior of module 
// To start must n_reset this module to initial the system (start checker and counter)
// when having error transmission -> must n_reset this module to reset checker (can using firmware to drive n_reset).

module SPI_Slave_CRC #(
    parameter n = 8,
    parameter crc_len = 5,
    parameter total_len = n + crc_len, 
    parameter cnum = 4,               
    parameter CPOL = 0,
    parameter CPHA = 0,
    parameter CLK_CTRL = CPOL ^ CPHA 
)(  
    input wire n_rst,      
    input wire [n-1:0] data_in,
    input wire load,        
    input wire sclk,
    input wire MOSI,
    input wire n_cs,        
    
    output wire [n-1:0] data_out,
    output wire MISO,
    output wire rx_data_valid, 
    output wire rx_done,
    output wire [crc_len-1:0] crc_out,  
    output reg ready,
    
    // checker 
    output wire [3:0] ccounter,  
    output wire csclk,  
    output wire check_feedback             
);  

    reg [cnum-1:0] counter;
    wire inter_clk;
    
    assign inter_clk = sclk ^ CLK_CTRL; 
    assign csclk = sclk;
    
    //INSTANTIATE CÁC KHỐI DỊCH DATA (Chỉ chạy 8 nhịp đầu)
    wire tx_miso_data; 
    wire shift_ena = (~n_cs) && (counter < n); 
    
    serial_to_parallel #(n) MOSI_Block (
        .data_in(MOSI), 
        .clk(inter_clk), 
        .ena(shift_ena), 
        .data_out(data_out)
    );
    
    Parallel_to_serial #(n) MISO_Block (
        .data_in(data_in), 
        .load(load), 
        .clk(inter_clk), 
        .ena(shift_ena), 
        .data_out(tx_miso_data)
    );
    
    // B. INSTANTIATE CÁC KHỐI CRC
    wire [crc_len-1:0] tx_crc_out;
    
    // reset when deactivate n_cs or counter reach 13 to reset for the new CRC frame
    crc5 tx_crc_calc (
        .clk(inter_clk),
        .reset(~n_rst | load),      
        .enable(shift_ena), 
        .serial_in(tx_miso_data), 
        .crc_out(tx_crc_out)
    );

    crc5_checker rx_crc_check (
        .clk(inter_clk),
        .reset(~n_rst),    
        .enable(~n_cs),   
        .serial_in(MOSI),
        .data_valid(rx_data_valid),
        .check_feedback(check_feedback)
    );

    // C. MẠCH MUX MISO VÀ ĐIỀU KHIỂN LOGIC

    assign MISO = (n_cs) ? 1'bz : 
                  ((counter < n || counter == 13) ? tx_miso_data : 
                  tx_crc_out[(total_len - 1) - counter]);
    assign crc_out = tx_crc_out;
    assign ccounter = counter;

    always @(posedge inter_clk or negedge n_rst or posedge n_cs) begin
        if (!n_rst) begin
            counter <= 0;
        end 
        else if (n_cs == 1'b1) begin 
            counter <= 0; 
        end
        else begin
            if (counter < 13) begin
                counter <= counter + 1;
            end
            else begin 
                counter <= 1;
            end
        end
    end
    
    // Báo trạng thái Ready
    always @(*) begin
        if (counter > 0 && counter < total_len) ready = 0;
        else ready = 1;
    end

    assign rx_done = (counter == total_len) ? 1'b1 : 1'b0;

endmodule