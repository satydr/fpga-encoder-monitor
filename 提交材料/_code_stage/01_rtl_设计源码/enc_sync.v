module enc_sync (
    input  wire       clk,
    input  wire [2:0] enc_raw,
    output reg  [2:0] meta,
    output reg  [2:0] synced
);
always @(posedge clk) begin
    meta   <= enc_raw;
    synced <= meta;
end
endmodule
