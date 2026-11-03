`timescale 1ns / 1ps
module tb_pos;
reg  clk;
reg  rst;
reg  step_up, step_dn, z_sync;
wire [11:0] position;
wire signed [15:0] turns;

enc_pos dut (
    .clk(clk), .rst(rst),
    .step_up(step_up), .step_dn(step_dn), .z_sync(z_sync),
    .position(position), .turns(turns)
);

always #5 clk = ~clk;

integer i;

task do_up; begin @(negedge clk) step_up = 1'b1; @(negedge clk) step_up = 1'b0; end endtask
task do_dn; begin @(negedge clk) step_dn = 1'b1; @(negedge clk) step_dn = 1'b0; end endtask
task do_z;  begin @(negedge clk) z_sync  = 1'b1; @(negedge clk) z_sync  = 1'b0; end endtask

initial begin
    clk = 0; rst = 1; step_up = 0; step_dn = 0; z_sync = 0;
    #20 rst = 0;

    for (i = 0; i < 2400; i = i + 1) do_up;   // 正转整一圈
    @(posedge clk);
    $display("TP1 one turn fwd : position=%0d turns=%0d (expect 0 1)", position, turns);

    for (i = 0; i < 100; i = i + 1) do_up;    // 再正转 100 步
    @(posedge clk);
    $display("TP2 +100 steps   : position=%0d turns=%0d (expect 100 1)", position, turns);

    for (i = 0; i < 200; i = i + 1) do_dn;    // 反转 200 步，跨过 0
    @(posedge clk);
    $display("TP3 200 steps dn : position=%0d turns=%0d (expect 2300 0)", position, turns);

    for (i = 0; i < 2400; i = i + 1) do_dn;   // 再倒转整一圈
    @(posedge clk);
    $display("TP4 one turn rev : position=%0d turns=%0d (expect 2300 -1)", position, turns);

    for (i = 0; i < 37; i = i + 1) do_up;     // 正转 37 步，让位置偏离零点
    @(posedge clk);
    $display("TP5 before Z     : position=%0d turns=%0d (expect 2337 -1)", position, turns);

    do_z;                                     // 给一个 Z 相脉冲
    @(posedge clk);
    $display("TP6 after  Z     : position=%0d turns=%0d (expect 0 -1)", position, turns);

    $finish;
end
endmodule
