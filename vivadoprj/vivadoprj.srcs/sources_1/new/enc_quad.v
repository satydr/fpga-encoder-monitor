module enc_quad (
    input  wire       clk,
    input  wire       rst,
    input  wire       a_sync,
    input  wire       b_sync,
    output reg  [1:0] state,
    output reg        dir,
    output reg [15:0] count,
    output reg        err,
    output reg        step_up,      // 新增：正转一步，1 拍脉冲
    output reg        step_dn       // 新增：反转一步，1 拍脉冲
);

wire [1:0] cur = {a_sync, b_sync};
reg  [1:0] prev;

always @(posedge clk) begin
    if (rst) begin
        prev  <= 2'b00;
        state <= 2'b00;
        dir   <= 1'b0;
        count <= 16'd0;
        err   <= 1'b0;
        step_up <= 1'b0;
        step_dn <= 1'b0;
    end else begin
        prev  <= cur;
        state <= cur;

        err     <= 1'b0;          // 三个事件信号先无条件清零
        step_up <= 1'b0;
        step_dn <= 1'b0;

        case ({prev, cur})
            4'b0010, 4'b1011, 4'b1101, 4'b0100: begin
                count   <= count + 16'd1;
                dir     <= 1'b0;
                step_up <= 1'b1;   // 正转一步
            end
            4'b0001, 4'b0111, 4'b1110, 4'b1000: begin
                count   <= count - 16'd1;
                dir     <= 1'b1;
                step_dn <= 1'b1;   // 反转一步
            end
            4'b0011, 4'b1100, 4'b0110, 4'b1001: begin
                err     <= 1'b1;   // 非法跳变，不产生步进
            end
            default: ;
        endcase
    end
end

endmodule
