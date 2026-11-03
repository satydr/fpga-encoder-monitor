`timescale 1ns / 1ps
// OLED 驱动测试台：带假从机，把每次 I2C 传输的字节全部抓下来核对
module tb_oled;

reg clk = 0;
reg rst = 1;
reg [15:0] rpm = 16'd0;
reg tick = 0;
wire scl;
wire sda;

oled_ssd1306 #(
    .BOOT_CYCLES(24'd500),      // 仿真里把上电等待缩到 500 拍
    .GAP_CYCLES (24'd2000)
) uut (
    .clk(clk), .rst(rst), .rpm(rpm), .tick(tick), .scl(scl), .sda(sda)
);

always #5 clk = ~clk;
pullup(sda); pullup(scl);

// ---------- 假从机：只在 ACK 位把 SDA 拉低 ----------
// ⚠️ STOP 过程里还会多出一次 SCL 上升沿，所以每次 START 必须把位计数器清零，
//    否则位序会整体错一位（症状：抓到的字节 = 真值右移一位，且从机把 ACK 拉错位置）
reg [3:0] edge_cnt = 0;
reg scl_d = 1, sda_d = 1;
reg ack_drive = 0, bus_busy = 0;

wire scl_rise =  scl & ~scl_d;
wire scl_fall = ~scl &  scl_d;
wire sda_rise =  sda & ~sda_d;
wire sda_fall = ~sda &  sda_d;
wire start_cond = scl & sda_fall & !bus_busy;   // START：SCL 高时 SDA 下降，且总线空闲
wire stop_cond  = scl & sda_rise &  bus_busy;   // STOP ：SCL 高时 SDA 上升

always @(posedge clk) begin
    scl_d <= scl;
    sda_d <= sda;
end

always @(posedge clk) begin
    if (start_cond) edge_cnt <= 4'd0;           // 每一帧重新开始数
    else if (scl_rise) begin
        if (edge_cnt == 4'd8) ack_drive <= 1'b1;
        edge_cnt <= (edge_cnt == 4'd8) ? 4'd0 : edge_cnt + 4'd1;
    end
    if (scl_fall) ack_drive <= 1'b0;
end
assign sda = ack_drive ? 1'b0 : 1'bz;

// ---------- 抓字节 ----------
reg [7:0] rx_byte = 0;
integer trans_n = 0, byte_n = 0;
reg [7:0] head_byte = 0;

always @(posedge clk) begin
    if (start_cond) begin
        bus_busy <= 1'b1;
        trans_n  = trans_n + 1;
        byte_n   = 0;
        $display("%0d ns : --- transfer #%0d starts ---", $time, trans_n);
    end
    if (scl_rise) begin
        if (edge_cnt == 4'd8) begin             // 第 9 个上升沿：收满一字节
            if (byte_n == 0) head_byte = rx_byte;
            byte_n = byte_n + 1;
            if (trans_n == 1)                                   // 初始化序列：全打
                $display("      init  [%0d] = %02h", byte_n - 1, rx_byte);
            if (trans_n == 2)                                   // 窗口设置：全打
                $display("      win   [%0d] = %02h", byte_n - 1, rx_byte);
            if (trans_n == 3 && byte_n <= 3)                    // 第一屏开头
                $display("      data1 [%0d] = %02h", byte_n - 1, rx_byte);
            if (trans_n == 5 && byte_n == 388)                  // 第二屏：波形点所在字节
                $display("      WAVE PIXEL = %02h (expect 80)", rx_byte);
        end else begin
            rx_byte <= {rx_byte[6:0], sda};
        end
    end
    if (stop_cond) begin
        bus_busy <= 1'b0;
        $display("%0d ns : transfer #%0d done, %0d bytes, head=%02h",
                 $time, trans_n, byte_n, head_byte);
    end
end

// ---------- 在第一屏刷屏途中塞一个采样点：rpm=512 -> y=31 -> page3 bit7 ----------
always @(posedge clk) begin
    if (trans_n == 3 && byte_n == 200) rpm <= 16'd512;
end
reg tick_d = 0;
always @(posedge clk) begin
    tick_d <= tick;
    tick   <= (trans_n == 3 && byte_n == 300 && !tick_d) ? 1'b1 : 1'b0;
end

initial begin
    $display("=== OLED driver: init / window / framebuffer ===");
    #200 rst = 0;
    #400000000;                    // 400 ms：够跑完两屏
    $display("!! timeout, trans_n=%0d", trans_n);
    $finish;
end

endmodule
