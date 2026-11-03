`timescale 1ns / 1ps
// =============================================================================
//  tb_speed_range.v  ——  M 法测速量程标定（低速盲区 + 高速上限）
//
//  为什么要做：答辩必问"最低能测多少转 / 最高能测多少转"。
//  有这张表就能给出带 \% 的具体数字，不用含糊。
//
//  决定量程的三个参数：
//    编码器   600 PPR 四倍频 -> 2400 计数/圈
//    闸门     T = 10 ms      -> 每闸门计数 M = rpm x 2400 x 0.01 / 60 = rpm x 0.4
//    换算     rpm = M x 2.5  -> 量化台阶 2.5 转/分
//    消抖     200 拍 @100MHz = 2 us
//
//  ⚠️ 消抖上限的关键容易算错：
//     正交一个"状态"只有 1 步宽，但**单相信号的半周期是 2 步宽**。
//     消抖要的是单相信号稳定 200 拍，所以它约束的是 2 倍步长：
//        2 x step_ns >= 2000 ns  ->  rpm <= 25e6 / 1000 = 25000 转/分
//     不是 12000。本 tb 用 20000 / 24000 / 25000 / 26000 / 30000 去撞这条线。
//
//  输出两列关键数据：
//    true  = 用同一窗口内的真实脉冲计数算出的转速（证明计数本身一个没丢）
//    disp  = 模块实际输出的 rpm_filtered（证明误差只来自「量化 + 取整」）
//    两者之差就是纯算法误差。
// =============================================================================
module tb_speed_range;

parameter real CLK_NS   = 10.0;            // 100 MHz -> 10 ns
parameter real STEP_REF = 25_000_000.0;    // rpm x 每正交步宽度(ns) = 25e6

reg  clk = 1'b0;
reg  rst = 1'b1;
reg  clr = 1'b0;
reg  enc_a = 1'b0, enc_b = 1'b0, enc_z = 1'b0;
wire [2:0] enc_raw = {enc_z, enc_b, enc_a};   // [2]=Z [1]=B [0]=A

wire              tick;
wire [1:0]        state;
wire              dir, err;
wire [15:0]       count, pulse_num, rpm_raw, rpm_f;
wire [11:0]       position;
wire signed[15:0] turns;
wire              over_speed, pulse_loss, uart_tx_pin;

encoder_top uut (
    .clk(clk), .rst(rst), .clr(clr), .enc_raw(enc_raw),
    .state(state), .dir(dir), .count(count), .err(err),
    .position(position), .turns(turns),
    .pulse_num(pulse_num), .rpm(rpm_raw), .rpm_filtered(rpm_f),
    .over_speed(over_speed), .pulse_loss(pulse_loss), .tick(tick),
    .uart_tx_pin(uart_tx_pin)
);

always #(CLK_NS/2.0) clk = ~clk;

// ============================================================================
//  正交信号发生器：正转序列 {A,B} = 00 -> 10 -> 11 -> 01 -> 00
//  step_ns 用实数，保证 137、613 这种除不尽的速度也没有取整误差
// ============================================================================
real step_ns = 1000000.0;
initial begin
    forever begin
        #(step_ns); enc_a = 1'b1;
        #(step_ns); enc_b = 1'b1;
        #(step_ns); enc_a = 1'b0;
        #(step_ns); enc_b = 1'b0;
    end
end

integer err_cnt = 0;
always @(posedge clk) if (uut.err) err_cnt <= err_cnt + 1;

// ============================================================================
//  测一个速度点
// ============================================================================
integer s_min, s_max, s_sum, sample_n, err_before, cnt_sum;
integer p10, pa;

task do_case;
    input integer target;
    input integer ncol;
    real   true_rpm;
    begin
        step_ns = STEP_REF / target;
        rst = 1'b1;
        repeat (20) @(posedge clk);
        rst = 1'b0;

        repeat (5) @(posedge tick);   // 4 拍填满滑动窗口 + 1 拍余量
        err_before = err_cnt;         // ⚠️ 放在 warmup 之后：复位瞬间会有一次
                                      //    伪"非法跳变"（prev=00 遇到任意 cur），
                                      //    那是上电瞬态，不算正常工作误差

        s_sum = 0; cnt_sum = 0; s_min = 1000000; s_max = 0; sample_n = 0;
        while (sample_n < ncol) begin
            @(posedge tick);
            #1;                              // 等非阻塞赋值落地
            cnt_sum = cnt_sum + uut.pulse_num;
            if (uut.rpm_filtered < s_min) s_min = uut.rpm_filtered;
            if (uut.rpm_filtered > s_max) s_max = uut.rpm_filtered;
            s_sum    = s_sum + uut.rpm_filtered;
            sample_n = sample_n + 1;
        end

        true_rpm = (cnt_sum * 2.5) / ncol;   // 同一窗口里真实计数换算出的转速
        // 误差（单位 0.1%），手算避免 xsim 不支持 "%+f" 的问题
        p10 = (s_sum * 1000) - (target * 1000 * ncol);
        p10 = p10 / (target * ncol) * 1;     // (avg-target)/target*1000
        pa  = p10;
        if (pa < 0) begin
            pa = -pa;
            $display("  %6d | %7.1f | %6d | %5d ~ %5d |  -%0d.%0d | %5d",
                     target, true_rpm, s_sum / ncol, s_min, s_max,
                     pa / 10, pa % 10, err_cnt - err_before);
        end else begin
            $display("  %6d | %7.1f | %6d | %5d ~ %5d |   %0d.%0d | %5d",
                     target, true_rpm, s_sum / ncol, s_min, s_max,
                     pa / 10, pa % 10, err_cnt - err_before);
        end
    end
endtask

initial begin
    $display("");
    $display("=== LOW SPEED: where does it stop working? (ncol=12 x 10ms = 120ms) ===");
    $display("  target |   true   |  disp  |   min ~ max   |   err%%  | err_cnt");
    $display("  -------+----------+--------+---------------+---------+--------");
    do_case(    1, 12);
    do_case(    2, 12);
    do_case(    3, 12);
    do_case(    4, 12);
    do_case(    5, 12);
    do_case(    6, 12);
    do_case(    8, 12);
    do_case(   10, 12);
    do_case(   15, 12);
    do_case(   20, 12);
    do_case(   25, 12);
    do_case(   50, 12);
    do_case(  100, 12);
    do_case(  137, 12);   // 特意选非 2.5 的整数倍，暴露量化误差
    do_case(  250, 12);
    do_case(  337, 12);   // 同上
    do_case(  600, 12);
    do_case(  613, 12);   // 同上

    $display("");
    $display("=== HIGH SPEED: does the 2us debounce keep up? ===");
    $display("  target |   true   |  disp  |   min ~ max   |   err%%  | err_cnt");
    $display("  -------+----------+--------+---------------+---------+--------");
    do_case(12000, 10);
    do_case(20000, 10);
    do_case(24000, 10);
    do_case(25000, 10);   // 理论临界点
    do_case(26000, 10);   // 越界：应该开始崩
    do_case(30000, 10);

    $display("");
    $display("=== DONE ===");
    $finish;
end

initial begin
    #8.0e9;               // 8 秒仿真时间上限，必须写实数（超 32 位整数范围）
    $display("!! TIMEOUT");
    $finish;
end

endmodule
