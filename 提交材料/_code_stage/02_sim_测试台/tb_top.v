`timescale 1ns / 1ps
module tb_top;
reg        clk;
reg        rst;
reg  [2:0] enc_raw;
wire [1:0] state;
wire       dir;
wire [15:0] count;
wire       err;
wire [11:0] position;
wire signed [15:0] turns;
reg        err_seen;

encoder_top dut (
    .clk(clk), .rst(rst), .enc_raw(enc_raw),
    .state(state), .dir(dir), .count(count), .err(err),
    .position(position), .turns(turns)
);

always #5 clk = ~clk;
always @(posedge clk) if (err) err_seen <= 1'b1;

initial begin
    clk = 0; rst = 1; enc_raw = 3'b000; err_seen = 0;
    #20 rst = 0;
    #2500;

    enc_raw[1:0] = 2'b11; #80; enc_raw[1:0] = 2'b00;
    #2500;
    $display("TP0 glitch  : position=%0d turns=%0d count=%0d err_seen=%b (expect 0 0 0 0)", position, turns, count, err_seen);

    #2500 enc_raw[0] = 1;
    #2500 enc_raw[1] = 1;
    #2500 enc_raw[0] = 0;
    #2500 enc_raw[1] = 0;
    #2500;
    $display("TP1 forward : position=%0d turns=%0d count=%0d dir=%b (expect 4 0 4 0)", position, turns, count, dir);

    #2500 enc_raw[1] = 1;
    #2500 enc_raw[0] = 1;
    #2500;
    $display("TP2 reverse : position=%0d turns=%0d count=%0d dir=%b (expect 2 0 2 1)", position, turns, count, dir);

    enc_raw[1:0] = 2'b00;
    #2500;
    $display("TP3 illegal : position=%0d turns=%0d err_seen=%b (expect 2 0 1)", position, turns, err_seen);

    enc_raw[2] = 1;
    #2500;
    $display("TP4 z-pulse : position=%0d turns=%0d (expect 0 0)", position, turns);
    $finish;
end
endmodule
