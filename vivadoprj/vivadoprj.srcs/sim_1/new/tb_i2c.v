`timescale 1ns / 1ps
// I2C 主机测试台：带一个"会拉 ACK 的假从机"，把线上波形还原回字节
module tb_i2c;

reg clk = 0;
reg rst = 1;
reg       start    = 0;
reg [6:0] dev_addr = 7'h3C;     // SSD1306
reg [7:0] wr_data  = 8'h00;
reg       wr_valid = 0;
wire      wr_next, busy, done, ack_err;
wire      scl;
wire      sda;

i2c_master uut (
    .clk(clk), .rst(rst), .start(start), .dev_addr(dev_addr),
    .wr_data(wr_data), .wr_valid(wr_valid),
    .wr_next(wr_next), .busy(busy), .done(done), .ack_err(ack_err),
    .scl(scl), .sda(sda)
);

always #5 clk = ~clk;            // 100 MHz

// ---------- 假从机：只在第 9 个 SCL 上升沿（ACK 位）把 SDA 拉低 ----------
reg [3:0] edge_cnt = 0;
reg scl_d = 1, sda_d = 1;
reg ack_drive = 0;
reg slave_nack = 0;              // 置 1 则不应答，用来测 ack_err

wire scl_rise =  scl & ~scl_d;
wire scl_fall = ~scl &  scl_d;
wire sda_rise =  sda & ~sda_d;
wire sda_fall = ~sda &  sda_d;

always @(posedge clk) begin
    scl_d <= scl;
    sda_d <= sda;
end

always @(posedge clk) begin
    if (scl & sda_fall) edge_cnt <= 4'd0;            // START 条件：重新数
    else if (scl_rise) begin
        if (edge_cnt == 4'd8) ack_drive <= ~slave_nack;
        edge_cnt <= (edge_cnt == 4'd8) ? 4'd0 : edge_cnt + 4'd1;
    end
    if (scl_fall) ack_drive <= 1'b0;                 // ACK 只在 SCL 高期间有效
end

assign sda = ack_drive ? 1'b0 : 1'bz;               // 开漏，与主机"线与"
pullup(sda);                                        // 总线必须有上拉，否则线上是 z 不是 1
pullup(scl);

// ---------- 波形还原：SCL 上升沿采 SDA ----------
reg [7:0] rx_byte = 0;
integer   byte_n = 0;
always @(posedge clk) begin
    if (scl_rise && edge_cnt != 4'd8) rx_byte <= {rx_byte[6:0], sda};
    if (scl_rise && edge_cnt == 4'd8) begin
        $display("%0d ns : byte[%0d] = %02h", $time, byte_n, rx_byte);
        byte_n = byte_n + 1;
    end
end

// ---------- 量 SCL 周期 ----------
integer t_rise1 = 0, t_rise2 = 0;
integer rise_n = 0;
always @(posedge clk) if (scl_rise) begin
    rise_n = rise_n + 1;
    if (rise_n == 1) t_rise1 = $time;
    if (rise_n == 2) t_rise2 = $time;
end

// ---------- START / STOP 条件 ----------
integer t_start = 0, t_stop = 0;
always @(posedge clk) begin
    if (start) begin
        t_start = $time; $display("%0d ns : transfer launched", $time);
    end
    if (scl & sda_rise && busy) begin
        t_stop  = $time; $display("%0d ns : STOP",  $time);
    end
end

integer t_done = 0;
reg ack_err_seen = 0;          // ack_err 只有 1 拍，必须用 sticky 标志捕获
always @(posedge clk) if (ack_err) begin ack_err_seen <= 1'b1; $display("%0d ns : ack_err raised", $time); end
always @(posedge clk) if (done) begin t_done = $time; $display("%0d ns : done", $time); end

initial begin
    $display("=== TP1: send 2 bytes 0x00 0xA5 to SSD1306 (addr 7'h3C) ===");
    rst = 1; #200; rst = 0; #100;
    wr_data = 8'h00; wr_valid = 1'b1;
    @(negedge clk); start = 1'b1;                 // 激励一律在 negedge 给，避免与采样竞争
    @(negedge clk); start = 1'b0;

    @(posedge wr_next);            // 主机要第二个字节
    wr_data = 8'hA5; wr_valid = 1'b0;
    @(posedge done);
    #200;
    $display("SCL period  = %0d ns (expect 10000)", t_rise2 - t_rise1);
    $display("done at %0d ns, stop at %0d ns", t_done, t_stop);

    $display("=== TP2: slave NACK -> ack_err ===");
    #1000;
    slave_nack = 1'b1;
    byte_n = 0; rise_n = 0; ack_err_seen = 0;
    wr_data = 8'h40; wr_valid = 1'b0;
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge done);
    #200;
    $display("ack_err_seen = %0d (expect 1)", ack_err_seen);
    $display("bytes seen   = %0d (expect 1: only addr, then NACK)", byte_n);
    $finish;
end

initial begin
    #2000000;
    $display("!! timeout");
    $finish;
end

endmodule
