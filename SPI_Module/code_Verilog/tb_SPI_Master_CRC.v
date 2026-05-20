
`timescale 1ns / 1ps

module tb_SPI_Master_CRC();

    localparam FRAME_SIZE   = 8;
    localparam NUMBER_SLAVE = 8;
    localparam FRAME_LEN    = 13;

    // ==========================================================
    // MASTER PINS
    // ==========================================================
    reg  [FRAME_SIZE-1:0] Master_input;
    reg  [1:0]            Master_cntl;
    reg                   REFCLK;
    reg                   MISO;

    wire [FRAME_SIZE-1:0] Master_output;
    wire                  Master_SCLK;
    wire                  MOSI;
    wire [NUMBER_SLAVE-1:0] Master_SS;
    wire                  Master_ready;
    wire                  Master_valid;

    // ==========================================================
    // OBSERVE SIGNALS
    // ==========================================================

    // Slave -> Master
    reg [FRAME_LEN-1:0]   Slave_virtual_tx_frame;
    reg [FRAME_SIZE-1:0]  Slave_8bit_sent_to_master;
    reg [FRAME_SIZE-1:0]  Master_8bit_received_from_slave;

    // Master -> Slave
    reg [FRAME_LEN-1:0]   Master_virtual_tx_frame;

    reg [FRAME_SIZE-1:0]  Master_sent;
    reg [FRAME_SIZE-1:0]  Slave_received;

    // bit tracking
    reg                   Current_MISO_bit;
    reg                   Current_MOSI_bit;
    reg [3:0]             Bit_index;

    integer i;

    // ==========================================================
    // DUT
    // ==========================================================
    SPI_Master_CRC #(
        .Frame_Size(FRAME_SIZE),
        .Number_Slave(NUMBER_SLAVE),
        .CPOL(0),
        .CPAH(0)
    ) master_dut (
        .INPUT(Master_input),
        .CNTL(Master_cntl),
        .REFCLK(REFCLK),
        .MISO(MISO),

        .OUTPUT(Master_output),
        .SCLK(Master_SCLK),
        .MOSI(MOSI),
        .SS(Master_SS),
        .READY(Master_ready),
        .buf_input(),
        .VALID(Master_valid)
    );

    // ==========================================================
    // REFCLK
    // ==========================================================
    initial begin
        REFCLK = 1'b0;
        forever #5 REFCLK = ~REFCLK;
    end

    // ==========================================================
    // BASIC TASKS
    // ==========================================================

    task init_system;
    begin
        Master_input = 8'h00;
        Master_cntl  = 2'b00;
        MISO         = 1'b0;

        Slave_virtual_tx_frame          = 13'b0;
        Slave_8bit_sent_to_master       = 8'h00;
        Master_8bit_received_from_slave = 8'h00;

        Master_virtual_tx_frame = 13'b0;

        Master_sent    = 8'h00;
        Slave_received = 8'h00;

        Current_MISO_bit = 1'b0;
        Current_MOSI_bit = 1'b0;
        Bit_index        = 4'd0;

        repeat (5) @(posedge REFCLK);
    end
    endtask


    task go_idle;
    begin
        Master_cntl = 2'b00;
        repeat (4) @(posedge REFCLK);
    end
    endtask


    task select_slave_by_input;
        input [7:0] slave_id;
    begin
        Master_input = slave_id;
        Master_cntl  = 2'b10;

        repeat (2) @(posedge REFCLK);

        Master_cntl = 2'b00;

        repeat (2) @(posedge REFCLK);
    end
    endtask


    task load_master_data;
        input [7:0] data;
    begin
        Master_input = data;
        Master_cntl  = 2'b01;

        repeat (2) @(posedge REFCLK);

        Master_cntl = 2'b00;

        repeat (2) @(posedge REFCLK);
    end
    endtask

    // ==========================================================
    // SLAVE VIRTUAL SENDS DATA TO MASTER
    //
    // IMPORTANT:
    //
    // DATA:
    // data[0] -> data[1] -> ... -> data[7]
    //
    // CRC:
    // crc[4] -> crc[3] -> ... -> crc[0]
    //
    // SAME BEHAVIOR AS Parallel_to_serial
    // ==========================================================

    task slave_virtual_send_13bit_to_master;
        input [7:0] data_bits;
        input [4:0] crc_bits;

        reg [7:0] slave_tx_buffer;

        integer data_i;
        integer crc_i;
    begin

        Slave_8bit_sent_to_master = data_bits;

        // waveform observe only
        Slave_virtual_tx_frame = {data_bits, crc_bits};

        Master_8bit_received_from_slave = 8'h00;

        // ======================================================
        // LOAD behavior
        //
        // same as:
        // buffer <= data_in
        // MISO = buffer[0]
        // ======================================================
        slave_tx_buffer = data_bits;

        MISO             = slave_tx_buffer[0];
        Current_MISO_bit = slave_tx_buffer[0];
        Bit_index        = 4'd0;

        // ======================================================
        // START TRANSFER
        // ======================================================
        Master_cntl = 2'b11;

        // Master samples first bit
        @(posedge Master_SCLK);

        Master_8bit_received_from_slave[0]
            = MISO;

        // ======================================================
        // SEND REMAINING DATA BITS
        //
        // SHIFT AT NEGEDGE
        // SAMPLE AT POSEDGE
        // ======================================================
        for (data_i = 1; data_i < 8; data_i = data_i + 1) begin

            @(negedge Master_SCLK);

            // SAME AS Parallel_to_serial SHIFT
            slave_tx_buffer =
                {1'b0, slave_tx_buffer[7:1]};

            MISO             = slave_tx_buffer[0];
            Current_MISO_bit = slave_tx_buffer[0];
            Bit_index        = data_i[3:0];

            @(posedge Master_SCLK);

            Master_8bit_received_from_slave[data_i]
                = MISO;
        end

        // ======================================================
        // SEND CRC
        // crc[4] -> crc[0]
        // ======================================================
        for (crc_i = 4; crc_i >= 0; crc_i = crc_i - 1) begin

            @(negedge Master_SCLK);

            MISO             = crc_bits[crc_i];
            Current_MISO_bit = crc_bits[crc_i];

            Bit_index = 8 + (4 - crc_i);

            @(posedge Master_SCLK);
        end

        // hold CNTL=3 few cycles
        repeat (3) @(posedge REFCLK);

        Master_cntl = 2'b00;

        repeat (4) @(posedge REFCLK);

        $display("==================================================");
        $display("SLAVE -> MASTER");
        $display("Slave loaded buffer         = %b",
                    Slave_8bit_sent_to_master);
        $display("Expected Master receive     = %b",
                    Master_8bit_received_from_slave);
        $display("Master OUTPUT               = %b",
                    Master_output);
        $display("Master VALID                = %b",
                    Master_valid);
        $display("Master READY                = %b",
                    Master_ready);
        $display("==================================================");

    end
    endtask

    // ==========================================================
    // CAPTURE MOSI FROM MASTER
    //
    // SLAVE SAMPLE MOSI AT POSEDGE
    // ==========================================================

    task capture_master_13bit_to_slave;
    begin

        Slave_received          = 8'h00;
        Master_virtual_tx_frame = 13'b0;

        Master_cntl = 2'b11;

        for (i = FRAME_LEN-1; i >= 0; i = i - 1) begin

            @(posedge Master_SCLK);

            Bit_index        = i[3:0];
            Current_MOSI_bit = MOSI;

            Master_virtual_tx_frame[i]
                = Current_MOSI_bit;

            if (i >= 5) begin
                Slave_received[i-5]
                    = Current_MOSI_bit;
            end
        end

        repeat (3) @(posedge REFCLK);

        Master_cntl = 2'b00;

        repeat (4) @(posedge REFCLK);

        $display("==================================================");
        $display("MASTER -> SLAVE");
        $display("Master input data           = %b",
                    Master_sent);
        $display("Slave captured data         = %b",
                    Slave_received);
        $display("Slave captured frame        = %b",
                    Master_virtual_tx_frame);
        $display("Master VALID                = %b",
                    Master_valid);
        $display("Master READY                = %b",
                    Master_ready);
        $display("==================================================");

    end
    endtask

    // ==========================================================
    // TEST 1
    // GOOD CRC
    // ==========================================================

    task test_slave_send_good_crc_to_master;
    begin

        $display("TEST 1 : GOOD CRC");

        go_idle();

        // select slave 0
        select_slave_by_input(8'b00000000);

        slave_virtual_send_13bit_to_master(
            8'b00111100,
            5'b10010
        );

    end
    endtask

    // ==========================================================
    // TEST 2
    // BAD CRC
    // ==========================================================

    task test_slave_send_bad_crc_to_master;
    begin

        $display("TEST 2 : BAD CRC");

        go_idle();

        // invalid slave
        select_slave_by_input(8'b00001111);

        slave_virtual_send_13bit_to_master(
            8'b11001100,
            5'b10111
        );

    end
    endtask

    // ==========================================================
    // TEST 3
    // MASTER SENDS TO SLAVE
    // ==========================================================

    task test_master_send_to_slave;
    begin

        $display("TEST 3 : MASTER SENDS");

        go_idle();

        Master_sent = 8'b00110011;

        // LOAD DATA
        load_master_data(8'b00110011);

        // SELECT SLAVE 3
        select_slave_by_input(8'd3);

        // CAPTURE MOSI
        capture_master_13bit_to_slave();

    end
    endtask

    // ==========================================================
    // MAIN
    // ==========================================================

    initial begin

        $dumpfile("tb_spi_master_crc.vcd");

        // master pins
        $dumpvars(0, REFCLK);
        $dumpvars(0, Master_input);
        $dumpvars(0, Master_cntl);
        $dumpvars(0, Master_output);
        $dumpvars(0, Master_SCLK);
        $dumpvars(0, MOSI);
        $dumpvars(0, MISO);
        $dumpvars(0, Master_SS);
        $dumpvars(0, Master_ready);
        $dumpvars(0, Master_valid);

        // observe
        $dumpvars(0, Slave_virtual_tx_frame);
        $dumpvars(0, Slave_8bit_sent_to_master);
        $dumpvars(0, Master_8bit_received_from_slave);

        $dumpvars(0, Master_virtual_tx_frame);

        $dumpvars(0, Master_sent);
        $dumpvars(0, Slave_received);

        // bit tracking
        $dumpvars(0, Current_MISO_bit);
        $dumpvars(0, Current_MOSI_bit);
        $dumpvars(0, Bit_index);

        init_system();

        // ======================================================
        // TEST 1
        // ======================================================
        test_slave_send_good_crc_to_master();

        #100;

        // ======================================================
        // TEST 2
        // ======================================================
        test_slave_send_bad_crc_to_master();

        #100;

        // ======================================================
        // TEST 3
        // ======================================================
        test_master_send_to_slave();

        #200;

        $finish;
    end

endmodule