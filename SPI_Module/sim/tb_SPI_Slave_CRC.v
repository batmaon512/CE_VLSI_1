`timescale 1ns / 1ps

module tb_SPI_Slave_CRC;

    // Các tham số cấu hình
    parameter n = 8;
    parameter crc_len = 5;
    
    // Tín hiệu kết nối với Slave
    reg n_rst;
    reg [n-1:0] data_in;
    reg load;
    reg sclk;
    reg MOSI;
    reg n_cs;
    
    wire [n-1:0] data_out;
    wire MISO;
    wire rx_data_valid;
    wire rx_done;
    wire ready;
    wire [4:0] crc_out;
    wire [3:0] ccounter;
    wire check_feedback;

    // Biến nội bộ Testbench để lưu dữ liệu Master nhận được
    reg [12:0] master_rx_buffer;

    // Instantiate module SPI_Slave_CRC
    SPI_Slave_CRC #(
        .n(n),
        .crc_len(crc_len)
    ) dut (
        .n_rst(n_rst),
        .data_in(data_in),
        .load(load),
        .sclk(sclk),
        .MOSI(MOSI),
        .n_cs(n_cs),
        .data_out(data_out),
        .MISO(MISO),
        .rx_data_valid(rx_data_valid),
        .rx_done(rx_done),
        .crc_out(crc_out),
        .ccounter(ccounter),
        .ready(ready),
        .check_feedback(check_feedback)
    );

    // TASK: Mô phỏng hành vi của SPI Master truyền/nhận 13 bit
    // MSB truyền trước. SCLK mặc định bằng 0, dữ liệu mẫu ở sườn lên (CPOL=0, CPHA=0)
    task master_transfer;
        input  [12:0] tx_data; // Dữ liệu Master gửi
        integer i;
        begin
            master_rx_buffer = 13'b0; // Reset buffer nhận của master
            
            for (i = 12; i >= 0; i = i - 1) begin
                // Master đẩy bit ra MOSI
                MOSI = tx_data[i];
                #20; // Thời gian thiết lập (Setup time)
                
                // Master kích sườn LÊN của SCLK (Slave và Master chốt dữ liệu)
                sclk = 1;
                master_rx_buffer[i] = MISO; // Master lấy mẫu bit từ MISO của Slave
                #20; 
                
                // Master kích sườn XUỐNG của SCLK
                sclk = 0;
            end
            #20; // Đợi ổn định sau khi xong 1 frame
        end
    endtask

    // KỊCH BẢN MÔ PHỎNG CHÍNH
    initial begin
        // Khởi tạo trạng thái ban đầu
        n_rst = 1;
        n_cs = 1; // Deactivate CS (Tích cực mức 0)
        sclk = 0;
        MOSI = 0;
        load = 0;
        data_in = 8'b00000000;
        
        // 1. Reset hệ thống (Slave)
        $display("--- STEP 1: Reset System ---");
        #10 n_rst = 0; 
        #20 n_rst = 1;
        #20;
        
        // Dữ liệu mẫu kiểm tra: Data = 8'b1011_0011 (0xB3), CRC5 = 5'b01001 (Tính tay hoặc tool chuẩn)
        // Chuỗi 13 bit ghép lại: 13'b10110011_01001
        
        // -------------------------------------------------------------------------
        // 2 & 3. Giao dịch 1: Master -> Slave (Chỉ test Master gửi, không quan tâm Slave trả gì)
        // -------------------------------------------------------------------------
        $display("--- STEP 2 & 3: Master sends data to Slave ---");
        n_cs = 0; // Activate CS
        #40;      // Đợi 1-2 chu kỳ đồng hồ hệ thống theo mô tả
        
        master_transfer(13'b10110011_01010);
        
        // Kiểm tra tín hiệu valid từ Slave sau khi nhận xong
        if (rx_done && rx_data_valid)
            $display("[PASS] Slave nhan dung Data + CRC. Data: %b", data_out);
        else
            $display("[FAIL] Slave bao loi CRC hoac chua xong!");

        n_cs = 0; // Tắt CS chuẩn bị cho bước sau
        #50;

        // -------------------------------------------------------------------------
        // 4 & 5. Giao dịch 2: Slave -> Master (Load data vào Slave rồi test gửi về)
        // -------------------------------------------------------------------------
        $display("--- STEP 4 & 5: Slave sends data to Master ---");
        
        // Tích cực tín hiệu Load
        data_in = 8'b1100_1010; // Data Slave muốn gửi
        #5;
        load = 1;
        #20; load = 0; // Tắt Load (tích cực mức thấp như bạn lưu ý trong lúc transmission)
        
        n_cs = 0; // Activate CS
        #40;
        
        // Master cấp 13 xung clk, chỉ gửi toàn 0 đi (dummy data) để lấy MISO về
        master_transfer(13'b00000000_00000); 
        
        $display("Master nhan duoc tu Slave: %b", master_rx_buffer);
        // Lưu ý: Phần kiểm tra CRC ở Master nằm ngoài module này, bạn có thể tự tính để so sánh
        
        n_cs = 0; // Tắt CS
        #50;

        // -------------------------------------------------------------------------
        // 6. Giao dịch 3: Full-Duplex (Truyền nhận đồng thời)
        // -------------------------------------------------------------------------
        $display("--- STEP 6: Full Duplex Transmission ---");
        
        // Load data vào Slave trước
        data_in = 8'b0101_0101; 
        load = 1; #20; load = 0;
        
        n_cs = 0; // Activate CS
        #40;
        
        // Master đồng thời gửi 1 data chuẩn và nhận data từ Slave
        master_transfer(13'b10110011_01010);
        
        if (rx_data_valid)
            $display("[PASS FULL-DUPLEX] Slave Nhan: %b | Master Nhan: %b", data_out, master_rx_buffer);
        else
            $display("[FAIL FULL-DUPLEX] Loi kiem tra CRC tai Slave!");

        n_cs = 0;
        #50;

        $display("--- END OF SIMULATION ---");
        $finish;
    end

endmodule