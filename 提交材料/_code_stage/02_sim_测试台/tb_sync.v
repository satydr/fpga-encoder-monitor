`timescale 1ns / 1ps

module tb_sync;

reg        clk;
reg  [2:0] enc_raw;
wire [2:0] meta;
wire [2:0] synced;

enc_sync dut (
    .clk     (clk),
    .enc_raw (enc_raw),
    .meta    (meta),
    .synced  (synced)
);

always #5 clk = ~clk;

initial begin
    clk     = 0;
    enc_raw = 3'b000;
    #13 enc_raw[0] = 1;
    #17 enc_raw[1] = 1;
    #23 enc_raw[2] = 1;
    #40 $finish;
end

endmodule
