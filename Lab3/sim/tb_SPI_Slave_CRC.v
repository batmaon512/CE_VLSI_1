`timescale 1ns / 1ps

module tb_SPI_Slave_CRC();

    localparam DATA_WIDTH = 8;
    localparam CRC_WIDTH  = 5;
    localparam FRAME_LEN  = 13;

    // =========================
    // Slave pins
    // =========================
    reg  [DATA_WIDTH-1:0] Slave_input;
    reg                   Slave_load;
    reg                   Slave_nrst;

    reg                   SPI_sclk;
    reg                   Master_MOSI;
    reg                   Slave_nCS;

    wire [DATA_WIDTH-1:0] Slave_output;
    wire                  Slave_MISO;
    wire                  Slave_ready;
    wire                  Slave_valid;
    wire                  Slave_rx_done;
    wire [CRC_WIDTH-1:0]  Slave_crc_out;

    // =========================
    // Waveform observe registers
    // =========================
    reg [DATA_WIDTH-1:0]  Master_sent;
    reg [DATA_WIDTH-1:0]  Master_received;

    reg [FRAME_LEN-1:0]   Master_13bit_frame_sent_to_slave;
    reg [FRAME_LEN-1:0]   Master_13bit_frame_received_from_slave;

    reg                   Current_MOSI_bit;
    reg                   Current_MISO_bit;
    reg [3:0]             Bit_counter;

    integer i;

    // =========================
    // DUT
    // =========================
    SPI_Slave_CRC #(
        .n(DATA_WIDTH),
        .crc_len(CRC_WIDTH),
        .total_len(FRAME_LEN),
        .cnum(4),
        .CPOL(0),
        .CPHA(0)
    ) uut (
        .n_rst(Slave_nrst),
        .data_in(Slave_input),
        .load(Slave_load),
        .sclk(SPI_sclk),
        .MOSI(Master_MOSI),
        .n_cs(Slave_nCS),

        .data_out(Slave_output),
        .MISO(Slave_MISO),
        .rx_data_valid(Slave_valid),
        .rx_done(Slave_rx_done),
        .crc_out(Slave_crc_out),
        .ready(Slave_ready)
    );

    // =========================
    // Manual clock
    // =========================
    initial begin
        SPI_sclk = 1'b0;
    end

    task one_sclk_pulse;
    begin
        #10 SPI_sclk = 1'b1;
        #10 SPI_sclk = 1'b0;
    end
    endtask

    // =========================
    // Tasks
    // =========================

    task reset_slave;
    begin
        Slave_nCS   = 1'b1;
        Master_MOSI = 1'b0;
        Slave_load  = 1'b0;
        Slave_input = 8'h00;
        SPI_sclk    = 1'b0;

        Master_sent          = 8'h00;
        Master_received   = 8'h00;
        Master_13bit_frame_sent_to_slave   = 13'h0000;
        Master_13bit_frame_received_from_slave = 13'h0000;

        Current_MOSI_bit = 1'b0;
        Current_MISO_bit = 1'b0;
        Bit_counter      = 4'd0;

        Slave_nrst = 1'b0;
        #30;
        Slave_nrst = 1'b1;
        #30;
    end
    endtask


    task master_send_13bit_frame_to_slave;
        input [7:0] data_bits;
        input [4:0] crc_bits;
    begin
        Master_sent       = data_bits;
        Master_13bit_frame_sent_to_slave = {data_bits, crc_bits};

        Slave_nCS = 1'b0;

        for (i = FRAME_LEN-1; i >= 0; i = i - 1) begin
            Bit_counter      = i[3:0];
            Current_MOSI_bit = Master_13bit_frame_sent_to_slave[i];
            Master_MOSI      = Current_MOSI_bit;

            one_sclk_pulse();
        end

        #5;

        $display("==============================================");
        $display("MASTER -> SLAVE");
        $display("8-bit sent to slave      = %b", Master_sent);
        $display("13-bit frame sent        = %b", Master_13bit_frame_sent_to_slave);
        $display("Slave output received    = %b", Slave_output);
        $display("Slave valid              = %b", Slave_valid);
        $display("Slave rx_done            = %b", Slave_rx_done);
        $display("==============================================");

        Slave_nCS = 1'b1;
        #30;
    end
    endtask
    
    task master_send_13bit_frame_to_slave_notena;
        input [7:0] data_bits;
        input [4:0] crc_bits;
    begin
        Master_sent       = data_bits;
        Master_13bit_frame_sent_to_slave = {data_bits, crc_bits};

        Slave_nCS = 1'b1;

        for (i = FRAME_LEN-1; i >= 0; i = i - 1) begin
            Bit_counter      = i[3:0];
            Current_MOSI_bit = Master_13bit_frame_sent_to_slave[i];
            Master_MOSI      = Current_MOSI_bit;

            one_sclk_pulse();
        end

        #5;

        $display("==============================================");
        $display("MASTER -> SLAVE");
        $display("8-bit sent to slave      = %b", Master_sent);
        $display("13-bit frame sent        = %b", Master_13bit_frame_sent_to_slave);
        $display("Slave output received    = %b", Slave_output);
        $display("Slave valid              = %b", Slave_valid);
        $display("Slave rx_done            = %b", Slave_rx_done);
        $display("==============================================");

        Slave_nCS = 1'b1;
        #30;
    end
    endtask


    task load_slave_tx_buffer;
        input [7:0] data_bits;
    begin
        Slave_input = data_bits;

        #10;
        Slave_load = 1'b1;
        #20;
        Slave_load = 1'b0;
        #20;
    end
    endtask


    task slave_send_13bit_frame_to_master;
    begin
        Master_received      = 8'h00;
        Master_13bit_frame_received_from_slave = 13'h0000;

        Slave_nCS = 1'b0;

        for (i = FRAME_LEN-1; i >= 0; i = i - 1) begin
            #5;

            Current_MISO_bit = Slave_MISO;
            Master_13bit_frame_received_from_slave[i] = Current_MISO_bit;

            if (i >= CRC_WIDTH) begin
                Master_received[i - CRC_WIDTH] = Current_MISO_bit;
            end

            one_sclk_pulse();
        end

        #5;

        $display("==============================================");
        $display("SLAVE -> MASTER");
        $display("Slave input loaded            = %b", Slave_input);
        $display("8-bit received from slave     = %b", Master_received);
        $display("13-bit frame received         = %b", Master_13bit_frame_received_from_slave);
        $display("Slave generated CRC           = %b", Slave_crc_out);
        $display("==============================================");

        Slave_nCS = 1'b1;
        #30;
    end
    endtask


    task test_master_to_slave_good_crc;
    begin
        reset_slave();

        master_send_13bit_frame_to_slave(
            8'b00111100,
            5'b10010
        );
    end
    endtask


    task test_master_to_slave_bad_crc;
    begin
        reset_slave();

        master_send_13bit_frame_to_slave(
            8'b00111100,
            5'b10011
        );
    end
    endtask


    task test_slave_to_master;
    begin
        reset_slave();

        load_slave_tx_buffer(8'b10100101);

        slave_send_13bit_frame_to_master();
    end
    endtask
    
    task test_master_to_slave_notena;
    begin
        reset_slave();

        master_send_13bit_frame_to_slave_notena(
            8'b00111100,
            5'b10010
        );
    end
    endtask

    // =========================
    // Main
    // =========================
    initial begin
        $dumpfile("tb_spi_slave_crc_scenario.vcd");

        // Physical pins
        $dumpvars(0, SPI_sclk);
        $dumpvars(0, Slave_nCS);
        $dumpvars(0, Master_MOSI);
        $dumpvars(0, Slave_MISO);

        // Important 8-bit observe values
        $dumpvars(0, Master_sent);
        $dumpvars(0, Master_received);

        // Full 13-bit observe values
        $dumpvars(0, Master_13bit_frame_sent_to_slave);
        $dumpvars(0, Master_13bit_frame_received_from_slave);

        // Current bit observe
        $dumpvars(0, Current_MOSI_bit);
        $dumpvars(0, Current_MISO_bit);
        $dumpvars(0, Bit_counter);

        // Slave outputs
        $dumpvars(0, Slave_input);
        $dumpvars(0, Slave_output);
        $dumpvars(0, Slave_load);
        $dumpvars(0, Slave_nrst);
        $dumpvars(0, Slave_ready);
        $dumpvars(0, Slave_valid);
        $dumpvars(0, Slave_rx_done);
        $dumpvars(0, Slave_crc_out);

        test_master_to_slave_good_crc();

        #100;

        test_master_to_slave_bad_crc();

        #100;

        test_slave_to_master();
        
        #100;
        
        test_master_to_slave_notena();

        #200;
        $finish;
    end

endmodule