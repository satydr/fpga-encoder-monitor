`timescale 1ns / 1ps

module tb_uart_frame;

reg               clk, rst;
reg               tick;
reg  signed [15:0] turns;
reg  [11:0]        position;
reg  [15:0]        rpm;
reg               over_speed, pulse_loss;

wire              tx_start;
wire [7:0]        tx_data;
wire              tx;
wire              tx_busy;
uart_tx u_tx (
    .clk      (clk),
    .rst      (rst),
    .tx_start (tx_start),
    .tx_data  (tx_data),
    .tx       (tx),
    .tx_busy  (tx_busy)
);

uart_frame u_frame (
    .clk        (clk),
    .rst        (rst),
    .tick       (tick),
    .turns      (turns),
    .position   (position),
    .rpm        (rpm),
    .over_speed (over_speed),
    .pulse_loss (pulse_loss),
    .tx_start   (tx_start),
    .tx_data    (tx_data),
    .tx_busy    (tx_busy)
);

always #5 clk = ~clk;                  // 100 MHz

parameter integer BIT_NS  = 8680;      // 1 位时长（115200 bps）
parameter integer TICK_NS = 10000000;  // 10 ms，和真实闸门一致

integer   i;
reg [7:0] rx [0:10];                   // 收到的 11 个字节
reg [7:0] csum;
time      t0, t_f0, t_f1;
initial begin
    tick = 1'b0;
    forever begin
        #(TICK_NS/2);
        tick = 1'b1;
        #10;
        tick = 1'b0;
        #(TICK_NS/2 - 10);
    end
end
task recv_frame;
    integer n, b;
    begin
        for (n = 0; n < 11; n = n + 1) begin
            @(negedge tx);                 // 等起始位下降沿 = 新字节开始
            if (n == 0) t0 = $time;        // 记下本帧第一字节的时刻
            #(BIT_NS + BIT_NS/2);          // 再走 1.5 位，正好落在 bit0 正中间
            for (b = 0; b < 8; b = b + 1) begin
                rx[n][b] = tx;             // 中点采样
                #BIT_NS;                   // 跳到下一位中点
            end
        end
    end
endtask
initial begin
    clk = 1'b0; rst = 1'b1;
    turns = 16'sd0; position = 12'd0; rpm = 16'd0;
    over_speed = 1'b0; pulse_loss = 1'b0;

    #25 rst = 1'b0;

    // ============ TP1：turns=-3, position=1234, rpm=600, 超速=1 ============
    turns      = -16'sd3;
    position   = 12'd1234;
    rpm        = 16'd600;
    over_speed = 1'b1;
    pulse_loss = 1'b0;

    recv_frame;
    t_f0 = t0;

    csum = 8'd0;
    for (i = 0; i < 10; i = i + 1) csum = csum + rx[i];   // 自己重算校验和

    $display("TP1 frame1 : hdr=%h %h (exp aa 55)  len=%h (exp 07)", rx[0], rx[1], rx[2]);
    $display("TP1 fields : turns=%h%h (exp fffd=-3)  pos=%h%h (exp 04d2=1234)  rpm=%h%h (exp 0258=600)",
             rx[3], rx[4], rx[5], rx[6], rx[7], rx[8]);
    $display("TP1 status : %h (exp 01)   sum=%h  calc=%h (exp 33)", rx[9], rx[10], csum);

    // ============ TP2：换数据 turns=+5, position=7, rpm=450, 丢脉冲=1 ============
    turns      =  16'sd5;
    position   =  12'd7;
    rpm        =  16'd450;
    over_speed =  1'b0;
    pulse_loss =  1'b1;

    recv_frame;
    t_f1 = t0;

    csum = 8'd0;
    for (i = 0; i < 10; i = i + 1) csum = csum + rx[i];

    $display("TP2 frame2 : hdr=%h %h (exp aa 55)  len=%h (exp 07)", rx[0], rx[1], rx[2]);
    $display("TP2 fields : turns=%h%h (exp 0005=+5)  pos=%h%h (exp 0007=7)  rpm=%h%h (exp 01c2=450)",
             rx[3], rx[4], rx[5], rx[6], rx[7], rx[8]);
    $display("TP2 status : %h (exp 02)   sum=%h  calc=%h (exp d7)", rx[9], rx[10], csum);

    // ============ TP3：两帧间隔应该 = 10 ms ============
    $display("TP3 period : %0d ns (expect 10000000 ns = 10 ms)", t_f1 - t_f0);

    $finish;
end

endmodule
