`timescale 1ns / 1ps
module tb_debounce;
reg  clk;
reg  rst;
reg  sig_in;
wire sig_out;

enc_debounce dut (.clk(clk), .rst(rst), .sig_in(sig_in), .sig_out(sig_out));

always #5 clk = ~clk;

initial begin
    clk = 0; rst = 1; sig_in = 0;
    #20 rst = 0;

    #80  sig_in = 1;
    #200 sig_in = 0;
    #200;
    $display("TP1 spike    : sig_out=%b  (expect 0)", sig_out);

    sig_in = 1;
    #1850;
    $display("TP2 counting : sig_out=%b  (expect 0)", sig_out);
    #300;
    $display("TP3 settled  : sig_out=%b  (expect 1)", sig_out);
    $finish;
end
endmodule
