@echo off
chcp 65001 >nul
title JTAG Program - SRAM volatile
echo ============================================
echo   JTAG download to SRAM
echo   WARNING: VOLATILE - power off erases it
echo ============================================
echo.
echo   Checklist before running:
echo     1. Board powered on (D18 / D30 lit)
echo     2. Vivado GUI must be CLOSED
echo     3. JP3 jumper in place
echo.
set BIT=E:\project\vivadoprj\vivadoprj.runs\impl_1\board_top_oled.bit
if not exist "%BIT%" (
    echo ERROR: bit file not found:
    echo        %BIT%
    echo.
    echo Run synthesis + implementation first.
    pause
    exit /b 1
)
set OUT=C:\Users\32037\AppData\Local\Temp\flash
if not exist "%OUT%" mkdir "%OUT%"
set TCL=%OUT%\pgm_jtag.tcl
(
echo open_hw_manager
echo connect_hw_server -url localhost:3121
echo set t [get_hw_targets]
echo if {[llength $t] == 0} {
echo     puts "NO_TARGET"
echo     puts "CHECK: power on / JP3 jumper / Vivado GUI must be CLOSED"
echo     close_hw_manager
echo     exit
echo }
echo current_hw_target [lindex $t 0]
echo open_hw_target
echo refresh_hw_target [lindex $t 0]
echo set d [lindex [get_hw_devices] 0]
echo current_hw_device $d
echo refresh_hw_device $d
echo set_property PROGRAM.FILE "%BIT%" $d
echo program_hw_devices $d
echo refresh_hw_device $d
echo puts "JTAG_PROGRAM_OK"
echo close_hw_manager
echo exit
) > "%TCL%"
echo Downloading...
echo.
"D:\Xilinx\2026.1\Vivado\bin\vivado.bat" -mode batch -source "%TCL%" -nojournal -nolog 2>&1 | findstr /C:"27-1434" /C:"JTAG_PROGRAM_OK" /C:"NO_TARGET" /C:"ERROR"
echo.
echo ============================================
pause
