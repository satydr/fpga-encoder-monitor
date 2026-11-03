# ============================================================================
#  program_board.tcl  ——  命令行烧板（不用来回点 GUI）
#
#  用法（Vivado Tcl Console 里，或命令行）：
#      vivado -mode batch -source E:/project/program_board.tcl
#
#  做三件事：
#    1. 连 hw_server，列出 JTAG 目标与器件（确认板子真的被认出来）
#    2. 烧 vivadoprj.runs/impl_1/board_top_oled.bit 到 FPGA
#    3. 回读 DONE 状态确认成功
#
#  ⚠️ 烧之前先确认：
#    - 板子用 Type-C 线接到电脑，且已上电（D18、D30 常亮）
#    - JP3 跳线帽已装上（不装 = JTAG 链路开路，TDO 恒高，连不上）
# ============================================================================

set BIT "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bit"

if {![file exists $BIT]} {
    puts "ERROR: bitstream not found: $BIT"
    exit 1
}

open_hw_manager
connect_hw_server -url localhost:3121

set tgts [get_hw_targets]
puts "=== JTAG targets found: [llength $tgts] ==="
foreach t $tgts { puts "  $t" }

if {[llength $tgts] == 0} {
    puts ""
    puts "!! NO JTAG CABLE DETECTED !!"
    puts "   按顺序检查："
    puts "   1) Type-C 线是否插好、板子是否上电（D18 / D30 应常亮）"
    puts "   2) JP3 跳线帽是否装上（这是之前连不上的根因）"
    puts "   3) 设备管理器里有没有出现 FTDI 设备（VID_0403）"
    puts "   4) 若 hw_server 卡住：taskkill /F /IM hw_server.exe 后重试"
    exit 1
}

current_hw_target [lindex $tgts 0]
open_hw_target

set devs [get_hw_devices]
puts "=== devices: [llength $devs] ==="
foreach d $devs {
    puts "  $d  PART=[get_property PART $d]  IDCODE=[get_property IDCODE $d]"
}

if {[llength $devs] == 0} {
    puts "!! cable found but NO device -- JTAG chain open (check JP3 jumper) !!"
    exit 1
}

set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev

puts "=== programming $BIT ==="
set_property PROGRAM.FILE $BIT $dev
set_property PROBES.FILE   {}  $dev
program_hw_devices $dev
refresh_hw_device  $dev

# ⚠️ Vivado 2026.1 里 PROGRAM.HW_STATUS 属性已被取消（报 [Labtoolstcl 44-56]）。
#    改用「program_hw_devices 不抛异常 + 回读 DONE 引脚」来判断。
set st "UNKNOWN"
if {![catch {set st [get_property PROGRAM.HW_STATUS $dev]} e]} {
    puts "=== DONE status: $st ==="
} else {
    # 退而求其次：读 DONE 引脚（配置完成引脚，烧成功后应为 1）
    if {![catch {set dn [get_property DONE $dev]} e2]} {
        puts "=== DONE pin = $dn ==="
        set st $dn
    } else {
        puts "=== (status property unavailable, assume OK if no error above) ==="
        set st "NO_ERROR"
    }
}

if {[string match "*DONE*" $st] || [string match "*programmed*" $st]
    || $st eq "1" || $st eq "NO_ERROR"} {
    puts ""
    puts "PROGRAM SUCCESS -- 现在去看板子："
    puts "  1) LED0  (v2.2 丝印 D2_7, 引脚 F6)  约 1.34 s 翻转一次  <- 证明在跑"
    puts "  2) 数码管组1 应显示 0258 (=600 转/分)                   <- 若是 8520 说明位序反了"
    puts "  3) OLED 应出现从左往右滚动的转速波形"
    puts "  4) D24 (配置完成灯) 应点亮"
} else {
    puts "PROGRAM FAILED -- status = $st"
}

close_hw_manager
puts "SCRIPT_END"
exit
