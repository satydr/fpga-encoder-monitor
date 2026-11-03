`timescale 1ns / 1ps
// =============================================================================
//  cmd_rx.v  --  上位机控制帧解析（把收到的字节流变成"改阈值"的命令）
//
//  控制帧格式（上位机 -> FPGA），6 字节定长：
//      [0] 0xAA      帧头第 1 字节
//      [1] 0x55      帧头第 2 字节
//      [2] CMD       指令：0x4E = 'N' 改超速阈值
//                       0x50 = 'P' 改丢脉冲容差
//                       0x43 = 'C' 清除两个报警
//      [3] D_H       参数高字节
//      [4] D_L       参数低字节
//      [5] SUM       校验和 = 指令+参数两字节低 8 位求和
//
//  ⚠️ 2026-10-05 修正一个真 bug：
//     原来 S_SYNC 只吃 1 个字节，见到 0xAA 或 0x55 就直接进 S_CMD。
//     结果发 AA 55 43 00 00 43 时，0x55 被当成了指令字节，
//     后面全部错位，校验和必然对不上 —— 所有命令都被丢弃。
//     现在拆成 S_H1（等 AA）和 S_H2（等 55）两步，AA 55 必须连续出现。
// =============================================================================
module cmd_rx (
    input  wire        clk,
    input  wire        rst,

    input  wire        rx_valid,     // 来自 uart_rx
    input  wire [7:0]  rx_data,

    // ---- 参数寄存器（改了立刻生效）----
    output reg  [15:0] speed_limit,  // 超速阈值（转/分）
    output reg  [15:0] z_gap_tol,    // Z 相周期容差（计数）
    output reg         clr_pulse,    // 1 拍脉冲：上位机要求清报警
    output reg         ack_pulse,    // 1 拍脉冲：命令已生效

    output reg  [7:0]  last_cmd,     // 最近一次成功执行的指令（调试用）
    output reg  [15:0] last_param
);

localparam [2:0] S_H1   = 3'd0,   // 等帧头第 1 字节 AA
                 S_H2   = 3'd1,   // 等帧头第 2 字节 55
                 S_CMD  = 3'd2,   // 收指令
                 S_DH   = 3'd3,   // 收参数高字节
                 S_DL   = 3'd4,   // 收参数低字节
                 S_SUM  = 3'd5,   // 收校验和
                 S_CK   = 3'd6;   // 校验并执行

reg [2:0] st;
reg [7:0] b_cmd, b_dh, b_dl, b_sum;

wire [7:0] calc = b_cmd + b_dh + b_dl;   // 校验和 = 指令+参数两字节

always @(posedge clk) begin
    if (rst) begin
        st         <= S_H1;
        b_cmd      <= 8'd0;
        b_dh       <= 8'd0;
        b_dl       <= 8'd0;
        b_sum      <= 8'd0;
        speed_limit<= 16'd700;
        z_gap_tol  <= 16'd200;
        clr_pulse  <= 1'b0;
        ack_pulse  <= 1'b0;
        last_cmd   <= 8'd0;
        last_param <= 16'd0;
    end else begin
        clr_pulse <= 1'b0;
        ack_pulse <= 1'b0;

        case (st)
        // --------------------------------------------- 等帧头第 1 字节 AA
        S_H1: begin
            if (rx_valid) begin
                if (rx_data == 8'hAA) st <= S_H2;   // 只认 AA，别的丢掉
            end
        end

        // --------------------------------------------- 等帧头第 2 字节 55
        S_H2: begin
            if (rx_valid) begin
                if (rx_data == 8'h55) st <= S_CMD;  // AA 55 必须成对
                else if (rx_data == 8'hAA) st <= S_H2; // 连续 AA，继续等 55
                else st <= S_H1;                     // 帧头错，重新找
            end
        end

        S_CMD: begin
            if (rx_valid) begin
                b_cmd <= rx_data;
                st    <= S_DH;
            end
        end

        S_DH: begin
            if (rx_valid) begin
                b_dh <= rx_data;
                st   <= S_DL;
            end
        end

        S_DL: begin
            if (rx_valid) begin
                b_dl <= rx_data;
                st   <= S_SUM;
            end
        end

        S_SUM: begin
            if (rx_valid) begin
                b_sum <= rx_data;
                st    <= S_CK;
            end
        end

        // ------------------------------------------- 校验并执行
        S_CK: begin
            if (b_sum == calc) begin
                ack_pulse   <= 1'b1;
                last_cmd    <= b_cmd;
                last_param  <= {b_dh, b_dl};
                case (b_cmd)
                    8'h4E: speed_limit <= {b_dh, b_dl};   // 'N'
                    8'h50: z_gap_tol  <= {b_dh, b_dl};   // 'P'
                    8'h43: clr_pulse  <= 1'b1;            // 'C'
                    default: ;
                endcase
            end
            st <= S_H1;
        end

        default: st <= S_H1;
        endcase
    end
end

endmodule
