`timescale 1ns / 1ps
// =============================================================================
//  tb_cmd_rx.v  --  cmd_rx 的测试台
//
//  直接喂 rx_valid/rx_data（跳过 uart_rx，专注协议解析）
//
//  ⚠️ 2026-10-05 增加 TP7 / TP8：帧头必须 AA 55 成对。
//     旧版本 S_SYNC 只吃 1 个字节，把 0x55 当成指令，真机上所有命令都被丢弃
//     （表现为"阈值改了没反应""远程清报警无效"）。这两个用例钉死这个 bug。
//
//  测试点：
//    TP1  合法 4E 帧 -> speed_limit 改成 900
//    TP2  合法 50 帧 -> z_gap_tol 改成 350
//    TP3  校验和错的 4E 帧 -> speed_limit 不变
//    TP4  合法 43 帧 -> clr_pulse 拉高一拍
//    TP5  连续两帧 -> 两次都生效
//    TP6  边界值 0 与 65535
//    TP7  残缺帧头（只有 AA）-> 丢弃
//    TP8  帧头颠倒（55 AA）  -> 丢弃
// =============================================================================
module tb_cmd_rx;

reg clk = 1'b0;
reg rst = 1'b1;

reg        rx_valid = 1'b0;
reg [7:0]  rx_data  = 8'd0;

wire [15:0] speed_limit;
wire [15:0] z_gap_tol;
wire        clr_pulse;
wire        ack_pulse;
wire [7:0]  last_cmd;
wire [15:0] last_param;

integer     ack_n = 0;
integer     clr_n = 0;
integer     fail  = 0;

cmd_rx uut (
    .clk         (clk),
    .rst         (rst),
    .rx_valid    (rx_valid),
    .rx_data     (rx_data),
    .speed_limit (speed_limit),
    .z_gap_tol   (z_gap_tol),
    .clr_pulse   (clr_pulse),
    .ack_pulse   (ack_pulse),
    .last_cmd    (last_cmd),
    .last_param  (last_param)
);

always #5 clk = ~clk;              // 100 MHz

task put(input [7:0] b);
    begin
        @(negedge clk);
        rx_valid = 1'b1;
        rx_data  = b;
        @(negedge clk);
        rx_valid = 1'b0;
    end
endtask

task put_frame(input [7:0] cmd, input [7:0] dh, input [7:0] dl);
    reg [7:0] s;
    begin
        s = cmd + dh + dl;
        put(8'hAA);
        put(8'h55);
        put(cmd);
        put(dh);
        put(dl);
        put(s);
    end
endtask

task put_frame_bad(input [7:0] cmd, input [7:0] dh, input [7:0] dl);
    begin
        put(8'hAA);
        put(8'h55);
        put(cmd);
        put(dh);
        put(dl);
        put(8'hEE);
    end
endtask

// 只有 AA 没有 55 的残缺帧头
task put_frame_short_hdr(input [7:0] cmd, input [7:0] dh, input [7:0] dl);
    begin
        put(8'hAA);
        put(cmd);
        put(dh);
        put(dl);
        put(8'h00);
    end
endtask

// 帧头顺序颠倒 55 AA
task put_frame_rev_hdr(input [7:0] cmd, input [7:0] dh, input [7:0] dl);
    begin
        put(8'h55);
        put(8'hAA);
        put(cmd);
        put(dh);
        put(dl);
        put(8'h00);
    end
endtask

always @(posedge clk) begin
    if (ack_pulse) ack_n = ack_n + 1;
    if (clr_pulse) clr_n = clr_n + 1;
end

task check(input [8*12:1] name, input integer cond);
    begin
        if (cond) $display("  %0s  PASS", name);
        else begin
            $display("  %0s  FAIL", name);
            fail = fail + 1;
        end
    end
endtask

initial begin
    $display("=== cmd_rx 测试开始 ===");

    #200;
    rst = 1'b0;
    #100;

    $display("初值: speed_limit=%0d  z_gap_tol=%0d", speed_limit, z_gap_tol);

    ack_n = 0;
    put_frame(8'h4E, 8'h03, 8'h84);          // 900
    #100;
    $display("TP1 4E 帧      -> speed_limit=%0d (expect 900)  ack=%0d", speed_limit, ack_n);
    check("TP1", (speed_limit==16'd900) && (ack_n==1));

    ack_n = 0;
    put_frame(8'h50, 8'h01, 8'h5E);          // 350
    #100;
    $display("TP2 50 帧      -> z_gap_tol=%0d (expect 350)  ack=%0d", z_gap_tol, ack_n);
    check("TP2", (z_gap_tol==16'd350) && (ack_n==1));

    put_frame_bad(8'h4E, 8'h07, 8'h08);      // 2000 但校验和错
    #100;
    $display("TP3 坏校验     -> speed_limit=%0d (expect 900 不变)", speed_limit);
    check("TP3", speed_limit==16'd900);

    clr_n = 0;
    put_frame(8'h43, 8'h00, 8'h00);
    #100;
    $display("TP4 43 帧      -> clr_pulse=%0d (expect 1)", clr_n);
    check("TP4", clr_n==1);

    ack_n = 0;
    put_frame(8'h4E, 8'h02, 8'h58);          // 600
    put_frame(8'h4E, 8'h04, 8'hE0);          // 1248
    #100;
    $display("TP5 连续两帧   -> speed_limit=%0d (expect 1248)  ack=%0d", speed_limit, ack_n);
    check("TP5", (speed_limit==16'd1248) && (ack_n==2));

    put_frame(8'h4E, 8'h00, 8'h00);
    #50;
    $display("TP6a 设 0      -> speed_limit=%0d", speed_limit);
    check("TP6a", speed_limit==16'd0);

    put_frame(8'h4E, 8'hFF, 8'hFF);
    #50;
    $display("TP6b 设 65535  -> speed_limit=%0d", speed_limit);
    check("TP6b", speed_limit==16'd65535);

    put_frame_short_hdr(8'h4E, 8'h03, 8'hC8);  // 968
    #100;
    $display("TP7 只有 AA    -> speed_limit=%0d (expect 65535 不变)", speed_limit);
    check("TP7", speed_limit==16'd65535);

    put_frame_rev_hdr(8'h4E, 8'h01, 8'h00);    // 256
    #100;
    $display("TP8 帧头 55 AA -> speed_limit=%0d (expect 65535 不变)", speed_limit);
    check("TP8", speed_limit==16'd65535);

    if (fail == 0) $display("=== cmd_rx 全部测试点 PASS ===");
    else           $display("=== cmd_rx 有 %0d 项 FAIL ===", fail);
    $display("=== cmd_rx 测试结束 ===");
    $finish;
end

initial begin
    #1_000_000;
    $display("!! TIMEOUT");
    $finish;
end

endmodule
