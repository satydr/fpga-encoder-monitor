module enc_pos (
    input  wire        clk,
    input  wire        rst,
    input  wire        step_up,     // 正转一步（1 拍脉冲）
    input  wire        step_dn,     // 反转一步（1 拍脉冲）
    input  wire        z_sync,      // 同步+消抖后的 Z 相
    output wire        z_rise,      // ← 新增：Z 相上升沿（1 拍），给预警模块用
    output reg  [11:0] position,    // 圈内位置 0 ~ 2399
    output reg  signed [15:0] turns // 圈数（有符号，能表示反转）
);

parameter integer CPR = 2400;   // Counts Per Revolution = 600 PPR × 4 倍频

reg z_d;
always @(posedge clk) begin
    if (rst) z_d <= 1'b0;
    else     z_d <= z_sync;
end

assign z_rise = z_sync & ~z_d;  // ← 改动：原来是 wire，现在改成 assign

always @(posedge clk) begin
    if (rst) begin
        position <= 12'd0;
        turns    <= 16'sd0;
    end else if (step_up) begin
        if (position == CPR - 1) begin
            position <= 12'd0;          // 正转回绕：进位
            turns    <= turns + 16'sd1;
        end else begin
            position <= position + 12'd1;
        end
    end else if (step_dn) begin
        if (position == 12'd0) begin
            position <= CPR - 1;        // 反转回绕：借位
            turns    <= turns - 16'sd1;
        end else begin
            position <= position - 12'd1;
        end
    end else if (z_rise) begin
        position <= 12'd0;              // Z 相零位校准（不动 turns）
    end
end

endmodule
