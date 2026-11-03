`timescale 1ns / 1ps
// =============================================================================
//  uart_rx.v  --  UART 接收器（异步，115200 8N1）
//
//  为什么接收比发送难：
//      发送端我主动拉起始位，节拍自己定，不会错；
//      接收端不知道数据什么时候来，必须靠"高->低的跌落"判断有人开始发。
//
//  做法：
//   1. 平时盯住 rx，检测到 1->0 的跌落就算抓到起始位
//   2. 再等 1.5 个位时间才采第一个数据位 —— 居中采样，抗偏移
//   3. 之后每隔 1 个位时间采一次，共采 8 位
//   4. 最后采停止位，必须是 1，否则认为这一帧是假的（framing error）
//
//  115200 bps @ 100 MHz：
//      1 位 = 1e9 / 115200 = 8680.5 ns = 868 个时钟（10 ns）
//      DIV = 868；抓边沿后先等 DIV/2 = 434 拍，再等 434 拍，合计 1.5 位
// =============================================================================
module uart_rx #(
    parameter integer DIV = 868            // 一个位时间的时钟数（100 MHz / 115200 = 868）
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,                 // 串行数据线（空闲为高）
    output reg        rx_valid,           // 1 拍脉冲：收到一个完整字节
    output reg  [7:0] rx_data,            // 收到的字节
    output reg        rx_frame_err        // 1 拍脉冲：停止位不为 1（帧错误）
);

localparam [1:0] S_IDLE = 2'd0,   // 等待起始位
                 S_HALF = 2'd1,   // 已抓到起始位，正在数半个位
                 S_DATA = 2'd2,   // 采 8 个数据位
                 S_STOP = 2'd3;   // 采停止位

reg [1:0] st;
reg       rx_d;              // 上一拍的 rx，用来找边沿
reg [15:0] cnt;              // 计数器
reg [2:0]  bit_idx;          // 已采了几个数据位
reg [7:0]  sh;               // 接收移位寄存器

// 抓起始位：上一拍是 1，这一拍是 0
wire falling = rx_d & ~rx;

always @(posedge clk) begin
    if (rst) begin
        st          <= S_IDLE;
        rx_d        <= 1'b1;
        cnt         <= 16'd0;
        bit_idx     <= 3'd0;
        sh          <= 8'd0;
        rx_data     <= 8'd0;
        rx_valid    <= 1'b0;
        rx_frame_err<= 1'b0;
    end else begin
        rx_d         <= rx;
        rx_valid     <= 1'b0;
        rx_frame_err <= 1'b0;

        case (st)
        // ---------------------------------------------------------- 等起始位
        S_IDLE: begin
            if (falling) begin
                st  <= S_HALF;
                cnt <= (DIV >> 1) - 1;     // 先等半个位
            end
        end

        // ---- 半个位走完，再等半个位，合计 1.5 位后才采第一个数据位 ----
        S_HALF: begin
            if (cnt == 16'd0) begin
                st   <= S_DATA;
                cnt  <= DIV - 1;
            end else cnt <= cnt - 16'd1;
        end

        // ------------------------------------------------------ 采 8 个数据位
        S_DATA: begin
            if (cnt == 16'd0) begin
                sh[bit_idx] <= rx;          // 位序 = 位号，LSB 先来先放 bit0
                if (bit_idx == 3'd7) begin
                    st  <= S_STOP;
                    cnt <= DIV - 1;
                end else begin
                    cnt     <= DIV - 1;
                    bit_idx <= bit_idx + 3'd1;
                end
            end else cnt <= cnt - 16'd1;
        end

        // -------------------------------------------------------- 采停止位
        S_STOP: begin
            if (cnt == 16'd0) begin
                if (rx !== 1'b1) rx_frame_err <= 1'b1;
                rx_data  <= sh;
                rx_valid <= 1'b1;
                st       <= S_IDLE;
                cnt      <= 16'd0;
                bit_idx  <= 3'd0;
            end else cnt <= cnt - 16'd1;
        end

        default: st <= S_IDLE;
        endcase
    end
end

endmodule
