// I2C 主机（只发不收），100 kHz @ 100 MHz 系统时钟
// 字节流接口：一次 start 可以连续发多个字节，每字节后从机回一个 ACK
module i2c_master (
    input  wire       clk,        // 100 MHz
    input  wire       rst,
    input  wire       start,      // 1 拍脉冲：发起一次传输
    input  wire [6:0] dev_addr,   // 7 位从机地址（SSD1306 = 7'h3C）
    input  wire [7:0] wr_data,    // 当前要发的字节
    input  wire       wr_valid,   // 1 = 本字节之后还有字节要发；0 = 本字节是最后一个
    output reg        wr_next,    // 1 拍脉冲：请把下一个字节放到 wr_data 上
    output reg        busy,       // 1 = 传输进行中
    output reg        done,       // 1 拍脉冲：传输结束（STOP 之后）
    output reg        ack_err,    // 1 拍脉冲：从机没应答（NACK）
    output wire       scl,
    inout  wire       sda
);

// 100 MHz / 100 kHz = 1000 分频；一个 SCL 周期 = 1000 拍 = 10 us
parameter DIV  = 1000;
parameter HALF = DIV / 2;        // 500：半个 SCL 周期
parameter Q    = DIV / 4;        // 250：周期内的 1/4 点

localparam S_IDLE  = 3'd0,
           S_START = 3'd1,
           S_LOAD  = 3'd2,
           S_LOW   = 3'd3,
           S_HIGH  = 3'd4,
           S_STOPA = 3'd5,
           S_STOPB = 3'd6,
           S_STOPC = 3'd7;

// 开漏输出：只能拉低，不能拉高（高电平靠外部上拉电阻）
reg scl_l;      // 1 = 拉低 SCL
reg sda_l;      // 1 = 拉低 SDA
assign scl = scl_l ? 1'b0 : 1'bz;
assign sda = sda_l ? 1'b0 : 1'bz;
wire sda_in = sda;               // 读回线上真实电平（ACK 用）

reg [9:0] cnt;       // 半个 SCL 周期内的计数
reg [3:0] bit_idx;   // 0~7 = 数据位，8 = ACK 位
reg [7:0] sh;        // 发送移位寄存器，先发 sh[7]
reg       ack_ok;    // 采到的 ACK 是否有效
reg       wvalid_r;  // 装载字节时锁存的 wr_valid：表示"本字节之后还有没有"
reg [2:0] st;

always @(posedge clk) begin
    if (rst) begin
        st <= S_IDLE; cnt <= 10'd0; bit_idx <= 4'd0;
        sh <= 8'hFF; scl_l <= 1'b0; sda_l <= 1'b0;
        busy <= 1'b0; done <= 1'b0; ack_err <= 1'b0;
        wr_next <= 1'b0; ack_ok <= 1'b0; wvalid_r <= 1'b0;
    end else begin
        wr_next <= 1'b0;          // 默认只维持 1 拍
        done    <= 1'b0;
        ack_err <= 1'b0;
        case (st)

        // 总线空闲：SCL 与 SDA 都被上拉为高
        S_IDLE: begin
            scl_l <= 1'b0; sda_l <= 1'b0; busy <= 1'b0;
            if (start) begin
                sh       <= {dev_addr, 1'b0};  // 地址字节 + 写位(0)
                bit_idx  <= 4'd0;
                cnt      <= 10'd0;
                sda_l    <= 1'b1;              // SCL 高时拉低 SDA = START 条件
                wvalid_r <= wr_valid;          // 地址字节后面还有没有数据字节
                busy     <= 1'b1;
                st       <= S_START;
            end
        end

        // START 保持：SDA 低电平维持半个周期
        S_START: begin
            if (cnt == HALF - 1) begin
                cnt   <= 10'd0;
                scl_l <= 1'b1;                 // 拉低 SCL，开始第一位
                st    <= S_LOW;
            end else begin
                cnt <= cnt + 10'd1;
            end
        end

        // 取数：给上层留一拍时间换字节（收到 wr_next 后才更新 wr_data）
        S_LOAD: begin
            sh       <= wr_data;
            wvalid_r <= wr_valid;              // 与这个字节配套的"还有没有"，发完它时才用
            st       <= S_LOW;
        end

        // SCL 低电平：在 1/4 点改数据（SCL 高电平时数据必须稳定）
        S_LOW: begin
            if (cnt == Q) begin
                if (bit_idx == 4'd8) sda_l <= 1'b0;     // ACK 位：释放 SDA，交给从机
                else                 sda_l <= ~sh[7];   // 发 1 就释放，发 0 就拉低
            end
            if (cnt == HALF - 1) begin
                cnt   <= 10'd0;
                scl_l <= 1'b0;                          // 释放 SCL = 变高
                st    <= S_HIGH;
            end else begin
                cnt <= cnt + 10'd1;
            end
        end

        // SCL 高电平：ACK 位在 1/4 点读线上电平
        S_HIGH: begin
            if (cnt == Q && bit_idx == 4'd8) begin
                ack_ok <= (sda_in == 1'b0);             // 从机拉低 = ACK
            end
            if (cnt == HALF - 1) begin
                cnt   <= 10'd0;
                scl_l <= 1'b1;                          // 拉低 SCL
                if (bit_idx == 4'd8) begin
                    bit_idx <= 4'd0;
                    if (!ack_ok || !wvalid_r) begin     // NACK 或没有后续字节 -> 收尾
                        ack_err <= ~ack_ok;
                        st      <= S_STOPA;
                    end else begin
                        wr_next <= 1'b1;                // 向上一层要下一个字节
                        st      <= S_LOAD;
                    end
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    sh      <= {sh[6:0], 1'b1};
                    st      <= S_LOW;
                end
            end else begin
                cnt <= cnt + 10'd1;
            end
        end

        // STOP 第 1 段：SCL 低，先把 SDA 拉低（保证后面有 0->1 的上升沿）
        S_STOPA: begin
            sda_l <= 1'b1;
            if (cnt == HALF - 1) begin
                cnt <= 10'd0; scl_l <= 1'b0; st <= S_STOPB;
            end else cnt <= cnt + 10'd1;
        end

        // STOP 第 2 段：SCL 高、SDA 仍低
        S_STOPB: begin
            if (cnt == HALF - 1) begin
                cnt <= 10'd0; sda_l <= 1'b0; st <= S_STOPC;  // 释放 SDA = STOP 条件
            end else cnt <= cnt + 10'd1;
        end

        // STOP 第 3 段：总线空闲时间
        S_STOPC: begin
            if (cnt == HALF - 1) begin
                cnt <= 10'd0; done <= 1'b1; busy <= 1'b0; st <= S_IDLE;
            end else cnt <= cnt + 10'd1;
        end

        endcase
    end
end

endmodule
