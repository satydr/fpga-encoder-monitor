`timescale 1ns / 1ps
// =============================================================================
//  tb_top_uart.v  ——  整链端到端验证 UART 上传
//
//  与前面所有 "单模块 tb" 的区别：这里**不给假数据**，而是真的喂正交编码器波形，
//  让 sync -> debounce -> quad -> pos / speed -> filter -> frame -> uart_tx 全链跑起来，
//  然后在串口线上把帧抓回来，跟顶层此刻的真实输出交叉比对。
//
//  测试点：
//    TP1  第 1 帧：帧头/长度/状态/校验和；且帧内 turns、rpm 与顶层输出**严格相等**
//    TP2  第 2 帧：同样比对；且 position 比第 1 帧大（证明数据在动）
//    TP3  两帧间隔 = 10 ms（上传周期严格跟随闸门）
// =============================================================================
module tb_top_uart;

reg        clk, rst, clr;
reg  [2:0] enc_raw;
wire [1:0] state;
wire       dir;
wire [15:0] count;
wire       err;
wire [11:0] position;
wire signed [15:0] turns;
wire [15:0] pulse_num;
wire [15:0] rpm;
wire [15:0] rpm_filtered;
wire       over_speed;
wire       pulse_loss;
wire       uart_tx_pin;

encoder_top dut (
    .clk(clk), .rst(rst), .clr(clr), .enc_raw(enc_raw),
    .state(state), .dir(dir), .count(count), .err(err),
    .position(position), .turns(turns),
    .pulse_num(pulse_num), .rpm(rpm), .rpm_filtered(rpm_filtered),
    .over_speed(over_speed), .pulse_loss(pulse_loss),
    .uart_tx_pin(uart_tx_pin)
);

always #5 clk = ~clk;                  // 100 MHz

parameter integer BIT_NS = 8680;       // 1 位 = 868 拍 x 10 ns（115200 bps）

integer   n, b, i;
reg [7:0] rx [0:10];                   // 收到的 11 个字节
reg [7:0] csum;
reg signed [15:0] f_t;                 // 帧里解出来的 turns（按有符号解释）
reg [11:0]        f_p;                 // 帧里解出来的 position
reg [15:0]        f_r;                 // 帧里解出来的 rpm
time      t0, t_f0, t_f1;

// ---- 收一帧：11 个字节，每位中点采样 ----
task recv_frame;
    begin
        for (n = 0; n < 11; n = n + 1) begin
            @(negedge uart_tx_pin);            // 起始位下降沿 = 新字节开始
            if (n == 0) t0 = $time;            // 记下本帧第一字节的时刻
            #(BIT_NS + BIT_NS/2);              // 走 1.5 位，落在 bit0 正中间
            for (b = 0; b < 8; b = b + 1) begin
                rx[n][b] = uart_tx_pin;
                #BIT_NS;
            end
        end
    end
endtask

// ---- 激励：连续正转，600 转/分（每 41670 ns 推进一个正交相位）----
// ⚠️ enc_raw[1:0] = {B, A}，正转序列是 00 -> 01 -> 11 -> 10 -> 00
// Z（enc_raw[2]）全程不给：20 ms 内只有 480 计数 < 2600，不会误报丢脉冲
initial begin
    clk = 1'b0; rst = 1'b1; clr = 1'b0; enc_raw = 3'b000;
    #20 rst = 1'b0;
    #100;
    forever begin
        enc_raw[1:0] = 2'b01; #41670;
        enc_raw[1:0] = 2'b11; #41670;
        enc_raw[1:0] = 2'b10; #41670;
        enc_raw[1:0] = 2'b00; #41670;
    end
end

initial begin
    #200;                                       // 等复位释放

    // ==================== TP1：第 1 帧 ====================
    recv_frame;
    t_f0 = t0;
    f_t = {rx[3], rx[4]};
    f_p = {rx[5][3:0], rx[6]};
    f_r = {rx[7], rx[8]};

    csum = 8'd0;
    for (i = 0; i < 10; i = i + 1) csum = csum + rx[i];

    $display("TP1 frame  : hdr=%h %h len=%h status=%h   sum=%h calc=%h",
             rx[0], rx[1], rx[2], rx[9], rx[10], csum);
    $display("TP1 vs dut : turns frame=%0d dut=%0d  |  rpm_f frame=%0d dut=%0d",
             f_t, turns, f_r, rpm_filtered);
    $display("TP1 pos    : frame=%0d dut=%0d  (frame should be slightly smaller)", f_p, position);

    // ==================== TP2：第 2 帧 ====================
    recv_frame;
    t_f1 = t0;
    f_t = {rx[3], rx[4]};
    f_p = {rx[5][3:0], rx[6]};
    f_r = {rx[7], rx[8]};

    csum = 8'd0;
    for (i = 0; i < 10; i = i + 1) csum = csum + rx[i];

    $display("TP2 frame  : hdr=%h %h len=%h status=%h   sum=%h calc=%h",
             rx[0], rx[1], rx[2], rx[9], rx[10], csum);
    $display("TP2 vs dut : turns frame=%0d dut=%0d  |  rpm_f frame=%0d dut=%0d",
             f_t, turns, f_r, rpm_filtered);
    $display("TP2 pos    : frame=%0d dut=%0d", f_p, position);

    // ==================== TP3：上传周期 ====================
    $display("TP3 period : %0d ns (expect 10000000 ns = 10 ms)", t_f1 - t_f0);

    $finish;
end

endmodule
