@echo off
chcp 65001 >nul
title FPGA Config Console
set PORT=%1
if "%PORT%"=="" set PORT=COM10
echo ========================================
echo   FPGA parameter config  port %PORT%
echo ========================================
echo   speed <rpm>     set overspeed threshold
echo   tol   <count>   set pulse-loss tolerance
echo   clr              clear alarms
echo   show             show status distribution
echo   quit             exit
echo.
echo   NOTE: alarms are latched. If rpm is still above
echo         the threshold, clearing has no effect.
echo         Raise the threshold FIRST, then clear.
echo.
"C:/Users/32037/.workbuddy/binaries/python/envs/default/Scripts/python.exe" "%~dp0fpga_config.py" -p %PORT% -b 115200
pause