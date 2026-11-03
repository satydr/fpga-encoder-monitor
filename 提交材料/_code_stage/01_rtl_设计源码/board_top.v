`timescale 1ns / 1ps
// =============================================================================
//  board_top.v  --  EGO1 板级顶层
//
//  encoder_top 是"功能顶层"（端口是逻辑信号）；board_top 负责把逻辑信号接到引脚：
//      - 上电复位
//      - 编码器信号来源选择（外部真编码器 / 内部自检信号源）
//      - 数码管扫描显示、LED 指示、UART 发送引脚、OLED 波形显示
//
//  SW7 = 0 : 用外部编码器（J5-15/16/17）
//  SW7 = 1 : 用内部自检信号源（600 转/分正交波形，无编码器也能演示）
//
//  显示：组0 = 圈内位置 position 十六进制（000~95F）
//        组1 = 滤波后转速 rpm_filtered 十六进制（258 = 600）
//        OLED = 转速波形（每 10 ms 画一列，扫满 128 列回到开头）
// =============================================================================
module board_top (
    input  wire        sys_clk,      // P17   100 MHz
    input  wire        rst_btn,      // P15   FPGA_RESET，【低有效】未按=高 按下=低（实测）
    input  wire        clr_btn,      // R11   S0，报警清除，按下为高
    input  wire [7:0]  sw,           // SW0~SW7
    input  wire        enc_a,        // B11   J5-15   编码器 A
    input  wire        enc_b,        // A11   J5-16   编码器 B
    input  wire        enc_z,        // E15   J5-17   编码器 Z
    output wire [15:0] led,          // LED0~15，高电平点亮
    output wire [7:0]  seg0,         // 数码管组0 段 A~DP，高电平点亮
    output wire [3:0]  dig0,         // 数码管组0 位选 K1~K4，高电平选通
    output wire [7:0]  seg1,         // 数码管组1 段 A~DP
    output wire [3:0]  dig1,         // 数码管组1 位选 K1~K4
    output wire        uart_tx,      // T4    = FPGA 发送端 -> FT2232 通道B
    input  wire        uart_rx,      // N5    = FPGA 接收端 <- FT2232 通道B（阈值在线可改）
    output wire        oled_scl,     // E16   J5-18 -> OLED SCL
    inout  wire        oled_sda      // D15   J5-19 -> OLED SDA
);

// ============================================================================
//  1. 上电复位：上电后先保持约 0.66 ms 复位（65536 拍），再并入板上复位键
// ============================================================================
reg [16:0] por_cnt = 17'd0;
always @(posedge sys_clk) begin
    if (!por_cnt[16]) por_cnt <= por_cnt + 17'd1;
end

// ⚠️ 关键（2026-10-04 上板实测得出，不是推断）：
//    EGO1 的专用复位键 FPGA_RESET(P15) 是【低有效】—— 未按=高，按下=低。
//    原写法 `| rst_btn` 会让系统永远卡在复位（表现为 UART 一个字节都不发）。
//    用 diag_top 强制喂 1'b0 后串口立刻吐出 299 帧校验和全对的帧，才定位到这里。
//    （注意：通用按键 S0~S4 是【高有效】，手册写明"默认为低电平，按下为高"，别混。）
wire rst = (~por_cnt[16]) | (~rst_btn);   // 低有效：未按(高)不复位，按下(低)复位

// ============================================================================
//  2. 内部自检信号源（SW7 = 1 时启用）
//     600 转/分：每个正交状态持续 4167 拍 -> 一圈 2400 个状态 = 100 ms
//     Z 相每圈来一次，脉宽 10 us（远大于 2 us 消抖窗口）
// ============================================================================
localparam integer STEP_DIV = 4167;      // 每个正交状态的持续拍数
localparam integer CPR      = 2400;      // 一圈的四倍频计数
localparam integer Z_WIDE   = 1000;      // Z 脉冲宽度（拍）

reg [12:0] tdiv  = 13'd0;                // 状态内分频
reg [1:0]  phase = 2'd0;                 // 正交相位 0..3
reg [11:0] stepc = 12'd0;                // 圈内计数 0..2399
reg [9:0]  zcnt  = 10'd0;                // Z 脉宽倒数
reg        z_gen = 1'b0;

always @(posedge sys_clk) begin
    if (tdiv == STEP_DIV - 1) begin
        tdiv  <= 13'd0;
        phase <= phase + 2'd1;
        if (stepc == CPR - 1) begin
            stepc <= 12'd0;
            zcnt  <= Z_WIDE[9:0];        // 一圈跑完 -> 触发 Z
        end else begin
            stepc <= stepc + 12'd1;
        end
    end else begin
        tdiv <= tdiv + 13'd1;
    end

    if (zcnt != 10'd0) begin
        zcnt  <= zcnt - 10'd1;
        z_gen <= 1'b1;
    end else begin
        z_gen <= 1'b0;
    end
end

// 正交状态序列（与 tb 里一致）：01 -> 11 -> 10 -> 00
// ⚠️ enc_raw[1:0] = {B, A}，所以这两位直接就是 {B,A}
wire [1:0] ab_gen = (phase == 2'd0) ? 2'b01 :
                    (phase == 2'd1) ? 2'b11 :
                    (phase == 2'd2) ? 2'b10 : 2'b00;

wire [2:0] enc_test = {z_gen, ab_gen};              // {Z, B, A}

// ============================================================================
//  3. 编码器信号来源选择：{enc_z, enc_b, enc_a} 顺序必须是 Z,B,A（enc_raw[0] 才是 A）
// ============================================================================
wire [2:0] enc_raw = sw[7] ? enc_test : {enc_z, enc_b, enc_a};

// ============================================================================
//  4. 功能顶层例化
// ============================================================================
wire [1:0]  state;
wire        dir;
wire [15:0] count;
wire        err;
wire [11:0] position;
wire [15:0] speed_limit;       // 当前超速阈值（可被上位机改）
wire [15:0] z_gap_tol;         // 当前 Z 相容差
wire        cmd_ack;           // 命令生效脉冲
wire signed [15:0] turns;
wire [15:0] pulse_num;
wire [15:0] rpm;
wire [15:0] rpm_filtered;
wire        over_speed;
wire        pulse_loss;
wire        tick;          // 10 ms 一个采样点，直接喂给 OLED

encoder_top u_enc (
    .clk          (sys_clk),
    .rst          (rst),
    .clr          (clr_btn),
    .enc_raw      (enc_raw),
    .state        (state),
    .dir          (dir),
    .count        (count),
    .err          (err),
    .position     (position),
    .turns        (turns),
    .pulse_num    (pulse_num),
    .rpm          (rpm),
    .rpm_filtered (rpm_filtered),
    .over_speed   (over_speed),
    .pulse_loss   (pulse_loss),
    .tick         (tick),
    .uart_tx_pin  (uart_tx),
    .uart_rx_pin  (uart_rx),
    .speed_limit  (speed_limit),
    .z_gap_tol    (z_gap_tol),
    .cmd_ack      (cmd_ack)
);

// ============================================================================
//  5. 数码管显示
// ============================================================================
seg_scan u_seg (
    .clk  (sys_clk),
    .val0 ({4'b0000, position}),        // 组0：圈内位置
    .val1 (rpm_filtered),               // 组1：滤波后转速
    .seg0 (seg0),
    .dig0 (dig0),
    .seg1 (seg1),
    .dig1 (dig1)
);

// ============================================================================
//  6. LED 指示
// ============================================================================
reg [26:0] hb = 27'd0;
always @(posedge sys_clk) hb <= hb + 27'd1;      // 约 1.34 s 翻转 = 心跳

assign led[0]   = hb[26];       // 心跳：证明 FPGA 在跑
assign led[1]   = dir;          // 方向：0 = 正转，1 = 反转
assign led[2]   = over_speed;   // 超速报警
assign led[3]   = pulse_loss;   // 丢脉冲报警
assign led[4]   = err;          // A/B 非法跳变
assign led[5]   = sw[7];        // 亮 = 正在用内部自检信号源
assign led[7:6] = state;        // 当前正交状态
assign led[15:8] = 8'h00;

// ============================================================================
//  7. OLED：转速波形（SSD1306，I2C）
//     每来一个 10 ms 闸门画一列，走满 128 列回到开头覆盖 —— 像示波器那样扫
// ============================================================================
oled_ssd1306 u_oled (
    .clk  (sys_clk),
    .rst  (rst),
    .rpm  (rpm_filtered),   // 画滤波后的转速，曲线才平滑
    .tick (tick),
    .scl  (oled_scl),
    .sda  (oled_sda)
);

endmodule
