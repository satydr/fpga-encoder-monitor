@echo off
chcp 65001 >nul
title Flash Program - NON-volatile (survives power off)
echo ============================================
echo   Burn bitstream into SPI Flash
echo   Result: program survives power cycle
echo ============================================
echo.
echo   Checklist before running:
echo     1. Board powered on (D18 / D30 lit)
echo     2. JP3 jumper in place  (JTAG link)
echo     3. Vivado GUI must be CLOSED
echo.
echo   AFTER this script finishes:
echo     4. JP2 jumper -^> QSPI
echo     5. Power off -^> power on -^> check D24 + LED0 heartbeat
echo.
pause

set TCL=E:\project\program_flash.tcl
if not exist "%TCL%" (
    echo ERROR: %TCL% not found
    pause
    exit /b 1
)

echo Running Vivado in batch mode, please wait 1-3 minutes...
echo.
"D:\Xilinx\2026.1\Vivado\bin\vivado.bat" -mode batch -source "%TCL%" -nojournal -nolog 2^>^&1 | findstr /C:"===" /C:"FLASH_PROGRAM_DONE" /C:"FLASH_FAILED" /C:"NO_TARGET" /C:"NO_DEVICE" /C:"ERROR" /C:"SCRIPT_END" /C:"bin size" /C:"part =" /C:"device:"
echo.
echo ============================================
echo   Look for FLASH_PROGRAM_DONE above.
echo   If you see FLASH_FAILED or ERROR, read
echo   the message - most likely flash part model.
echo ============================================
pause
