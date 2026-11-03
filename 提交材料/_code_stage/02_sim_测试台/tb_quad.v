`timescale 1ns / 1ps
module tb_quad;
reg clk, rst, a, b, err_seen;
wire [1:0] state;
wire dir;
wire [15:0] count;
wire err;
wire step_up, step_dn;
reg [15:0] up_cnt, dn_cnt;

enc_quad dut (
    .clk(clk), .rst(rst), .a_sync(a), .b_sync(b),
    .state(state), .dir(dir), .count(count), .err(err),
    .step_up(step_up), .step_dn(step_dn)
);

always #5 clk = ~clk;
always @(posedge clk) if (err) err_seen <= 1'b1;
always @(posedge clk) begin
    if (step_up) up_cnt <= up_cnt + 16'd1;
    if (step_dn) dn_cnt <= dn_cnt + 16'd1;
end

initial begin
    clk = 0; rst = 1; a = 0; b = 0; err_seen = 0;
    up_cnt = 0; dn_cnt = 0;
    #20 rst = 0;

    #30 a = 1; #30 b = 1; #30 a = 0; #30 b = 0; #30;
    $display("TP1 forward: count=%0d dir=%b state=%b up=%0d dn=%0d", count, dir, state, up_cnt, dn_cnt);

    #30 b = 1; #30 a = 1; #30;
    $display("TP2 reverse: count=%0d dir=%b state=%b up=%0d dn=%0d", count, dir, state, up_cnt, dn_cnt);

    a = 0; b = 0; #30;
    $display("TP3 illegal: err_seen=%b count=%0d up=%0d dn=%0d", err_seen, count, up_cnt, dn_cnt);
    $finish;
end
endmodule
