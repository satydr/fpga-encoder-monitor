module encoder_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        clr,          // 报警清除（按键，高有效）
    input  wire  [2:0] enc_raw,
    output wire  [1:0] state,
    output wire        dir,
    output wire [15:0] count,
    output wire        err,
    output wire [11:0] position,
    output wire signed [15:0] turns,
    output wire [15:0] pulse_num,
    output wire [15:0] rpm,
    output wire [15:0] rpm_filtered,
    output wire        over_speed,   // 超速报警（锁存）
    output wire        pulse_loss,   // 丢脉冲报警（锁存）
    output wire        tick,         // 10 ms 闸门脉冲：每个闸门出一个新采样点
    output wire        uart_tx_pin,  // 串口发送线（EGO1 的 T4）
    // ---- 2026-10-05 新增：串口接收，让报警阈值可在线改 ----
    input  wire        uart_rx_pin,  // 串口接收线（EGO1 的 N5）
    output wire [15:0] speed_limit,  // 当前超速阈值（可回读给 PC）
    output wire [15:0] z_gap_tol,    // 当前 Z 相容差
    output wire        cmd_ack       // 1 拍脉冲：命令已生效，PC 据此确认
);

wire [2:0] synced;
wire [2:0] debounced;
wire       step_up;
wire       step_dn;
wire       z_rise;                   // enc_pos 与 enc_alarm 之间的连线

// 组帧器 <-> 发送器 之间的内部握手线（只在芯片内部，不接引脚）
wire       tx_start;                 // 组帧器 -> 发送器：开始发这个字节
wire [7:0] tx_data;                  // 组帧器 -> 发送器：发什么
wire       tx_busy;                  // 发送器 -> 组帧器：我还在忙

// ---- UART 接收链路的内部握手 ----
wire       rx_valid;                 // uart_rx -> cmd_rx：收到一个字节
wire [7:0] rx_data;
wire       rx_frame_err;
wire       clr_pulse;                // cmd_rx -> enc_alarm：远程清报警

enc_sync u_sync (
    .clk     (clk),
    .enc_raw (enc_raw),
    .synced  (synced)
);

enc_debounce u_deb_a (
    .clk     (clk),
    .rst     (rst),
    .sig_in  (synced[0]),
    .sig_out (debounced[0])
);

enc_debounce u_deb_b (
    .clk     (clk),
    .rst     (rst),
    .sig_in  (synced[1]),
    .sig_out (debounced[1])
);

enc_debounce u_deb_z (
    .clk     (clk),
    .rst     (rst),
    .sig_in  (synced[2]),
    .sig_out (debounced[2])
);

enc_quad u_quad (
    .clk     (clk),
    .rst     (rst),
    .a_sync  (debounced[0]),
    .b_sync  (debounced[1]),
    .state   (state),
    .dir     (dir),
    .count   (count),
    .err     (err),
    .step_up (step_up),
    .step_dn (step_dn)
);

enc_pos u_pos (
    .clk      (clk),
    .rst      (rst),
    .step_up  (step_up),
    .step_dn  (step_dn),
    .z_sync   (debounced[2]),
    .z_rise   (z_rise),
    .position (position),
    .turns    (turns)
);

enc_speed u_speed (
    .clk       (clk),
    .rst       (rst),
    .step_up   (step_up),
    .step_dn   (step_dn),
    .tick      (tick),
    .pulse_num (pulse_num),
    .rpm       (rpm)
);

enc_filter u_filter (
    .clk     (clk),
    .rst     (rst),
    .tick    (tick),
    .rpm_in  (rpm),
    .rpm_avg (rpm_filtered)
);

// 报警阈值来自寄存器，上电默认 700/200；上位机可经 UART 改
enc_alarm u_alarm (
    .clk          (clk),
    .rst          (rst),
    .clr          (clr),
    .remote_clr   (clr_pulse),
    .speed_limit  (speed_limit),
    .z_gap_tol    (z_gap_tol),
    .rpm          (rpm_filtered),  // 用滤波后的转速判超速
    .step_up      (step_up),
    .step_dn      (step_dn),
    .z_rise       (z_rise),
    .err          (err),
    .over_speed   (over_speed),
    .pulse_loss   (pulse_loss),
    .speed_limit_o(),
    .z_tol_o      ()
);

// ------------------------------------------------------------------ UART 上传
// tick 直接复用 enc_speed 已产生的 10 ms 闸门 —— 不另造定时器，天然同步
uart_frame u_frame (
    .clk        (clk),
    .rst        (rst),
    .tick       (tick),
    .turns      (turns),
    .position   (position),
    .rpm        (rpm_filtered),  // 上传滤波后的转速，PC 上才画得出平滑曲线
    .over_speed (over_speed),
    .pulse_loss (pulse_loss),
    .tx_start   (tx_start),
    .tx_data    (tx_data),
    .tx_busy    (tx_busy)
);

uart_tx u_uart_tx (
    .clk      (clk),
    .rst      (rst),
    .tx_start (tx_start),
    .tx_data  (tx_data),
    .tx       (uart_tx_pin),
    .tx_busy  (tx_busy)
);

// ------------------------------------------------- UART 接收（阈值在线可改）
// EGO1 的 N5 = 手册里的 UART_TX = FPGA 的【接收端】，
// 与 T4（FPGA 发送端）正好是一对，都在 FT2232 通道 B 上。
uart_rx u_rx (
    .clk         (clk),
    .rst         (rst),
    .rx          (uart_rx_pin),
    .rx_valid    (rx_valid),
    .rx_data     (rx_data),
    .rx_frame_err(rx_frame_err)
);

cmd_rx u_cmd (
    .clk         (clk),
    .rst         (rst),
    .rx_valid    (rx_valid),
    .rx_data     (rx_data),
    .speed_limit (speed_limit),
    .z_gap_tol   (z_gap_tol),
    .clr_pulse   (clr_pulse),
    .ack_pulse   (cmd_ack),
    .last_cmd    (),
    .last_param  ()
);

endmodule
