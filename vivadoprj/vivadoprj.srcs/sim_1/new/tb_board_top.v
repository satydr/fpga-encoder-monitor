`timescale 1ns / 1ps
// =============================================================================
//  tb_board_top.v  ——  板级整链仿真（上板前的最后一道防线）
//
//  与 tb_top_uart 的区别：
//      tb_top_uart = 台架测试，把正交波形直接灌进 encoder_top 的输入脚
//      本 tb       = 整车路试，例化真正要烧进 FPGA 的顶层 board_top，
//                    连上电复位、内部自检信号源、数码管扫描、LED、OLED 一起跑
//
//  测试点：
//    TP1  上电复位：por_cnt 数满 65536 拍（约 655 us）后 rst 释放
//    TP2  自检信号源：rpm_filtered 收敛到 600（十六进制 0x258）
//    TP3  数码管组1：位选扫过时依次送出 "0" "2" "5" "8" 的段码
//    TP4  UART：抓到完整 11 字节帧，帧内 rpm 与顶层 rpm_filtered 一致
//    TP5  OLED：I2C 总线上出现传输（初始化 + 显存刷新）
//    TP6  LED：bit5=1（自检源），bit4/3/2 无报警；bit7:6=state 会变，不判定
//
//  ⚠️ 为了让仿真能在可接受时间内跑完，本 tb 用 defparam 把 OLED 的上电等待
//     和 I2C 分频改小了。I2C 的真实 100 kHz 时序由 tb_i2c / tb_oled 单独覆盖，
//     这里只验证"线连对了、数据流通了、没卡死"。
// =============================================================================
module tb_board_top;

reg        sys_clk = 1'b0;
reg        rst_btn = 1'b1;   // P15 低有效：不按=高=1，按下=低=0      // P15，不按
reg        clr_btn = 1'b0;      // R11，不按
reg  [7:0] sw      = 8'h80;     // SW7=1 -> 用内部自检信号源
reg        enc_a   = 1'b0;      // 外部编码器不用，全给 0
reg        enc_b   = 1'b0;
reg        enc_z   = 1'b0;

wire [15:0] led;
wire [7:0]  seg0, seg1;
wire [3:0]  dig0, dig1;
wire        uart_tx;
reg         uart_rx = 1'b1;   // 模拟上位机不发言，rx 保持空闲高
wire        oled_scl;
wire        oled_sda;

board_top uut (
    .sys_clk (sys_clk),
    .rst_btn (rst_btn),
    .clr_btn (clr_btn),
    .sw      (sw),
    .enc_a   (enc_a),
    .enc_b   (enc_b),
    .enc_z   (enc_z),
    .led     (led),
    .seg0    (seg0),
    .dig0    (dig0),
    .seg1    (seg1),
    .dig1    (dig1),
    .uart_tx (uart_tx),
    .uart_rx (uart_rx),
    .oled_scl(oled_scl),
    .oled_sda(oled_sda)
);

pullup(oled_sda);
pullup(oled_scl);

// ---- 加速 OLED，否则一屏要跑 100 ms 以上 ----
// ⚠️ BOOT_CYCLES 必须大于 board_top 的上电复位时间（65536 拍 = 655 us）。
//    oled_ssd1306 的状态机不受 rst 控制，从 t=0 就开始数 boot；
//    如果它在 rst 还没释放时就数完，I2C 主机会被 rst 压住、start 脉冲被吃掉，
//    OLED 状态机就永远卡在 S_INIT。这是本 tb 抓出来的第一个真问题。
defparam uut.u_oled.BOOT_CYCLES = 24'd800000;     // 8 ms，稳稳落在复位之后
defparam uut.u_oled.GAP_CYCLES  = 24'd3000;
defparam uut.u_oled.u_i2c.DIV   = 50;
defparam uut.u_oled.u_i2c.HALF  = 25;
defparam uut.u_oled.u_i2c.Q     = 12;

always #5 sys_clk = ~sys_clk;                 // 100 MHz

// ============================================================================
//  数码管采样：位选扫到哪一位，就把当时的段码存下来
// ============================================================================
reg [7:0] seg_cap  [0:3];      // 组1（转速）
reg [7:0] seg_cap0 [0:3];      // 组0（位置）
always @(posedge sys_clk) begin
    case (dig1)                               // dsel = 4'b0001 << pos
        4'b0001: seg_cap[0] <= seg1;          // pos=0 -> val[3:0]  个位
        4'b0010: seg_cap[1] <= seg1;          // pos=1 -> val[7:4]  十位
        4'b0100: seg_cap[2] <= seg1;          // pos=2 -> val[11:8] 百位
        4'b1000: seg_cap[3] <= seg1;          // pos=3 -> val[15:12]千位
    endcase
    case (dig0)
        4'b0001: seg_cap0[0] <= seg0;
        4'b0010: seg_cap0[1] <= seg0;
        4'b0100: seg_cap0[2] <= seg0;
        4'b1000: seg_cap0[3] <= seg0;
    endcase
end

// ============================================================================
//  假从机：I2C 是靠"从机把 SDA 拉低"来应答的。
//  没有它，主机发完地址字节就收不到 ACK，会立刻 STOP 收尾 —— 于是一次传输只有
//  1 个字节，OLED 状态机就会疯狂空转（我第一次跑就是这个症状：START 数 = 1739）。
//  真板上这个角色由 SSD1306 自己扮演，仿真里必须造一个出来。
// ============================================================================
reg [3:0] edge_cnt = 0;
reg       scl_d = 1'b1, sda_d = 1'b1;
reg       ack_drive = 1'b0;

wire scl_rise =  oled_scl & ~scl_d;
wire scl_fall = ~oled_scl &  scl_d;
wire sda_rise =  oled_sda & ~sda_d;
wire sda_fall = ~oled_sda &  sda_d;

// ⚠️ 必须用 tb 自己维护的 bus_busy，不能用主机的 i2c_busy：
//    主机是在产生 START 的同一拍就把 busy 拉高的，用它的 busy 会永远判不出 START
reg bus_busy = 1'b0;
wire start_cond = oled_scl & sda_fall & !bus_busy;
wire stop_cond  = oled_scl & sda_rise &  bus_busy;
always @(posedge sys_clk) begin
    if (start_cond)      bus_busy <= 1'b1;
    else if (stop_cond)  bus_busy <= 1'b0;
end

always @(posedge sys_clk) begin
    scl_d <= oled_scl;
    sda_d <= oled_sda;
end

always @(posedge sys_clk) begin
    if (start_cond) edge_cnt <= 4'd0;              // 每次 START 重新数位
    else if (scl_rise) begin
        if (edge_cnt == 4'd8) ack_drive <= 1'b1;   // 第 9 个沿 = ACK 位，拉低应答
        edge_cnt <= (edge_cnt == 4'd8) ? 4'd0 : edge_cnt + 4'd1;
    end
    if (scl_fall) ack_drive <= 1'b0;
end
assign oled_sda = ack_drive ? 1'b0 : 1'bz;

// ---- 统计：传输次数 + 每次传输发了几个字节 ----
integer i2c_start_n = 0;
integer byte_cnt    = 0;
integer last_bytes  = 0;
always @(posedge sys_clk) begin
    if (start_cond) begin
        i2c_start_n <= i2c_start_n + 1;
        byte_cnt    <= 0;
    end else if (scl_rise && edge_cnt == 4'd8) begin
        byte_cnt <= byte_cnt + 1;
    end
    if (stop_cond) last_bytes <= byte_cnt;    // 锁存本次传输的字节数
end

// ============================================================================
//  UART 接收：115200 8N1，每位中点采样
// ============================================================================
parameter integer BIT_NS = 8680;
reg [7:0] rx [0:10];
integer   n, b, i;
reg [15:0] f_r;
reg [11:0] f_p;
time      t_f0, t_f1;
reg [7:0] csum;

task recv_frame;
    begin
        for (n = 0; n < 11; n = n + 1) begin
            @(negedge uart_tx);
            if (n == 0) t_f0 = $time;
            #(BIT_NS + BIT_NS/2);
            for (b = 0; b < 8; b = b + 1) begin
                rx[n][b] = uart_tx;
                #BIT_NS;
            end
        end
    end
endtask

// ============================================================================
//  超时保护：万一哪个 wait 卡住，不至于无限跑
// ============================================================================
initial begin
    #150_000_000;
    $display("!! TIMEOUT at t=%0d ns", $time);
    $finish;
end

// ============================================================================
//  主流程
// ============================================================================
initial begin
    // ---- TP1 上电复位 ----
    wait (uut.rst == 1'b0);
    $display("TP1 POR   : rst released at %0d ns  (expect ~655360 ns)", $time);

    // ---- TP2 自检信号源 -> 转速收敛 ----
    wait (uut.rpm_filtered == 16'd600);
    $display("TP2 SPEED : rpm_filtered = %0d at %0d ns  (expect 600)",
             uut.rpm_filtered, $time);

    // 让数码管扫完一整轮（4 位 x 50000 拍 = 2 ms）
    #3_000_000;

    // ---- TP3 数码管组1 应显示 0258（600 转/分）----
    // 采集顺序是 个位->千位，所以正确结果是 7f 6d 5b 3f = 8,5,2,0
    // ⚠️ 屏幕上到底读成 "0258" 还是 "8520"，取决于 K1 是最左还是最右那一位
    $display("TP3 SEG   : group1 seg = %h %h %h %h  (个位->千位)",
             seg_cap[0], seg_cap[1], seg_cap[2], seg_cap[3]);
    $display("TP3 SEG   : expect      = 7f 6d 5b 3f  (= 8 5 2 0, 即 0x258)");
    $display("TP3 SEG   : group0 seg = %h %h %h %h  (position, 一直在变)",
             seg_cap0[0], seg_cap0[1], seg_cap0[2], seg_cap0[3]);

    // ---- TP6 LED ----
    // led[7:6] = state（正交状态），转子转起来后 0->1->3->2 不停循环，
    //    所以 led[7:0] 的整体值每个瞬间都可能不同（这次是 00100000，下一拍
    //    可能就是 01100000）。断言必须把这两位屏蔽掉，否则就是碰运气。
    //    真正要查的是：bit5 自检源 / bit4 非法跳变 / bit3 丢脉冲 / bit2 超速
    $display("TP6 LED   : led[7:0] = %b  (bit7:6=state varies, not checked)",
             led[7:0]);
    if (led[5] == 1'b1 && led[4] == 1'b0 && led[3] == 1'b0 && led[2] == 1'b0)
        $display("TP6 PASS  : selftest=1, no overspeed / no pulse-loss / no illegal");
    else
        $display("TP6 FAIL  : led=%b (bit5=selftest bit4=err bit3=pulseloss bit2=overspeed)",
                 led[7:0]);

    // ---- TP5 OLED ----
    // 每次刷屏 = 2 次传输（7 字节窗口设置 + 1026 字节显存）。
    // last_bytes 是锁存值，会一直保持到下一次 STOP，所以 wait 一定能等到。
    wait (last_bytes == 1026);
    $display("TP5 OLED  : full screen transfer = %0d bytes (expect 1026) at %0d ns",
             last_bytes, $time);

    // ---- TP4 UART 两帧 ----
    recv_frame;
    t_f1 = t_f0;
    f_r  = {rx[7], rx[8]};
    f_p  = {rx[5][3:0], rx[6]};
    csum = 8'd0;
    for (i = 0; i < 10; i = i + 1) csum = csum + rx[i];
    $display("TP4 UART1 : hdr=%h%h len=%h status=%h sum=%h calc=%h",
             rx[0], rx[1], rx[2], rx[9], rx[10], csum);
    $display("TP4 UART1 : rpm frame=%0d dut=%0d | pos frame=%0d dut=%0d",
             f_r, uut.rpm_filtered, f_p, uut.position);

    recv_frame;
    f_r = {rx[7], rx[8]};
    $display("TP4 UART2 : rpm frame=%0d dut=%0d | period = %0d ns (expect 10000000)",
             f_r, uut.rpm_filtered, t_f0 - t_f1);

    $display("TP5 OLED  : transfers = %0d  (在增长 = OLED 一直在刷屏)", i2c_start_n);
    $display("=== ALL CHECKS DONE ===");
    $finish;
end

endmodule
