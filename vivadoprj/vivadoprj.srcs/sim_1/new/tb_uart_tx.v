`timescale 1ns / 1ps
module tb_uart_tx;

reg        clk, rst;
reg        tx_start;
reg  [7:0] tx_data;
wire       tx;
wire       tx_busy;

uart_tx dut (
    .clk(clk), .rst(rst),
    .tx_start(tx_start), .tx_data(tx_data),
    .tx(tx), .tx_busy(tx_busy)
);

always #5 clk = ~clk;

parameter integer BIT_NS = 8680;   // 1 位 = 868 拍 x 10 ns

time      t1, t2;
integer   k;
reg [7:0] rx_byte;

task start_frame;
    input [7:0] d;
    begin
        @(negedge clk) begin tx_data = d; tx_start = 1'b1; end
        @(negedge clk) tx_start = 1'b0;
    end
endtask

// ⚠️ 必须等上一帧彻底发完，否则 tx_start 会被无声忽略
task wait_frame;
    begin
        @(negedge tx_busy);
        #(BIT_NS);
    end
endtask

task recv_byte;
    output [7:0] b;
    integer      j;
    begin
        @(negedge tx);
        #(BIT_NS + BIT_NS/2);            // 跳到 bit0 中点
        for (j = 0; j < 8; j = j + 1) begin
            b[j] = tx;
            #BIT_NS;
        end
    end
endtask

initial begin
    clk = 0; rst = 1; tx_start = 0; tx_data = 8'h00;
    #20 rst = 0;
    #200;

    // ---------- TP1：发送 0xA3，逐位采样还原 ----------
    start_frame(8'hA3);
    @(negedge tx); t1 = $time;
    #(BIT_NS + BIT_NS/2);
    for (k = 0; k < 8; k = k + 1) begin
        rx_byte[k] = tx;
        #BIT_NS;
    end
    $display("TP1 send A3 : rx_byte=%h (expect a3)  start at %0d ns", rx_byte, t1);
    wait_frame;

    // ---------- TP2：发 0x00 量位宽（数据位全 0 -> 起始位到停止位正好 9 位）----------
    start_frame(8'h00);
    @(negedge tx); t1 = $time;
    @(posedge tx); t2 = $time;
    $display("TP2 bit width: %0d ns (expect 78120 = 9 x 8680 ns, 115200 bps)", t2 - t1);
    wait_frame;

    // ---------- TP3：再发 0x0F，检查 LSB 先发 ----------
    start_frame(8'h0F);
    recv_byte(rx_byte);
    $display("TP3 send 0F : rx_byte=%h (expect 0f)  busy=%b (expect 1)", rx_byte, tx_busy);
    wait_frame;

    // ---------- TP4：帧结束后 tx_busy 归零、tx 回到空闲高电平 ----------
    $display("TP4 idle    : tx=%b tx_busy=%b (expect 1 0)", tx, tx_busy);

    $finish;
end

endmodule
