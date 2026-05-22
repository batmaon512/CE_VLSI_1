`timescale 1ns / 1ps

module tb_SPI_Circular_Loopback();
    parameter N = 8;
    
    // Signals
    reg [N-1:0] m_in_reg;
    wire [N-1:0] m_out_wire;
    wire [N-1:0] s_out_wire;
    // Nối Slave Output về lại Slave Input
    wire [N-1:0] s_in_wire = s_out_wire; 

    reg [1:0] m_cntl;
    reg m_clk;
    wire sclk, mosi, miso;
    wire [7:0] ss;
    wire m_ready, m_valid;
    reg s_rst_n, s_load;

    initial m_clk = 0;
    always #5 m_clk = ~m_clk;

    // Instantiate Master
    SPI_Master_CRC #(N, 8) Master_Loop (
        .INPUT(m_in_reg), .CNTL(m_cntl), .REFCLK(m_clk),
        .MISO(miso), .OUTPUT(m_out_wire), .SCLK(sclk),
        .MOSI(mosi), .SS(ss), .READY(m_ready), .VALID(m_valid)
    );

    // Instantiate Slave
    SPI_Slave_CRC #(N, 5) Slave_Loop (
        .n_rst(s_rst_n), .data_in(s_in_wire), .load(s_load),
        .sclk(sclk), .MOSI(mosi), .n_cs(ss[0]),
        .data_out(s_out_wire), .MISO(miso)
    );

    initial begin
        s_rst_n = 0; s_load = 0; m_cntl = 0;
        m_in_reg = 8'h99; // Dữ liệu gốc khởi tạo tại Master
        #20 s_rst_n = 1;

        // VÒNG 1: Master -> Slave
        $display("Loopback Vong 1: Master (0x99) -> Slave");
        m_cntl = 2'b01; #10; // LOAD_DT
        m_cntl = 2'b10; #10; // LOAD_CS
        m_cntl = 2'b11;      // TRANSFER
        wait(m_valid); #10;
        m_cntl = 2'b00; wait(m_ready);

        // VÒNG 2: Slave nạp lại dữ liệu nhận được và gửi ngược về Master
        $display("Loopback Vong 2: Slave -> Master (Tra lai 0x99)");
        s_load = 1; #10; s_load = 0; // Slave nạp s_in_wire (đang là 0x99) vào buffer
        
        // Nối Master Output về Master Input cho vòng duplex
        m_in_reg = m_out_wire; 
        m_cntl = 2'b01; #10;
        m_cntl = 2'b11; // TRANSFER tiếp
        wait(m_valid); #10;
        m_cntl = 2'b00; wait(m_ready);

        if (m_out_wire == 8'h99)
            $display("LOOPBACK THANH CONG! Du lieu ve Master: 0x%h", m_out_wire);
        else
            $display("LOOPBACK THAT BAI! Du lieu ve Master: 0x%h", m_out_wire);

        #50 $finish;
    end
endmodule