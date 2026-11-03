@echo off
chcp 65001 >nul
cd /d "%~dp0"
set SRC=_code_stage
set OUT=51528-重要代码.rar

set "RAREXE="
if exist "C:\Program Files\WinRAR\Rar.exe" set "RAREXE=C:\Program Files\WinRAR\Rar.exe"
if not defined RAREXE if exist "C:\Program Files (x86)\WinRAR\Rar.exe" set "RAREXE=C:\Program Files (x86)\WinRAR\Rar.exe"
if not defined RAREXE if exist "%LOCALAPPDATA%\Programs\WinRAR\Rar.exe" set "RAREXE=%LOCALAPPDATA%\Programs\WinRAR\Rar.exe"

if not defined RAREXE (
  echo.
  echo   [!] 未检测到 WinRAR，无法生成 .rar
  echo.
  echo   两种解决办法：
  echo     1. 安装 WinRAR 后重新双击本脚本（rar 是专有格式，无 WinRAR 无法创建）
  echo     2. 直接使用同目录下的  51528-重要代码.zip  /  .7z  提交
  echo.
  pause
  exit /b 1
)

"%RAREXE%" a -r -ep1 -m5 "%OUT%" "%SRC%\*"
echo.
echo   [OK] 已生成 %OUT%
echo.
pause
