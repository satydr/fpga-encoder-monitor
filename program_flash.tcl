# ============================================================================
#  program_flash.tcl  ——  把程序烧进 SPI Flash（断电不丢 / 脱机演示用）
#
#  用法：
#      vivado -mode batch -source E:/project/program_flash.tcl
#  或双击同目录的 burn_flash.bat
#
#  做四件事：
#    1. 由 .bit 生成 .bin（write_cfgmem，SPIx1，8 MB）
#    2. 连 JTAG，确认板子被认出来
#    3. 擦除 + 烧写 + 校验 SPI Flash
#    4. 重新从 Flash 启动 FPGA
#
#  烧完之后你必须手动做两步（脚本做不了，是硬件动作）：
#    A. JP2 跳线帽跳到 QSPI 位置
#    B. 断电 -> 重新上电 -> 看 D24 亮 + LED0 心跳闪烁 + 数码管显示 0258
#
#  ⚠️ 前置检查：
#    - Type-C 线插好、板子上电（D18 / D30 常亮）
#    - JP3 跳线帽已装上（不装 = JTAG 链路开路，连不上）
#    - Vivado GUI 必须关闭（会抢占 JTAG）
# ============================================================================

set BIT "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bit"
set BIN "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bin"

if {![file exists $BIT]} {
    puts "ERROR: bitstream not found: $BIT"
    puts "       请先综合 + 实现（Generate Bitstream）"
    exit 1
}

# ---------------------------------------------------------------- 1. 生成 .bin
puts "=== [1/4] write_cfgmem: bit -> bin ==="
if {[catch {
    write_cfgmem -format bin -size 8 -interface SPIx1 \
        -loadbit "up 0x0 $BIT" -file $BIN -force
} e]} {
    puts "ERROR: write_cfgmem failed: $e"
    exit 1
}
if {![file exists $BIN]} {
    puts "ERROR: bin not generated: $BIN"
    exit 1
}
puts "    bin size = [file size $BIN] bytes"

# ---------------------------------------------------------------- 2. 连 JTAG
puts "=== [2/4] connect JTAG ==="
open_hw_manager
connect_hw_server -url localhost:3121

set tgts [get_hw_targets]
puts "    targets: [llength $tgts]"
if {[llength $tgts] == 0} {
    puts "NO_TARGET -- 检查：Type-C 线 / 板子供电(D18,D30) / JP3 跳线 / Vivado GUI 是否关闭"
    close_hw_manager
    exit 1
}
current_hw_target [lindex $tgts 0]
open_hw_target

set devs [get_hw_devices]
if {[llength $devs] == 0} {
    puts "NO_DEVICE -- 线缆认到了但器件为 0，JTAG 链开路，检查 JP3"
    close_hw_manager
    exit 1
}
set dev [lindex $devs 0]
current_hw_device $dev
refresh_hw_device $dev
puts "    device: $dev  PART=[get_property PART $dev]  IDCODE=[get_property IDCODE $dev]"

# ------------------------------------------------- 3. 建立 Flash 编程对象
puts "=== [3/4] create cfgmem (N25Q64 x1-single, 逐个回退) ==="
# Vivado 的 cfgmem 器件名必须带接口后缀，例如 n25q64-3.3v-qspi-x1-single
# Vivado 2026.1 里 Artix-7 兼容的写法是旧命名：n25q64-3.3v-spi-x1_x2_x4
set all [lsort -unique [get_cfgmem_parts -of_objects $dev]]
puts "    compatible parts: [llength $all]"
set cands [list "n25q64-3.3v-spi-x1_x2_x4" \
                "n25q32-3.3v-spi-x1_x2_x4" \
                "n25q128-3.3v-spi-x1_x2_x4" \
                "s25fl128sxxxxxx0-spi-x1_x2_x4" \
                "s25fl064l-spi-x1_x2_x4"]
set cand_ok ""
foreach cand $cands {
    if {[lsearch $all $cand] < 0} { continue }
    if {[catch {create_hw_cfgmem -hw_device $dev $cand} e]} {
        puts "    try $cand -> NOT SUPPORTED"
        catch {delete_hw_cfgmem [current_hw_cfgmem]} e2
        continue
    } else {
        puts "    try $cand -> OK"
        set cand_ok $cand
        break
    }
}
if {$cand_ok eq ""} {
    puts "CFG_FAILED_NO_PART -- 命令行下无可用型号，请改用 Vivado GUI："
    puts "   Tools -> Add Configuration Memory Device -> 选实际型号 -> Program"
    close_hw_manager
    exit 1
}
set cm [current_hw_cfgmem]

set_property PROGRAM.ADDRESS_RANGE {use_file} $cm
set_property PROGRAM.BLANK_CHECK  0          $cm
set_property PROGRAM.ERASE        1          $cm
set_property PROGRAM.CFG_PROGRAM  1          $cm
set_property PROGRAM.VERIFY       1          $cm
set_property PROGRAM.FILE         $BIN       $cm
refresh_hw_device $dev

# ---------------------------------------------------------------- 4. 烧写
puts "=== [4/4] programming flash (erase + program + verify) ==="
if {[catch {program_hw_cfgmem $cm} e]} {
    puts "FLASH_FAILED: $e"
    puts "  常见原因：Flash 型号不符（改脚本里的 n25q64 / n25q32）或 JP3 未装"
    close_hw_manager
    exit 1
}
puts "FLASH_PROGRAM_DONE"

boot_hw_device $dev
puts ""
puts "=========================================================="
puts " 烧写完成。现在做两个硬件动作："
puts "   A. JP2 跳线帽 -> QSPI"
puts "   B. 断电 -> 重新上电"
puts " 验证：D24 亮 + LED0(F6) 约 1.34 s 翻转 + 数码管组1 显示 0258"
puts "       （若显示 8520 说明位序反了，见技术报告 6.2 节）"
puts "=========================================================="

close_hw_manager
puts "SCRIPT_END"
exit
