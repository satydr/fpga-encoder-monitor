`timescale 1ns / 1ps
module tb_top_speed;

reg        clk, rst;
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

encoder_top dut (
    .clk(clk), .rst(rst), .enc_raw(enc_raw),
    .state(state), .dir(dir), .count(count), .err(err),
    .position(position), .turns(turns),
    .pulse_num(pulse_num), .rpm(rpm), .rpm_filtered(rpm_filtered)
);

always #5 clk = ~clk;

// 整链测速+滤波激励：每 41670 ns（= 4167 拍）推进一个正交相位。
// ⚠️ enc_raw[1:0] = {B, A}，正转序列是 00 → 01 → 11 → 10 → 00
integer k;
initial begin
    clk = 0; rst = 1; enc_raw = 3'b000;
    #20 rst = 0;
    #100;

    // 连续正转，跑满 2 个闸门（约 20 ms）：120 轮 x 4 边沿 = 480 个边沿
    for (k = 0; k < 120; k = k + 1) begin
        enc_raw[1:0] = 2'b01; #41670;
        enc_raw[1:0] = 2'b11; #41670;
        enc_raw[1:0] = 2'b10; #41670;
        enc_raw[1:0] = 2'b00; #41670;
    end

    #20000;   // 留余量：让最后一个脉冲穿过消抖，并等闸门 tick 锁存
    $display("TP6 chain : pulse_num=%0d rpm=%0d rpm_filtered=%0d", pulse_num, rpm, rpm_filtered);
    $display("            position=%0d turns=%0d count=%0d dir=%b", position, turns, count, dir);
    $finish;
end

endmodule
