`timescale 1ns / 1ps
// =============================================================================
//  tb_uart_rx.v  --  uart_rx 的测试台
//
//  用"慢速测试发送器"喂字节，验证：
//    TP1  0x55 能被正确接收
//    TP2  0xAA 能被正确接收
//    TP3  0x00 能被正确接收（注意：0x00 全是 0，容易被起始边沿误判）
//    TP4  0xFF 能被正确接收（全 1）
//    TP5  连续 4 个字节都能收到
//    TP6  停止位为 0 时必须报 frame_err（不能当成有效字节）
// =============================================================================
module tb_uart_rx;

localparam integer DIV = 868;          // 与 DUT 一致
localparam integer BIT = 10 * DIV;     // 一个位 = 8680 ns

reg clk = 1'b0;
reg rst = 1'b1;
reg rx  = 1'b1;                        // 空闲高

wire        rx_valid;
wire [7:0]  rx_data;
wire        rx_frame_err;

integer     got_cnt = 0;               // 收到字节数
integer     err_cnt = 0;               // 帧错误次数
reg [7:0]   got [0:7];

uart_rx #(.DIV(DIV)) uut (
    .clk         (clk),
    .rst         (rst),
    .rx          (rx),
    .rx_valid    (rx_valid),
    .rx_data     (rx_data),
    .rx_frame_err(rx_frame_err)
);

always #5 clk = ~clk;                  // 100 MHz

// ---------------------------------------------------------------------------
//  测试发送器：按 115200 8N1 发一个字节
// ---------------------------------------------------------------------------
task send_byte(input [7:0] b);
    integer i;
    begin
        rx = 1'b0;                     // 起始位
        #(BIT);
        for (i = 0; i < 8; i = i + 1) begin
            rx = b[i];                 // LSB 先发
            #(BIT);
        end
        rx = 1'b1;                     // 停止位
        #(BIT);
    end
endtask

// 停止位故意发 0 的版本，用于验证 frame_err
task send_byte_bad_stop(input [7:0] b);
    integer i;
    begin
        rx = 1'b0;
        #(BIT);
        for (i = 0; i < 8; i = i + 1) begin
            rx = b[i];
            #(BIT);
        end
        rx = 1'b0;                     // 停止位错误
        #(BIT);
        rx = 1'b1;
        #(BIT);
    end
endtask

// ---------------------------------------------------------------------------
//  记录收到的字节
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (rx_valid) begin
        if (got_cnt < 8) got[got_cnt] = rx_data;
        got_cnt = got_cnt + 1;
    end
    if (rx_frame_err) err_cnt = err_cnt + 1;
end

initial begin
    $display("=== uart_rx 测试开始 (115200 8N1, 100 MHz) ===");

    #20000;
    rst = 1'b0;
    #(BIT * 2);                        // 复位后等两拍空闲

    // ---- TP1~TP4 四个典型字节 ----
    send_byte(8'h55);
    send_byte(8'hAA);
    send_byte(8'h00);
    send_byte(8'hFF);
    #(BIT * 2);

    $display("TP1 rx 0x55 -> 0x%02h  (expect 55)  %s",
             got[0], (got[0]==8'h55) ? "PASS" : "FAIL");
    $display("TP2 rx 0xAA -> 0x%02h  (expect AA)  %s",
             got[1], (got[1]==8'hAA) ? "PASS" : "FAIL");
    $display("TP3 rx 0x00 -> 0x%02h  (expect 00)  %s",
             got[2], (got[2]==8'h00) ? "PASS" : "FAIL");
    $display("TP4 rx 0xFF -> 0x%02h  (expect FF)  %s",
             got[3], (got[3]==8'hFF) ? "PASS" : "FAIL");

    // ---- TP5 连续 4 字节 ----
    got_cnt = 0;
    send_byte(8'h01);
    send_byte(8'h02);
    send_byte(8'h03);
    send_byte(8'h04);
    #(BIT * 2);
    $display("TP5 连续 4 字节 -> %02h %02h %02h %02h  (expect 01 02 03 04)  %s",
             got[0], got[1], got[2], got[3],
             ((got[0]==8'h01)&&(got[1]==8'h02)&&(got[2]==8'h03)&&(got[3]==8'h04)) ? "PASS" : "FAIL");

    // ---- TP6 停止位错误必须被检出 ----
    got_cnt = 0; err_cnt = 0;
    send_byte_bad_stop(8'h3C);
    #(BIT * 2);
    $display("TP6 停止位为 0 -> frame_err 计数 = %0d (expect 1)  %s",
             err_cnt, (err_cnt == 1) ? "PASS" : "FAIL");

    $display("=== uart_rx 测试结束 ===");
    $finish;
end

// 超时保护
initial begin
    #5_000_000;
    $display("!! TIMEOUT at t=%0d ns", $time);
    $finish;
end

endmodule
