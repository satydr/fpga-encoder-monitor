module uart_tx (
    input  wire       clk,        // 100 MHz
    input  wire       rst,
    input  wire       tx_start,   // 1 拍脉冲：启动一次发送
    input  wire [7:0] tx_data,    // 要发送的字节
    output reg        tx,         // 串行输出线（空闲为高电平）
    output reg        tx_busy     // 1 = 正在发送
);

// 波特率 115200 @ 100 MHz  ->  分频系数 = 100_000_000 / 115200 = 868.05
parameter integer BAUD_DIV = 868;

reg [9:0] div_cnt;    // 0 ~ 867，10 位
reg [3:0] bit_cnt;    // 0 ~ 10，记录已完成多少个"位周期"
reg [9:0] shifter;    // {停止位, 8 数据位, 起始位}

wire div_tick = (div_cnt == BAUD_DIV - 1);

always @(posedge clk) begin
    if (rst) begin
        div_cnt  <= 10'd0;
        bit_cnt  <= 4'd0;
        shifter  <= 10'h3FF;      // 全 1 = 空闲
        tx       <= 1'b1;
        tx_busy  <= 1'b0;
    end else if (!tx_busy) begin
        if (tx_start) begin
            shifter <= {1'b1, tx_data, 1'b0};   // 停止位 + 数据 + 起始位
            bit_cnt <= 4'd0;
            div_cnt <= 10'd0;
            tx_busy <= 1'b1;
        end else begin
            tx <= 1'b1;                         // 空闲保持高电平
        end
    end else begin
        if (div_tick) begin
            div_cnt <= 10'd0;
            tx      <= shifter[0];              // 先发最低位（LSB first）
            shifter <= {1'b1, shifter[9:1]};
            if (bit_cnt == 4'd10) begin
                tx_busy <= 1'b0;                // 停止位整个位周期走完才释放
            end else begin
                bit_cnt <= bit_cnt + 4'd1;
            end
        end else begin
            div_cnt <= div_cnt + 10'd1;
        end
    end
end

endmodule
