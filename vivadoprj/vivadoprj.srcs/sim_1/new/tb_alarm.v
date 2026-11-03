`timescale 1ns / 1ps
module tb_alarm;

reg  clk, rst, clr;
reg  [15:0] rpm;
reg  step_up, step_dn, z_rise, err;
wire over_speed, pulse_loss;

enc_alarm dut (
    .clk(clk), .rst(rst), .clr(clr),
    .rpm(rpm),
    .step_up(step_up), .step_dn(step_dn),
    .z_rise(z_rise), .err(err),
    .over_speed(over_speed), .pulse_loss(pulse_loss)
);

always #5 clk = ~clk;

integer i;

task one_step; begin
    @(negedge clk) step_up = 1'b1;
    @(negedge clk) step_up = 1'b0;
end endtask

task give_z; begin
    @(negedge clk) z_rise = 1'b1;
    @(negedge clk) z_rise = 1'b0;
end endtask

task do_clr; begin
    @(negedge clk) clr = 1'b1;
    @(negedge clk) clr = 1'b0;
end endtask

initial begin
    clk = 0; rst = 1; clr = 0; rpm = 16'd600;
    step_up = 0; step_dn = 0; z_rise = 0; err = 0;
    #20 rst = 0;
    #20;

    // ---- TP1：正常 600 转/分，走满一圈 2400 步 + 1 个 Z ----
    for (i = 0; i < 2400; i = i + 1) one_step;
    give_z;
    @(negedge clk);
    $display("TP1 normal   : over=%b loss=%b (expect 0 0)", over_speed, pulse_loss);

    // ---- TP2：超速 800 -> over 锁存 ----
    rpm = 16'd800;
    #30;
    $display("TP2 overspeed: over=%b loss=%b (expect 1 0)", over_speed, pulse_loss);

    // ---- TP3：降速回 600，但没清除 -> 锁存保持（这就是"留证据"）----
    rpm = 16'd600;
    #30;
    $display("TP3 latched  : over=%b loss=%b (expect 1 0)", over_speed, pulse_loss);

    // ---- TP4：clr 清除 -> over 归零 ----
    do_clr;
    @(negedge clk);
    $display("TP4 cleared  : over=%b loss=%b (expect 0 0)", over_speed, pulse_loss);

    // ---- TP5：Z 相丢失：转 3000 步不来 Z（> 2400+200）-> loss 锁存 ----
    for (i = 0; i < 3000; i = i + 1) one_step;
    @(negedge clk);
    $display("TP5 z-lost   : over=%b loss=%b (expect 0 1)", over_speed, pulse_loss);

    // ---- TP6：Z 周期恢复，但没清除 -> loss 仍锁存 ----
    give_z;
    #30;
    $display("TP6 restore  : over=%b loss=%b (expect 0 1)", over_speed, pulse_loss);

    // ---- TP7：clr 清除 -> loss 归零 ----
    do_clr;
    @(negedge clk);
    $display("TP7 cleared  : over=%b loss=%b (expect 0 0)", over_speed, pulse_loss);

    // ---- TP8：再正常走一圈 -> 不报警（确认清除后不会误触发）----
    for (i = 0; i < 2400; i = i + 1) one_step;
    give_z;
    @(negedge clk);
    $display("TP8 healthy  : over=%b loss=%b (expect 0 0)", over_speed, pulse_loss);

    // ---- TP9：err 脉冲（A/B 非法跳变）-> loss 锁存 ----
    @(negedge clk) err = 1'b1;
    @(negedge clk) err = 1'b0;
    @(negedge clk);
    $display("TP9 err      : over=%b loss=%b (expect 0 1)", over_speed, pulse_loss);

    $finish;
end

endmodule
