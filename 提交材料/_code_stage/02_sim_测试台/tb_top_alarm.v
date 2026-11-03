`timescale 1ns / 1ps
module tb_top_alarm;

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

encoder_top dut (
    .clk(clk), .rst(rst), .clr(clr), .enc_raw(enc_raw),
    .state(state), .dir(dir), .count(count), .err(err),
    .position(position), .turns(turns),
    .pulse_num(pulse_num), .rpm(rpm), .rpm_filtered(rpm_filtered),
    .over_speed(over_speed), .pulse_loss(pulse_loss)
);

always #5 clk = ~clk;

// 走 n 个正交周期（每周期 = 4 个计数），每个计数花 t 拍。
//   t = 4167  -> 600 转/分（24000 计数/秒）
//   t = 3125  -> 800 转/分（32000 计数/秒）
// ⚠️ enc_raw[1:0] = {B, A}，正转序列 00 -> 01 -> 11 -> 10 -> 00
task fwd_cycles;
    input integer n;
    input integer t;
    integer j;
    begin
        for (j = 0; j < n; j = j + 1) begin
            enc_raw[1:0] = 2'b01; #(t*10);
            enc_raw[1:0] = 2'b11; #(t*10);
            enc_raw[1:0] = 2'b10; #(t*10);
            enc_raw[1:0] = 2'b00; #(t*10);
        end
    end
endtask

// 给一个真实宽度的 Z 脉冲（3 us，远大于消抖 2 us 窗口；真实 Z 宽约 41 us）
task give_z;
    begin
        enc_raw[2] = 1'b1; #3000;
        enc_raw[2] = 1'b0; #3000;
    end
endtask

initial begin
    clk = 0; rst = 1; clr = 0; enc_raw = 3'b000;
    #20 rst = 0;

    // ============== 场景 A：真实信号上制造超速（800 转/分）==============
    give_z;                 // 先给一个 Z，让 z_seen = 1（否则丢脉冲判据被门控关着）
    fwd_cycles(400, 3125);  // 800 转/分 跑 50 ms = 1600 个计数
    #100000;
    $display("TPA overspeed : over=%b loss=%b rpm=%0d rpm_f=%0d count=%0d pos=%0d turns=%0d",
             over_speed, pulse_loss, rpm, rpm_filtered, count, position, turns);

    // ============== 场景 B：真实信号上制造丢脉冲（Z 整圈不来）==============
    rst = 1; #20 rst = 0;   // 复位，清掉锁存
    give_z;                 // 给一个 Z 作为周期基准 → z_seen = 1
    fwd_cycles(675, 4167);  // 600 转/分 跑 112.5 ms = 2700 个计数，全程不再给 Z
    #100000;
    $display("TPB z-lost    : over=%b loss=%b rpm=%0d rpm_f=%0d count=%0d pos=%0d turns=%0d",
             over_speed, pulse_loss, rpm, rpm_filtered, count, position, turns);

    $finish;
end

endmodule
