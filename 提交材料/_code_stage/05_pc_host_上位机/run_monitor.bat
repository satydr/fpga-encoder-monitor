@echo off
chcp 65001 >nul
set PORT=%1
if "%PORT%"=="" set PORT=COM10
"C:/Users/32037/.workbuddy/binaries/python/envs/default/Scripts/python.exe" "%~dp0uart_monitor.py" -p %PORT% -b 115200 --csv "%~dp0log.csv"
pause
