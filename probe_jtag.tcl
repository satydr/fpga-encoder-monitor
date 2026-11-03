# ============================================================================
#  probe_jtag.tcl  ——  只探测，不烧写
#  检查：JTAG 线缆 -> 目标 -> 器件型号 / IDCODE -> bit 文件是否存在
# ============================================================================

set BIT "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bit"

puts "PROBE_BEGIN"
if {[file exists $BIT]} {
    puts "BIT_OK size=[file size $BIT]"
} else {
    puts "BIT_MISSING"
}

if {[catch {open_hw_manager} e]} {
    puts "PROBE_FAIL open_hw_manager: $e"
    exit 1
}
if {[catch {connect_hw_server -url localhost:3121} e]} {
    puts "PROBE_FAIL connect_hw_server: $e"
    close_hw_manager
    exit 1
}

set tgts [get_hw_targets]
puts "TARGET_COUNT=[llength $tgts]"
foreach t $tgts { puts "TARGET=[get_property NAME $t]" }

if {[llength $tgts] == 0} {
    puts "PROBE_RESULT=NO_CABLE"
    puts "  -> 检查：Type-C 线是否插好 / 板子供电(D18,D30亮) / JP3 跳线帽 / Vivado GUI 是否关闭"
    close_hw_manager
    exit 1
}

current_hw_target [lindex $tgts 0]
if {[catch {open_hw_target} e]} {
    puts "PROBE_RESULT=OPEN_TARGET_FAILED"
    close_hw_manager
    exit 1
}

set devs [get_hw_devices]
puts "DEV_COUNT=[llength $devs]"
foreach d $devs {
    puts "DEV=$d PART=[get_property PART $d] IDCODE=[get_property IDCODE $d]"
}

if {[llength $devs] == 0} {
    puts "PROBE_RESULT=NO_DEVICE"
    puts "  -> 线缆认到了但器件为 0：JTAG 链开路，检查 JP3 跳线帽"
    close_hw_manager
    exit 1
}

puts "PROBE_RESULT=OK"
close_hw_manager
puts "PROBE_END"
exit
