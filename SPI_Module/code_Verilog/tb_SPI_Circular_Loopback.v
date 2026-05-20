`timescale 1ns/1ps

module tb_SPI_Circular_Loopback();

    localparam FRAME_SIZE   = 8;
    localparam NUMBER_SLAVE = 8;

    // 13 bit = 8 data + 5 CRC
    localparam TOTAL_BITS   = 13;

    reg clk;

    // =========================
    // Master important signals
    // =========================
    reg  [FRAME_SIZE-1:0] master_input;
    reg  [1:0]            master_cntl;
    wire [FRAME_SIZE-1:0] master_output;
    wire                  master_sclk;
    wire                  MOSI;
    wire                  MISO;
    wire [NUMBER_SLAVE-1:0] master_ss;
    wire                  master_ready;
    wire                  master_valid;

    // =========================
    // Slave important signals
    // =========================
    reg                   slave_n_rst;
    reg  [FRAME_SIZE-1:0] slave_input;
    reg                   slave_load;
    wire [FRAME_SIZE-1:0] slave_output;
    wire                  slave_valid;
    wire                  slave_ready;

    // =========================
    // External loopback buffers
    // =========================
    reg [FRAME_SIZE-1:0] master_rx_buffer;
    reg [FRAME_SIZE-1:0] slave_rx_buffer;

    integer loop_count;


    // =========================
    // Clock
    // =========================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================
    // DUT: SPI Master
    // =========================
    SPI_Master_CRC #(
        .Frame_Size(FRAME_SIZE),
        .Number_Slave(NUMBER_SLAVE),
        .CPOL(0),
        .CPAH(0)
    ) u_master (
        .INPUT(master_input),
        .CNTL(master_cntl),
        .REFCLK(clk),
        .MISO(MISO),

        .OUTPUT(master_output),
        .SCLK(master_sclk),
        .MOSI(MOSI),
        .SS(master_ss),
        .READY(master_ready),
        .buf_input(),
        .VALID(master_valid)
    );

    // =========================
    // DUT: SPI Slave CRC
    // =========================
    SPI_Slave_CRC #(
        .n(FRAME_SIZE),
        .crc_len(5),
        .total_len(13),
        .cnum(4),
        .CPOL(0),
        .CPHA(0)
    ) u_slave (
        .n_rst(slave_n_rst),
        .data_in(slave_input),
        .load(slave_load),
        .sclk(master_sclk),
        .MOSI(MOSI),
        .n_cs(master_ss[0]),

        .data_out(slave_output),
        .MISO(MISO),
        .rx_data_valid(slave_valid),
        .rx_done(),
        .crc_out(),
        .ready(slave_ready)
    );

    // =========================
    // Tasks
    // =========================

    task reset_system;
    begin
        master_cntl  = 2'b00;
        master_input = 8'b00000000;

        slave_n_rst  = 1'b0;
        slave_load   = 1'b0;
        slave_input  = 8'b00000000;

        master_rx_buffer = 8'b00000000;
        slave_rx_buffer  = 8'b00000000;
        loop_count       = 0;

        repeat (5) @(posedge clk);

        slave_n_rst = 1'b1;

        repeat (5) @(posedge clk);
    end
    endtask


    task select_slave_0;
    begin
        master_input = 8'd0;
        master_cntl  = 2'b10;

        repeat (2) @(posedge clk);

        master_cntl = 2'b00;

        repeat (2) @(posedge clk);
    end
    endtask


    task load_master_and_slave;
        input [FRAME_SIZE-1:0] m_data;
        input [FRAME_SIZE-1:0] s_data;
    begin
        master_input = m_data;
        slave_input  = s_data;

        master_cntl = 2'b01;
        slave_load  = 1'b1;

        repeat (2) @(posedge clk);

        master_cntl = 2'b00;
        slave_load  = 1'b0;

        repeat (2) @(posedge clk);
    end
    endtask


    task transfer_once;
    begin
        // Start transfer
        master_cntl = 2'b11;

        // Chờ đủ 13 bit frame:
        // 8 data bit + 5 CRC bit.
        repeat (TOTAL_BITS + 3) @(posedge clk);

        // Force master out of TRANSFER/COMPLETE
        master_cntl = 2'b00;

        repeat (4) @(posedge clk);

        // Capture received data
        master_rx_buffer = master_output;
        slave_rx_buffer  = slave_output;

        $display("Loop %0d | M_IN=%b | M_OUT=%b | S_IN=%b | S_OUT=%b | M_VALID=%b | S_VALID=%b",
                 loop_count,
                 master_input,
                 master_rx_buffer,
                 slave_input,
                 slave_rx_buffer,
                 master_valid,
                 slave_valid);

        loop_count = loop_count + 1;
    end
    endtask


    // =========================
    // Main infinite circular loopback
    // =========================
    initial begin
        $dumpfile("spi_circular_loopback.vcd");

        // Only important waveform signals
        $dumpvars(0, clk);

        $dumpvars(0, master_input);
        $dumpvars(0, master_output);
        $dumpvars(0, master_cntl);
        $dumpvars(0, master_sclk);
        $dumpvars(0, master_ready);
        $dumpvars(0, master_valid);
        $dumpvars(0, MOSI);
        $dumpvars(0, MISO);
        $dumpvars(0, master_ss);

        $dumpvars(0, slave_input);
        $dumpvars(0, slave_output);
        $dumpvars(0, slave_valid);
        $dumpvars(0, slave_ready);
        $dumpvars(0, slave_load);
        $dumpvars(0, slave_n_rst);

        reset_system();

        select_slave_0();

        // Initial values:
        // Master sends 01010101
        // Slave sends 10101010
        load_master_and_slave(8'b01010101, 8'b10101010);

        forever begin
            transfer_once();

            // Ping-pong:
            // Master sends what it received from Slave.
            // Slave sends what it received from Master.
            load_master_and_slave(master_rx_buffer, slave_rx_buffer);
        end
    end

endmodule