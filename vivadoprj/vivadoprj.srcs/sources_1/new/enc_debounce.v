module enc_debounce (
    input  wire clk,
    input  wire rst,
    input  wire sig_in,
    output reg  sig_out
);
parameter CNT_MAX = 8'd199;
reg [7:0] cnt;
always @(posedge clk) begin
    if (rst) begin
        cnt     <= 8'd0;
        sig_out <= 1'b0;
    end else begin
        if (sig_in != sig_out) begin
            if (cnt == CNT_MAX) begin
                sig_out <= sig_in;
                cnt     <= 8'd0;
            end else begin
                cnt <= cnt + 8'd1;
            end
        end else begin
            cnt <= 8'd0;
        end
    end
end
endmodule
