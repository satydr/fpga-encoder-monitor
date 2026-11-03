// OLED 显示驱动：SSD1306（128x64，I2C），只画转速波形
// 显存放在 FPGA 内部（1 KB），采用"扫描式"画点：每来一个采样点画一列，走到 127 回到 0 列覆盖
module oled_ssd1306 #(
    parameter BOOT_CYCLES = 24'd10_000_000,   // 上电等待：100 ms @100 MHz
    parameter GAP_CYCLES  = 24'd2_000_000     // 两屏之间的间隔：20 ms
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] rpm,      // 要显示的转速（滤波后，0~1000 对应全屏高度）
    input  wire        tick,     // 1 拍：来了一个新采样点（10 ms 闸门）
    output wire        scl,
    inout  wire        sda
);

localparam DEV_ADDR = 7'h3C;     // SSD1306 的 7 位地址
localparam CMD_N    = 5'd25;     // 初始化序列最后一个字节的序号（共 26 字节）
localparam SET_N    = 3'd6;      // 窗口设置序列最后一个序号（共 7 字节）
localparam DATA_N   = 11'd1024;  // 数据相位最后一个序号（1 字节控制字 + 1024 字节显存）

// ---------- 显存（页优先：地址 = page*128 + col） ----------
reg [7:0]  fb [0:1023];
reg [7:0]  ram_dout;
wire       ram_wen;   // 必须是组合的：与 ram_addr 同拍生效
wire [9:0] ram_addr;
wire [7:0] ram_wdata;

always @(posedge clk) begin
    if (ram_wen) fb[ram_addr] <= ram_wdata;
    ram_dout <= fb[ram_addr];
end

// ---------- 字节表 ----------
function [7:0] init_byte;
    input [4:0] i;
    case (i)
        5'd0:  init_byte = 8'h00;   // 控制字：后面全是命令
        5'd1:  init_byte = 8'hAE;   // 关显示
        5'd2:  init_byte = 8'hD5;
        5'd3:  init_byte = 8'h80;   // 分频/振荡频率
        5'd4:  init_byte = 8'hA8;
        5'd5:  init_byte = 8'h3F;   // 64 行复用
        5'd6:  init_byte = 8'hD3;
        5'd7:  init_byte = 8'h00;   // 显示偏移 0
        5'd8:  init_byte = 8'h40;   // 起始行 0
        5'd9:  init_byte = 8'h8D;
        5'd10: init_byte = 8'h14;   // 打开电荷泵（不打开屏幕不亮）
        5'd11: init_byte = 8'h20;
        5'd12: init_byte = 8'h00;   // 水平寻址：写满一行自动进下一页
        5'd13: init_byte = 8'hA1;   // 段重映射
        5'd14: init_byte = 8'hC8;   // 行扫描方向
        5'd15: init_byte = 8'hDA;
        5'd16: init_byte = 8'h12;   // COM 引脚配置
        5'd17: init_byte = 8'h81;
        5'd18: init_byte = 8'h7F;   // 对比度
        5'd19: init_byte = 8'hD9;
        5'd20: init_byte = 8'hF1;   // 预充电周期
        5'd21: init_byte = 8'hDB;
        5'd22: init_byte = 8'h30;   // VCOMH
        5'd23: init_byte = 8'hA4;   // 显示跟随显存
        5'd24: init_byte = 8'hA6;   // 正常显示（不反色）
        5'd25: init_byte = 8'hAF;   // 开显示
        default: init_byte = 8'h00;
    endcase
endfunction

function [7:0] set_byte;
    input [2:0] i;
    case (i)
        3'd0: set_byte = 8'h00;
        3'd1: set_byte = 8'h21;     // 设置列地址
        3'd2: set_byte = 8'h00;
        3'd3: set_byte = 8'h7F;     // 0 ~ 127
        3'd4: set_byte = 8'h22;     // 设置页地址
        3'd5: set_byte = 8'h00;
        3'd6: set_byte = 8'h07;     // 0 ~ 7
        default: set_byte = 8'h00;
    endcase
endfunction

// ---------- I2C 主机 ----------
wire       i2c_start;      // 进入发命令/发数据状态时给一个启动脉冲
reg  [7:0] i2c_wdata;
reg        i2c_wvalid;
wire       i2c_next, i2c_busy, i2c_done, i2c_ack_err;

i2c_master u_i2c (
    .clk(clk), .rst(rst), .start(i2c_start), .dev_addr(DEV_ADDR),
    .wr_data(i2c_wdata), .wr_valid(i2c_wvalid),
    .wr_next(i2c_next), .busy(i2c_busy), .done(i2c_done), .ack_err(i2c_ack_err),
    .scl(scl), .sda(sda)
);

// ---------- 主状态机 ----------
localparam S_BOOT = 3'd0, S_CLEAR = 3'd1, S_INIT = 3'd2,
           S_SET  = 3'd3, S_DATA = 3'd4, S_GAP  = 3'd5;
reg [2:0]  st = S_BOOT, st_d = S_BOOT;
reg [23:0] boot_cnt = 0;
reg [9:0]  clr_cnt  = 0;
reg [23:0] gap_cnt  = 0;
reg [4:0]  init_idx = 0;
reg [2:0]  set_idx  = 0;
reg [10:0] data_idx = 0;
reg        next_d   = 0;

wire st_enter = (st != st_d);
assign i2c_start = st_enter && (st == S_INIT || st == S_SET || st == S_DATA);

// 字节序号在"装载那一拍"才推进（wr_next 之后一拍），保证主机读到的是当前字节
always @(posedge clk) next_d <= i2c_next;
always @(posedge clk) begin
    if (rst) begin
        init_idx <= 0; set_idx <= 0; data_idx <= 0;
    end else if (st_enter) begin              // 刚进入发数状态：序号归零
        if (st == S_SET)  set_idx  <= 3'd0;
        if (st == S_DATA) data_idx <= 11'd0;
    end else if (next_d) begin
        if      (st == S_INIT) init_idx <= init_idx + 5'd1;
        else if (st == S_SET)  set_idx  <= set_idx  + 3'd1;
        else if (st == S_DATA) data_idx <= data_idx + 11'd1;
    end
end

// 显存读地址：data_idx-1 是当前字节对应的显存单元（0 号是控制字 0x40）
wire [9:0] look_addr = data_idx - 11'd1;
wire [9:0] next_look = data_idx;              // wr_next 时下一个字节要读的地址

always @(*) begin
    if (st == S_INIT) begin
        i2c_wdata  = init_byte(init_idx);
        i2c_wvalid = (init_idx != CMD_N);
    end else if (st == S_SET) begin
        i2c_wdata  = set_byte(set_idx);
        i2c_wvalid = (set_idx != SET_N);
    end else if (st == S_DATA) begin
        i2c_wdata  = (data_idx == 0) ? 8'h40 : ram_dout;   // 控制字：后面全是数据
        i2c_wvalid = (data_idx != DATA_N);
    end else begin
        i2c_wdata  = 8'h00;
        i2c_wvalid = 1'b0;
    end
end

// ---------- 波形绘制 ----------
reg [6:0] wx = 0;          // 当前写到第几列
reg [2:0] dp = 0;          // 正在写第几页
reg       drawing = 0;
reg       draw_req = 0;

wire [9:0] rr = (rpm > 16'd1000) ? 16'd1000 : rpm[9:0];   // 限幅
wire [5:0] yy = 6'd63 - (rr >> 4);                        // rpm 1000 -> y=1，rpm 0 -> y=63
wire [2:0] y_page = yy[5:3];
wire [2:0] y_bit  = yy[2:0];

// 显存地址只有一个来源：清屏 / 画点 / 刷屏读。三者互斥，用组合 MUX 一次定死，
// 千万不要在状态机的不同分支里各写一次 ram_addr（后写的会覆盖先写的）
assign ram_addr  = (st == S_CLEAR) ? clr_cnt
                 : drawing          ? {dp, wx}
                 : (i2c_next ? next_look : look_addr);
assign ram_wen   = (st == S_CLEAR) || drawing;
assign ram_wdata = (st == S_CLEAR) ? 8'h00
                 : ((dp == y_page) ? (8'h01 << y_bit) : 8'h00);

// 安全窗口：刚给完一个字节后主机要等几千拍才会再要，这段空隙可以拿去改显存
reg [4:0] safe_cnt = 5'd31;
always @(posedge clk) begin
    if (i2c_next) safe_cnt <= 5'd0;
    else if (safe_cnt != 5'd31) safe_cnt <= safe_cnt + 5'd1;
end
wire safe = (st != S_DATA) || (safe_cnt > 5'd10);

always @(posedge clk) begin
    st_d <= st;

    case (st)
    S_BOOT: begin                                   // 等 OLED 上电稳定
        if (boot_cnt == BOOT_CYCLES) begin boot_cnt <= 0; st <= S_CLEAR; end
        else boot_cnt <= boot_cnt + 24'd1;
    end

    S_CLEAR: begin                                  // 把本地显存刷成全 0（刷屏时就是清屏）
        if (clr_cnt == 10'd1023) begin clr_cnt <= 0; st <= S_INIT; end
        else clr_cnt <= clr_cnt + 10'd1;
    end

    S_INIT: if (i2c_done) st <= S_SET;              // 发完初始化命令
    S_SET:  if (i2c_done) st <= S_DATA;          // data_idx 由序号块归零
    S_DATA: if (i2c_done) begin gap_cnt <= 0; st <= S_GAP; end

    S_GAP: begin                                    // 两屏之间歇一会儿
        if (gap_cnt == GAP_CYCLES) st <= S_SET;  // set_idx 由序号块归零
        else gap_cnt <= gap_cnt + 24'd1;
    end
    endcase

    // 画一个新点：整列重写 8 个字节（顺带把上一轮的旧点擦掉）
    if (rst) begin
        wx <= 0; dp <= 0; drawing <= 0; draw_req <= 0;
    end else begin
        if (tick) draw_req <= 1'b1;                 // 采样点来了先记下来
        if (drawing) begin
            dp <= dp + 3'd1;
            if (dp == 3'd7) drawing <= 1'b0;
        end else if (draw_req && safe) begin
            draw_req <= 1'b0;
            drawing  <= 1'b1;
            dp       <= 3'd0;
            wx       <= wx + 7'd1;                  // 扫描式：走到 127 自动回到 0
        end
    end
end

endmodule
