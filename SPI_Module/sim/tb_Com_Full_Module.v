`timescale 1ns / 1ps

module tb_Com_Full_Module();
    // --- PARAMETERS ---
    parameter N = 8;
    parameter SLAVES = 8;

    // --- SIGNALS MASTER ---
    reg [N-1:0]     m_input;
    reg [1:0]       m_cntl;
    reg             m_refclk;
    wire [N-1:0]    m_output;
    wire            spi_sclk, spi_mosi, spi_miso;
    wire [SLAVES-1:0] spi_ss;
    wire            m_ready, m_valid;

    // --- SIGNALS SLAVE ---
    reg [N-1:0]     s_input;
    reg             s_load;
    reg             s_rst_n;
    wire [N-1:0]    s_output;
    wire            s_ready, s_rx_valid;
    wire [3:0] ccounter;
    wire csclk;

    // Clock Generation (100MHz)
    initial m_refclk = 0;
    always #5 m_refclk = ~m_refclk;

    // --- INSTANTIATION ---
    SPI_Master #(N, SLAVES) master_dut (
        .INPUT(m_input), .CNTL(m_cntl), .REFCLK(m_refclk),
        .MISO(spi_miso), .OUTPUT(m_output), .SCLK(spi_sclk),
        .MOSI(spi_mosi), .SS(spi_ss), .READY(m_ready), .VALID(m_valid)
    );

    SPI_Slave_CRC #(N, 5) slave_dut (
        .n_rst(s_rst_n), .data_in(s_input), .load(s_load),
        .sclk(spi_sclk), .MOSI(spi_mosi), .n_cs(spi_ss[0]), // Chọn Slave 0
        .data_out(s_output), .MISO(spi_miso),
        .rx_data_valid(s_rx_valid), .ready(s_ready), .ccounter(ccounter), .csclk(csclk)
    );

    // --- TEST PROCEDURES ---
    initial begin
        // Khởi tạo hệ thống
        s_rst_n = 1; s_load = 0; m_cntl = 0; m_input = 0; s_input = 0;
        #5 s_rst_n = 0;
        #5 s_rst_n = 1;
        #20;

        // --- GIAI ĐOẠN 1: MASTER TO SLAVE ---
        $display("Giai doan 1: Master -> Slave");
        m_input = 8'hD4;      // Dữ liệu Master muốn gửi
        m_cntl = 2'b01;       // Nạp dữ liệu vào Master (LOAD_DT)
        #10;
        m_input = 8'h00;      // Chọn Slave 0 (Địa chỉ 0)
        m_cntl = 2'b10;       // Nạp Slave Select (LOAD_CS) -> SS[0] sẽ về 0
        #10;
        m_cntl = 2'b11;       // Bắt đầu truyền (TRANSFER)
        
        wait(m_valid == 1 && m_ready == 0); // Đợi xong frame (m_valid bật lên ở nhịp cuối)
        #10 m_cntl = 2'b00;   // Về IDLE
        wait(m_ready == 1);   // Xác nhận về IDLE thành công
        $display("Master gui: 0x%h, Slave nhan: 0x%h, CRC Valid: %b", 8'hD4, s_output, s_rx_valid);
        #50;

        // --- GIAI ĐOẠN 2: SLAVE TO MASTER ---
        $display("Giai doan 2: Slave -> Master");
        s_input = 8'hA5;      // Dữ liệu Slave chuẩn bị
        #5;
        s_load = 1; #10 s_load = 0; // Nạp vào buffer Slave
        
        m_input = 8'h00;      // Nạp dummy data cho Master
        m_cntl = 2'b01; #10;
        m_cntl = 2'b10; #10;  // Giữ SS[0] active
        m_cntl = 2'b11;       // Truyền
        
        wait(m_valid == 1);
        #10 m_cntl = 2'b00;
        wait(m_ready == 1);
        $display("Slave gui: 0x%h, Master nhan: 0x%h", 8'hA5, m_output);
        #55;

        // --- GIAI ĐOẠN 3: FULL DUPLEX ---
        $display("Giai doan 3: Full Duplex");
        m_input = 8'h33; m_cntl = 2'b01; #10;
        s_input = 8'hCC; 
//        m_input = 8'h0;m_cntl = 2'b10;
        #5 s_load = 1;
        #10 s_load = 0;
        m_cntl = 2'b11;
        
        wait(m_valid == 1);
        #10 m_cntl = 2'b00;
        wait(m_ready == 1);
        $display("Master gui 33 nhan %h | Slave gui CC nhan %h", m_output, s_output);
        
        #100 $finish;
    end
endmodule