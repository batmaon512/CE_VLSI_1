`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/20/2026 08:30:09 PM
// Design Name: 
// Module Name: SPI_Top
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

module SPI_Top #(
	parameter FRAME_SIZE = 8
)(
	input wire REFCLK,
	input wire [FRAME_SIZE-1:0] MASTER_INPUT,
	input wire [1:0] MASTER_CNTL,

	// Slave 0 external interface
	input wire n_rst0,
	input wire [FRAME_SIZE-1:0] SLAVE0_DATA_IN,
	input wire SLAVE0_LOAD,
	output wire [FRAME_SIZE-1:0] SLAVE0_DATA_OUT,
	output wire SLAVE0_RX_DONE,

	// Slave 1 external interface
	input wire n_rst1,
	input wire [FRAME_SIZE-1:0] SLAVE1_DATA_IN,
	input wire SLAVE1_LOAD,
	output wire [FRAME_SIZE-1:0] SLAVE1_DATA_OUT,
	output wire SLAVE1_RX_DONE,

	// Master status / outputs
	output wire [FRAME_SIZE-1:0] MASTER_OUTPUT,
	output wire MASTER_READY,
	output wire MASTER_VALID,
	output wire [1:0] SS
);

wire SCLK;
wire MOSI;
wire MISO_LINE; // shared MISO bus (tri-state from slaves)
wire [FRAME_SIZE-1:0] BUF_INPUT;

// Instantiate SPI master (2 slaves)
SPI_Master_CRC #(
	.Frame_Size(FRAME_SIZE),
	.Number_Slave(2),
	.CPOL(0),
	.CPAH(0)
) u_master (
	.INPUT(MASTER_INPUT),
	.CNTL(MASTER_CNTL),
	.REFCLK(REFCLK),
	.MISO(MISO_LINE),
	.OUTPUT(MASTER_OUTPUT),
	.SCLK(SCLK),
	.MOSI(MOSI),
	.SS(SS),
	.READY(MASTER_READY),
	.buf_input(BUF_INPUT),
	.VALID(MASTER_VALID)
);

// Slave 0
SPI_Slave_CRC #(
	.n(FRAME_SIZE),
	.crc_len(5),
	.total_len(FRAME_SIZE+5),
	.cnum(4),
	.CPOL(0),
	.CPHA(0)
) u_slave0 (
	.n_rst(n_rst0),
	.data_in(SLAVE0_DATA_IN),
	.load(SLAVE0_LOAD),
	.sclk(SCLK),
	.MOSI(MOSI),
	.n_cs(SS[0]),
	.data_out(SLAVE0_DATA_OUT),
	.MISO(MISO_LINE),
	.rx_data_valid(),
	.rx_done(SLAVE0_RX_DONE),
	.crc_out(),
	.ready()
);

// Slave 1
SPI_Slave_CRC #(
	.n(FRAME_SIZE),
	.crc_len(5),
	.total_len(FRAME_SIZE+5),
	.cnum(4),
	.CPOL(0),
	.CPHA(0)
) u_slave1 (
	.n_rst(n_rst1),
	.data_in(SLAVE1_DATA_IN),
	.load(SLAVE1_LOAD),
	.sclk(SCLK),
	.MOSI(MOSI),
	.n_cs(SS[1]),
	.data_out(SLAVE1_DATA_OUT),
	.MISO(MISO_LINE),
	.rx_data_valid(),
	.rx_done(SLAVE1_RX_DONE),
	.crc_out(),
	.ready()
);

endmodule
