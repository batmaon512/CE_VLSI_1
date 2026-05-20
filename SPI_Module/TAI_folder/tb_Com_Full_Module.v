`timescale 1ns / 1ps

module tb_Com_Full_Module();

    parameter N = 8;
    parameter SLAVES = 8;
    parameter TOTAL_BITS = 13; // 8 data + 5 CRC

    // =========================
    // Signals to observe
    // =========================
    reg                 clk;

    reg  [N-1:0]        Master_input;
    wire [N-1:0]        Master_output;
    reg  [1:0]          Master_cntl;
    wire                Master_clk;
    wire                Master_ready;
    wire                Master_valid;
    wire                MOSI;
    wire                MISO;
    wire [SLAVES-1:0]   Master_SS;

    reg  [N-1:0]        Slave_input;
    wire [N-1:0]        Slave_output;
    wire                Slave_valid;
    wire                Slave_ready;
    reg                 Slave_load;
    reg                 Slave_nrst;

    // =========================
    // Clock 100 MHz
    // =========================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================
    // Master DUT
    // =========================
    SPI_Master_CRC #(
        .Frame_Size(N),
        .Number_Slave(SLAVES),
        .CPOL(0),
        .CPAH(0)
    ) master_dut (
        .INPUT(Master_input),
        .CNTL(Master_cntl),
        .REFCLK(clk),
        .MISO(MISO),

        .OUTPUT(Master_output),
        .SCLK(Master_clk),
        .MOSI(MOSI),
        .SS(Master_SS),
        .READY(Master_ready),
        .VALID(Master_valid)
    );

    // =========================
    // Slave DUT
    // =========================
    SPI_Slave_CRC #(
        .n(N),
        .crc_len(5),
        .total_len(13),
        .cnum(4),
        .CPOL(0),
        .CPHA(0)
    ) slave_dut (
        .n_rst(Slave_nrst),
        .data_in(Slave_input),
        .load(Slave_load),
        .sclk(Master_clk),
        .MOSI(MOSI),
        .n_cs(Master_SS[0]),

        .data_out(Slave_output),
        .MISO(MISO),
        .rx_data_valid(Slave_valid),
        .ready(Slave_ready)
    );

    // =========================
    // Tasks
    // =========================

    task reset_system;
    begin
        Master_input = 8'h00;
        Master_cntl  = 2'b00;

        Slave_input  = 8'h00;
        Slave_load   = 1'b0;
        Slave_nrst   = 1'b1;

        repeat (2) @(posedge clk);

        Slave_nrst = 1'b0;
        repeat (2) @(posedge clk);

        Slave_nrst = 1'b1;
        repeat (3) @(posedge clk);
    end
    endtask


    task load_master_data;
        input [N-1:0] data;
    begin
        Master_input = data;
        Master_cntl  = 2'b01;

        repeat (2) @(posedge clk);

        Master_cntl = 2'b00;
        repeat (2) @(posedge clk);
    end
    endtask


    task select_slave_0;
    begin
        Master_input = 8'h00;
        Master_cntl  = 2'b10;

        repeat (2) @(posedge clk);

        Master_cntl = 2'b00;
        repeat (2) @(posedge clk);
    end
    endtask


    task load_slave_data;
        input [N-1:0] data;
    begin
        Slave_input = data;
        Slave_load  = 1'b1;

        repeat (2) @(posedge clk);

        Slave_load = 1'b0;
        repeat (2) @(posedge clk);
    end
    endtask


    task start_transfer;
    begin
        Master_cntl = 2'b11;

        // chờ đủ 8 data + 5 CRC + vài clock margin
        repeat (TOTAL_BITS + 4) @(posedge clk);

        Master_cntl = 2'b00;

        repeat (4) @(posedge clk);
    end
    endtask


    task print_result;
        input [8*32-1:0] test_name;
        input [N-1:0] expected_master_send;
        input [N-1:0] expected_slave_send;
    begin
        $display("==================================================");
        $display("%s", test_name);
        $display("Master sent     = 0x%h", expected_master_send);
        $display("Slave received  = 0x%h", Slave_output);
        $display("Slave sent      = 0x%h", expected_slave_send);
        $display("Master received = 0x%h", Master_output);
        $display("Master valid    = %b", Master_valid);
        $display("Slave valid     = %b", Slave_valid);
        $display("Master ready    = %b", Master_ready);
        $display("Slave ready     = %b", Slave_ready);
        $display("==================================================");
    end
    endtask


    task run_full_duplex_transfer;
        input [N-1:0] master_data;
        input [N-1:0] slave_data;
        input [8*32-1:0] test_name;
    begin
        load_master_data(master_data);
        load_slave_data(slave_data);
        select_slave_0();

        start_transfer();

        print_result(test_name, master_data, slave_data);
    end
    endtask

    // =========================
    // Main test
    // =========================
    initial begin
        $dumpfile("com_full_module_clean.vcd");

        // chỉ dump signal quan trọng
        $dumpvars(0, clk);

        $dumpvars(0, Master_input);
        $dumpvars(0, Master_output);
        $dumpvars(0, Master_cntl);
        $dumpvars(0, Master_clk);
        $dumpvars(0, Master_ready);
        $dumpvars(0, Master_valid);
        $dumpvars(0, MOSI);
        $dumpvars(0, MISO);
        $dumpvars(0, Master_SS);

        $dumpvars(0, Slave_input);
        $dumpvars(0, Slave_output);
        $dumpvars(0, Slave_valid);
        $dumpvars(0, Slave_ready);
        $dumpvars(0, Slave_load);
        $dumpvars(0, Slave_nrst);

        reset_system();

        run_full_duplex_transfer(
            8'hD4,
            8'h00,
            "PHASE 1: MASTER TO SLAVE"
        );

        #50;

        run_full_duplex_transfer(
            8'h00,
            8'hA5,
            "PHASE 2: SLAVE TO MASTER"
        );

        #50;

        run_full_duplex_transfer(
            8'h33,
            8'hCC,
            "PHASE 3: FULL DUPLEX"
        );

        #100;
        $finish;
    end

endmodule