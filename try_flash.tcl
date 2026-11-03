# ============================================================================
#  try_flash.tcl —— 逐个尝试候选 Flash 型号，哪个能烧通就用哪个
#  （EGO1 手册对 Flash 型号说法不一，实测最可靠的办法就是试）
# ============================================================================

set BIT "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bit"
set BIN "E:/project/vivadoprj/vivadoprj.runs/impl_1/board_top_oled.bin"

if {![file exists $BIT]} { puts "ERROR: no bit file"; exit 1 }

puts "=== [1/3] write_cfgmem ==="
catch {write_cfgmem -format bin -size 8 -interface SPIx1 -loadbit "up 0x0 $BIT" -file $BIN -force}
if {![file exists $BIN]} { puts "ERROR: no bin"; exit 1 }
puts "    bin = [file size $BIN] bytes"

puts "=== [2/3] connect ==="
open_hw_manager
connect_hw_server -url localhost:3121
set tgts [get_hw_targets]
if {[llength $tgts] == 0} { puts "NO_CABLE"; close_hw_manager; exit 1 }
current_hw_target [lindex $tgts 0]
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device $dev
puts "    dev = $dev"

set all [lsort -unique [get_cfgmem_parts -of_objects $dev]]

set cands [list \
    "n25q128-3.3v-spi-x1_x2_x4" \
    "s25fl128sxxxxxx0-spi-x1_x2_x4" \
    "s25fl128l-spi-x1_x2_x4" \
    "n25q32-3.3v-spi-x1_x2_x4" \
    "mt25ql128-spi-x1_x2_x4" \
    "mx25l12872f-spi-x1_x2_x4" \
    "mx25l6433f-spi-x1_x2_x4" \
    "s25fl064l-spi-x1_x2_x4" \
    "is25lp128f-spi-x1_x2_x4" \
    "gd25b128e-spi-x1_x2_x4" \
    "mt25ql256-spi-x1_x2_x4" \
    "mx25l25673g-spi-x1_x2_x4" ]

puts "=== [3/3] try each candidate ==="
foreach cand $cands {
    if {[lsearch $all $cand] < 0} {
        puts "  SKIP(not in compat list): $cand"
        continue
    }
    if {[catch {create_hw_cfgmem -hw_device $dev $cand} e]} {
        puts "  CREATE_FAIL: $cand"
        continue
    }
    set cm [current_hw_cfgmem]
    set_property PROGRAM.ADDRESS_RANGE {use_file} $cm
    set_property PROGRAM.BLANK_CHECK  0 $cm
    set_property PROGRAM.ERASE        1 $cm
    set_property PROGRAM.CFG_PROGRAM  1 $cm
    set_property PROGRAM.VERIFY       1 $cm
    set_property PROGRAM.FILE         $BIN $cm
    refresh_hw_device $dev
    if {[catch {program_hw_cfgmem $cm} e2]} {
        puts "  PROGRAM_FAIL: $cand"
        catch {delete_hw_cfgmem $cm} e3
        continue
    }
    puts "  PROGRAM_OK: $cand"
    puts "FLASH_SUCCESS_PART=$cand"
    boot_hw_device $dev
    puts ""
    puts "  烧写成功！请做两步：JP2 跳到 QSPI -> 断电 -> 重新上电"
    puts "  验证：D24 亮 + LED0(F6) 约 1.34s 翻转 + 数码管组1 显示 0258"
    close_hw_manager
    exit 0
}

puts "ALL_CANDIDATES_FAILED"
close_hw_manager
exit 1
