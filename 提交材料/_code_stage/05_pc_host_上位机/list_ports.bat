@echo off
chcp 65001 >nul
"C:/Users/32037/.workbuddy/binaries/python/envs/default/Scripts/python.exe" "%~dp0uart_monitor.py" --list
pause
