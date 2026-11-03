`timescale 1ns / 1ps
// =============================================================================
//  enc_alarm.v  --  超速 / 丢脉冲预警（两级都锁存，clr 清除）
//
//  ⚠️ 2026-10-05 改动 1：阈值从【编译期常量】改成【运行时寄存器】
//     原来：parameter integer SPEED_MAX = 700;  换电机就得重新综合、重新下载
//     现在：speed_limit / z_gap_tol 由上位机经 UART 下发，改完立刻生效
//          上电默认值仍由 parameter 给（700 / 200），行为与旧版完全一致
//
//  ⚠️ 2026-10-05 改动 2：修"清完立刻又报警"的竞争
//     原来 clr 是 1 拍脉冲，clear 生效后同一拍 over_now/loss_now 可能仍为真，
//     于是报警在同一拍被重新锁存 —— 表现为"远程清报警有时灵有时不灵"，
//     真机复测时 10~150 帧不定，纯属随机竞争。
//     现在改成【边沿触发的单次清】：clr 拉高时 disarm=1，
//     之后即使 over_now 仍为真也不再置位，直到条件消失才重新武装。
//     这样"人工确认"语义完整：清完不会因为故障还在就立刻重新报警，
//     而是真的得等故障消失（rpm 降下来 / Z 相周期恢复正常）才可能再报。
//
//  这样改还有个好处：按键清报警（S0）也一并受益，不再有"按了没反应"的情况。
// =============================================================================
module enc_alarm #(
    parameter integer SPEED_MAX_INIT = 700,  // 上电默认超速阈值（转/分）
    parameter integer Z_TOL_INIT    = 200   // 上电默认 Z 相周期容差（计数）
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clr,          // 报警清除（按键，高有效）
    input  wire        remote_clr,   // 上位机远程清除（cmd_rx 下发，高 1 拍）
    input  wire [15:0] speed_limit,  // 超速阈值，来自寄存器
    input  wire [15:0] z_gap_tol,    // Z 相容差，来自寄存器
    input  wire [15:0] rpm,          // 滤波后的转速（来自 enc_filter）
    input  wire        step_up,      // 正转一步（来自 enc_quad）
    input  wire        step_dn,      // 反转一步（来自 enc_quad）
    input  wire        z_rise,       // Z 相上升沿（来自 enc_pos，1 拍）
    input  wire        err,          // A/B 非法跳变（来自 enc_quad，1 拍）
    output reg         over_speed,   // 超速报警（锁存）
    output reg         pulse_loss,   // 丢脉冲报警（锁存）
    output wire [15:0] speed_limit_o,// 回读当前阈值（PC 可查询）
    output wire [15:0] z_tol_o
);

parameter integer CPR = 2400;        // 每圈计数（600 PPR 四倍频）

reg [15:0] sp_limit;                // 本地副本：上电装载，之后由外部寄存器驱动
reg [15:0] z_tol;
reg [15:0] sp_limit_r;              // 单拍延迟，等价于 uart_frame 的 S_SNAP
reg [15:0] z_tol_r;

assign speed_limit_o = sp_limit;
assign z_tol_o       = z_tol;

reg        z_seen;                  // 是否已见过第一个 Z（见过之前不做周期判定）
reg [15:0] z_gap_cnt;               // 自上个 Z 以来的步进计数

// 与参数寄存器同步（单拍延迟，避免与写寄存器同拍产生毛刺）
always @(posedge clk) begin
    sp_limit_r <= sp_limit;
    z_tol_r    <= z_tol;
end

// 上电装载 / 远程改写
always @(posedge clk) begin
    if (rst) begin
        sp_limit <= SPEED_MAX_INIT[15:0];
        z_tol    <= Z_TOL_INIT[15:0];
    end else begin
        sp_limit <= speed_limit;
        z_tol    <= z_gap_tol;
    end
end

// 判超速用延迟一拍的阈值，保证与 sp_limit 的更新对齐
wire over_now = (rpm > sp_limit_r);
wire loss_now = z_seen & (z_gap_cnt > (CPR[15:0] + z_tol_r));
wire any_cond = over_now | loss_now | err;

// ---- 解除武装：人工确认后，故障条件真的消失前不再重新报警 ----
reg ov_disarm, pl_disarm;
wire clr_all = clr | remote_clr;

always @(posedge clk) begin
    if (rst) begin
        ov_disarm <= 1'b0;
        pl_disarm <= 1'b0;
    end else if (clr_all) begin
        // 人工确认后【保持解除武装】—— 这一拍不能置 0！
        // 因为清完的下一拍若条件仍为真，立刻就会重新锁存，等于清了个寂寞。
        // 只有条件真的消失了（见下）才重新武装。
        ov_disarm <= 1'b1;
        pl_disarm <= 1'b1;
    end else begin
        // 条件消失 -> 重新武装（下次真出故障还能报）
        if (!over_now) ov_disarm <= 1'b0;
        if (!loss_now) pl_disarm <= 1'b0;
    end
end

always @(posedge clk) begin
    if (rst) begin
        z_seen     <= 1'b0;
        z_gap_cnt  <= 16'd0;
        over_speed <= 1'b0;
        pulse_loss <= 1'b0;
    end else if (clr_all) begin
        // ---- 人工确认：清报警 + 同时解除武装，两件事必须分开赋值 ----
        over_speed <= 1'b0;
        pulse_loss <= 1'b0;
    end else begin
        if (over_now && !ov_disarm) over_speed <= 1'b1;
        if (loss_now && !pl_disarm) pulse_loss <= 1'b1;
        if (err      && !pl_disarm) pulse_loss <= 1'b1;   // 非法跳变也是丢脉冲的证据
    end

    // ---- Z 相周期计数器 ----
    if (z_rise) begin
        z_seen    <= 1'b1;
        z_gap_cnt <= 16'd0;
    end else if (step_up | step_dn) begin
        z_gap_cnt <= z_gap_cnt + 16'd1;
    end
end

endmodule
