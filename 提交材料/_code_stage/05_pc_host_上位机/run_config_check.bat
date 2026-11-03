@echo off
chcp 65001 >nul
title FPGA Config Self-Check
set PORT=%1
if "%PORT%"=="" set PORT=COM10
echo ========================================
echo   Self-check (board must be running)
echo   1 threshold 700 (> selftest 600) + clear -^> 0
echo   2 threshold 500 (< 600)               -^> 1 overspeed
echo   3 back to 700 + clear                -^> 0
echo ========================================
echo.
"C:/Users/32037/.workbuddy/binaries/python/envs/default/Scripts/python.exe" "%~dp0fpga_config.py" -p %PORT% -b 115200 --check
echo.
pause