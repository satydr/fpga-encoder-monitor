`timescale 1ns / 1ps
// =============================================================================
//  seg_scan.v  --  8 位数码管（2 组 x 4 位）动态扫描驱动
//
//  EGO1 数码管：**共阴，段选与位选都是高电平有效**（共阴公共极由三极管驱动，
//  FPGA 输出高 -> 三极管导通 -> 公共极接地）。
//
//  引脚分配按"每组 8 段 + 每组 4 位选"组织：
//      seg0[7:0] = {DP,G,F,E,D,C,B,A}   组0 段
//      dig0[3:0] = {K4,K3,K2,K1}        组0 位选
// =============================================================================
module seg_scan #(
    parameter integer SCAN_DIV = 50000          // 每位停留拍数；4 x 50000 = 2 ms 一轮 = 500 Hz
)(
    input  wire        clk,
    input  wire [15:0] val0,                    // 组0 显示值（4 位十六进制）
    input  wire [15:0] val1,                    // 组1 显示值（4 位十六进制）
    output reg  [7:0]  seg0,
    output reg  [3:0]  dig0,
    output reg  [7:0]  seg1,
    output reg  [3:0]  dig1
);

// ---------------------------------------------------------------- 扫描计数器
reg [16:0] div = 17'd0;
reg [1:0]  pos = 2'd0;

always @(posedge clk) begin
    if (div == SCAN_DIV - 1) begin
        div <= 17'd0;
        pos <= pos + 2'd1;                      // 0 -> 1 -> 2 -> 3 -> 0
    end else begin
        div <= div + 17'd1;
    end
end

// ---------------------------------------------------- 取出当前位要显示的 4 位数
wire [3:0] n0 = val0[{pos, 2'b00} +: 4];
wire [3:0] n1 = val1[{pos, 2'b00} +: 4];

// ---------------------------------------------------------------- 段码译码
// 共阴 + 高电平点亮；位序 seg[7:0] = {DP,G,F,E,D,C,B,A}
function [7:0] seg_of;
    input [3:0] n;
    begin
        case (n)
            4'h0 : seg_of = 8'h3F;
            4'h1 : seg_of = 8'h06;
            4'h2 : seg_of = 8'h5B;
            4'h3 : seg_of = 8'h4F;
            4'h4 : seg_of = 8'h66;
            4'h5 : seg_of = 8'h6D;
            4'h6 : seg_of = 8'h7D;
            4'h7 : seg_of = 8'h07;
            4'h8 : seg_of = 8'h7F;
            4'h9 : seg_of = 8'h6F;
            4'hA : seg_of = 8'h77;
            4'hB : seg_of = 8'h7C;
            4'hC : seg_of = 8'h39;
            4'hD : seg_of = 8'h5E;
            4'hE : seg_of = 8'h79;
            default : seg_of = 8'h71;           // F
        endcase
    end
endfunction

// ---------------------------------------------------------------- 输出
wire [3:0] dsel = 4'b0001 << pos;               // 位选高电平选通：pos=0 -> K1

always @(*) begin
    seg0 = seg_of(n0);
    seg1 = seg_of(n1);
    dig0 = dsel;
    dig1 = dsel;
end

endmodule
