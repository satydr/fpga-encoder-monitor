`timescale 1ns / 1ps
module tb_filter;

reg  clk, rst, tick;
reg  [15:0] rpm_in;
wire [15:0] rpm_avg;

enc_filter dut (
    .clk(clk), .rst(rst),
    .tick(tick), .rpm_in(rpm_in), .rpm_avg(rpm_avg)
);

always #5 clk = ~clk;

// 模拟一个闸门结束：给一个 tick，把 rpm_in 送进去
task gate;
    input [15:0] v;
    begin
        @(negedge clk) begin rpm_in = v; tick = 1'b1; end
        @(negedge clk) tick = 1'b0;
        @(posedge clk);
    end
endtask

integer i;

initial begin
    clk = 0; rst = 1; tick = 0; rpm_in = 0;
    #20 rst = 0;

    // ---- TP1：爬坡期。窗口逐渐填满，输出逐级上升 ----
    gate(600); $display("TP1 ramp g1    : rpm_avg=%0d (expect 150, 1/4 filled)", rpm_avg);
    gate(600); $display("TP1 ramp g2    : rpm_avg=%0d (expect 300)", rpm_avg);
    gate(600); $display("TP1 ramp g3    : rpm_avg=%0d (expect 450)", rpm_avg);
    gate(600); $display("TP1 ramp g4    : rpm_avg=%0d (expect 600, window full)", rpm_avg);

    // ---- TP2：稳态。输入恒 600，输出恒 600（无稳态误差）----
    for (i = 0; i < 4; i = i + 1) gate(600);
    $display("TP2 steady     : rpm_avg=%0d (expect 600)", rpm_avg);

    // ---- TP3：抖动输入 597/600 交替（真实 M 法 ±1 计数抖动）----
    $display("TP3 jitter in  : 597 600 597 600 597 600 597 600  (raw jumps 3 rpm)");
    gate(597); gate(600); gate(597); gate(600);
    gate(597); gate(600); gate(597); gate(600);
    $display("TP3 jitter out : rpm_avg=%0d (expect 598, flat, no jump)", rpm_avg);

    // ---- TP4：阶跃 600 -> 0（电机急停），看几个闸门归零 ----
    // 先把窗口里的数据"洗"成纯 600，这样阶跃响应的数字最干净
    for (i = 0; i < 4; i = i + 1) gate(600);
    gate(0); $display("TP4 step g1    : rpm_avg=%0d (expect 450)", rpm_avg);
    gate(0); $display("TP4 step g2    : rpm_avg=%0d (expect 300)", rpm_avg);
    gate(0); $display("TP4 step g3    : rpm_avg=%0d (expect 150)", rpm_avg);
    gate(0); $display("TP4 step g4    : rpm_avg=%0d (expect 0, settled)", rpm_avg);

    $finish;
end

endmodule
