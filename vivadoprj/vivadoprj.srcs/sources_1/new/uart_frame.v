// =============================================================================
//  uart_frame.v  ——  组帧器：把内部数据打包成定长 11 字节，交给 uart_tx 逐字节发出
//
//  帧格式（11 字节，多字节字段一律"高字节先发"，即大端）：
//    [0]  0xAA            帧头 1
//    [1]  0x55            帧头 2
//    [2]  0x07            数据段长度 = 7
//    [3]  turns[15:8]     圈数（有符号 16 位）高字节
//    [4]  turns[7:0]      圈数 低字节
//    [5]  {4'b0, position[11:8]}   圈内位置 高字节（高 4 位补 0）
//    [6]  position[7:0]   圈内位置 低字节
//    [7]  rpm[15:8]       滤波后转速 高字节
//    [8]  rpm[7:0]        滤波后转速 低字节
//    [9]  {6'b0, pulse_loss, over_speed}   状态字节（bit1=丢脉冲 bit0=超速）
//    [10] SUM = 前 10 字节累加和（只取低 8 位）
//
//  上位机侧：绝对位置 = turns * 2400 + position
//  一帧 11 字节 = 11 x 10 位 x 8680 ns ≈ 955 us，相对 10 ms 的上传周期只占 9.5%
// =============================================================================
module uart_frame (
    input  wire               clk,
    input  wire               rst,
    input  wire               tick,          // 10 ms 闸门脉冲：每来一次发一帧
    input  wire signed [15:0] turns,
    input  wire        [11:0] position,
    input  wire        [15:0] rpm,           // 传滤波后的转速
    input  wire               over_speed,
    input  wire               pulse_loss,
    output reg                tx_start,      // 1 拍脉冲，给 uart_tx
    output reg         [7:0]  tx_data,       // 给 uart_tx 的字节
    input  wire               tx_busy        // 来自 uart_tx
);

localparam [3:0] BYTE_CNT = 4'd11;   // 一帧 11 个字节（0~10）

// ---------------------------------------------------------------- 快照锁存
// ⚠️ 关键设计：一帧要发 955 us。如果"发到第几个字节就临时去读一次输入"，
//    那么同一个 16 位字段的高字节和低字节是在**两个不同时刻**采的 ——
//    万一正好卡在进位那一刻（如 turns 0x00FF -> 0x0100），拼出来的值完全错误。
//    而且 6 个数据字节彼此不同步，也就谈不上"状态快照"。
//    所以在闸门 tick 那一刻把全部字段一次性锁存，整帧发的都是同一时刻的快照。
reg [15:0] f_turns;
reg [11:0] f_pos;
reg [15:0] f_rpm;
reg [7:0]  f_status;

// ---------------------------------------------------------------- 拆字节
// 拆的是"锁存后的快照"，不是实时输入
wire [7:0] b_turns_hi = f_turns[15:8];
wire [7:0] b_turns_lo = f_turns[7:0];
wire [7:0] b_pos_hi   = {4'b0, f_pos[11:8]};
wire [7:0] b_pos_lo   = f_pos[7:0];
wire [7:0] b_rpm_hi   = f_rpm[15:8];
wire [7:0] b_rpm_lo   = f_rpm[7:0];
wire [7:0] b_status   = f_status;

// 校验和：全部操作数都是 8 位，加法自然按 8 位回绕，正好是要的"低 8 位"
wire [7:0] b_sum = 8'hAA + 8'h55 + 8'h07
                 + b_turns_hi + b_turns_lo
                 + b_pos_hi   + b_pos_lo
                 + b_rpm_hi   + b_rpm_lo
                 + b_status;

// ---------------------------------------------------------------- 字节选择器
// 组合逻辑：给定序号 idx，吐出该发的字节
reg [3:0] idx;                    // 下一个要发的字节序号（0~10）
reg [7:0] byte_mux;
always @(*) begin
    case (idx)
        4'd0 : byte_mux = 8'hAA;          // 帧头 1（常量，与数据无关）
        4'd1 : byte_mux = 8'h55;          // 帧头 2
        4'd2 : byte_mux = 8'h07;          // 数据长度
        4'd3 : byte_mux = b_turns_hi;
        4'd4 : byte_mux = b_turns_lo;
        4'd5 : byte_mux = b_pos_hi;
        4'd6 : byte_mux = b_pos_lo;
        4'd7 : byte_mux = b_rpm_hi;
        4'd8 : byte_mux = b_rpm_lo;
        4'd9 : byte_mux = b_status;
        default : byte_mux = b_sum;       // 4'd10
    endcase
end

// ---------------------------------------------------------------- 发送状态机
// ⚠️ 坑 1：从"我发出 tx_start"到"uart_tx 把 tx_busy 抬起来"中间隔了 2 拍。
//    如果只写 "if (!tx_busy) 就发下一个字节"，那么在 tx_busy 还没起来的这 2 拍里
//    条件会连续成立两次 —— 字节序号一次跳 2，帧就被发残了。
//    正确做法：显式分状态，先确认 tx_busy 起来了，再等它落下去。
// ⚠️ 坑 2：tick 那一拍，enc_speed / enc_filter 正在用非阻塞赋值更新 rpm，
//    同拍读到的是"上一个闸门"的旧值。所以插入 S_SNAP **延后一拍**再锁存，
//    拿到的是本闸门刚算出来的新鲜数据（否则上传的数据永远慢一个闸门 = 10 ms）。
localparam [1:0] S_IDLE = 2'd0;   // 等一帧的触发
localparam [1:0] S_SNAP = 2'd3;   // tick 后延一拍：锁存快照 + 送出第 1 个字节
localparam [1:0] S_WAIT = 2'd1;   // 等 uart_tx 把 tx_busy 拉起来（确认它接手了）
localparam [1:0] S_SEND = 2'd2;   // 等这个字节发完（tx_busy 落回 0）

reg [1:0] st;

always @(posedge clk) begin
    if (rst) begin
        st       <= S_IDLE;
        idx      <= 4'd0;
        tx_start <= 1'b0;
        tx_data  <= 8'h00;
        f_turns  <= 16'd0;
        f_pos    <= 12'd0;
        f_rpm    <= 16'd0;
        f_status <= 8'd0;
    end else begin
        tx_start <= 1'b0;                       // 默认拉低 => tx_start 天然是 1 拍脉冲

        case (st)
            S_IDLE : begin
                if (tick && !tx_busy) begin     // 上一帧还没发完就丢掉这次 tick
                    st <= S_SNAP;
                end
            end

            S_SNAP : begin                      // 延后一拍，此时 rpm / position 已更新完
                f_turns  <= turns;              // 一次性锁存：整帧发这一刻的快照
                f_pos    <= position;
                f_rpm    <= rpm;
                f_status <= {6'b0, pulse_loss, over_speed};
                tx_data  <= 8'hAA;              // 帧头是常量，直接给
                tx_start <= 1'b1;
                idx      <= 4'd1;
                st       <= S_WAIT;
            end

            S_WAIT : begin
                if (tx_busy) st <= S_SEND;      // uart_tx 已接手，可以开始等它结束了
            end

            S_SEND : begin
                if (!tx_busy) begin             // 这个字节发完了
                    if (idx == BYTE_CNT) begin  // 11 个字节全发完 -> 收工
                        st  <= S_IDLE;
                        idx <= 4'd0;
                    end else begin              // 继续发下一个字节
                        tx_data  <= byte_mux;   // byte_mux 由当前 idx 决定
                        tx_start <= 1'b1;
                        idx      <= idx + 4'd1;
                        st       <= S_WAIT;
                    end
                end
            end

            default : st <= S_IDLE;
        endcase
    end
end

endmodule
