module enc_filter (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick,       // 闸门到顶脉冲（来自 enc_speed，10 ms 一次）
    input  wire [15:0] rpm_in,     // 未滤波的转速（来自 enc_speed）
    output reg  [15:0] rpm_avg     // 4 点滑动平均后的转速
);

// 3 级移位寄存器：保存最近 3 个历史值（s0 最新、s2 最旧）
reg [15:0] s0, s1, s2;

// 窗口 = 当前值 + 3 个历史值，共 4 点
// 最大 4 x 65535 = 262140，需要 18 位 (2^18 = 262144)
wire [17:0] sum = rpm_in + s0 + s1 + s2;

always @(posedge clk) begin
    if (rst) begin
        s0 <= 16'd0;
        s1 <= 16'd0;
        s2 <= 16'd0;
        rpm_avg <= 16'd0;
    end else if (tick) begin
        s2 <= s1;          // 整体右移，最旧的被挤出去
        s1 <= s0;
        s0 <= rpm_in;      // 新数据进队头
        rpm_avg <= (sum + 18'd2) >> 2;   // 除以 4 并四舍五入（+2 = 半个除数）
    end
end

endmodule
