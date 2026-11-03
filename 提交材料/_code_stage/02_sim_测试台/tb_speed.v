`timescale 1ns / 1ps
module tb_speed;

reg  clk, rst;
reg  step_up, step_dn;
reg  run_en;                 // 1 = 电机在转，0 = 电机停
wire [15:0] pulse_num;
wire [15:0] rpm;

enc_speed dut (
    .clk(clk), .rst(rst),
    .step_up(step_up), .step_dn(step_dn),
    .pulse_num(pulse_num), .rpm(rpm)
);

always #5 clk = ~clk;

// 脉冲发生器：每 4167 拍给一个 step_up。
// 4167 拍 = 41.67 us = 24 kHz -- 正是 600 转/分 四倍频后的真实脉冲率
reg [12:0] div;
always @(posedge clk) begin
    if (rst) begin
        div     <= 13'd0;
        step_up <= 1'b0;
    end else if (!run_en) begin
        div     <= 13'd0;
        step_up <= 1'b0;
    end else if (div == 13'd4166) begin
        div     <= 13'd0;
        step_up <= 1'b1;
    end else begin
        div     <= div + 13'd1;
        step_up <= 1'b0;
    end
end

initial begin
    clk = 0; rst = 1; step_dn = 0; run_en = 1;
    #20 rst = 0;

    #10000200;                    
    $display("TP1 running : pulse_num=%0d rpm=%0d", pulse_num, rpm);

    run_en = 0;                      
    #10000200;                     
    $display("TP2 stopped : pulse_num=%0d rpm=%0d (expect 0 0)", pulse_num, rpm);

    $finish;
end

endmodule
