module enc_speed (
    input  wire        clk,
    input  wire        rst,
    input  wire        step_up,      // 正转一步（1 拍脉冲，来自 enc_quad）
    input  wire        step_dn,      // 反转一步（1 拍脉冲，来自 enc_quad）
    output reg         tick,         // 闸门到顶脉冲（1 拍），供滤波器同步采样用  ← 新增
    output reg  [15:0] pulse_num,    // 本闸门内的脉冲数 M（给滤波/显示/调试用）
    output reg  [15:0] rpm           // 转速（转/分）= M x 2.5
);

// 闸门 10 ms @ 100 MHz = 1,000,000 拍
parameter integer GATE_MAX = 1000000;

reg  [19:0] gate_cnt;    // 闸门计时器（10^6 需要 20 位，2^20 = 1048576）
reg  [15:0] pulse_cnt;   // 闸门内脉冲累计

wire        tick_now = (gate_cnt == GATE_MAX - 1);   // 闸门到顶，只有 1 拍（组合）
// M x 2.5 = (M x 5) / 2。+1 再右移 = 四舍五入，避免 floor 造成的系统性低估：
    // 不修时 M 为奇数会丢掉 0.5，与后级 enc_filter 的截断叠加后，
    // 会导致极低转速（1 转/分）直接读成 0。
    wire [31:0] rpm_calc = (pulse_cnt * 32'd5 + 32'd1) >> 1;

always @(posedge clk) begin
    if (rst) begin
        gate_cnt  <= 20'd0;
        pulse_cnt <= 16'd0;
        pulse_num <= 16'd0;
        rpm       <= 16'd0;
        tick      <= 1'b0;
    end else begin
        tick <= tick_now;             // ← 新增：延后一拍输出，此时 rpm 才刚变成新值
        if (tick_now) begin
            gate_cnt  <= 20'd0;           // 闸门重新开始
            pulse_cnt <= 16'd0;           // 计数清零
            pulse_num <= pulse_cnt;       // 关键：先把上一窗口的结果"锁存"下来
            rpm       <= rpm_calc[15:0];  // 再换算成转速
        end else begin
            gate_cnt <= gate_cnt + 20'd1;
            if (step_up | step_dn) pulse_cnt <= pulse_cnt + 16'd1;
        end
    end
end

endmodule
