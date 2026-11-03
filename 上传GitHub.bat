@echo off
cd /d E:\project

rem ---- 强制直连: 本机 127.0.0.1 的代理访问 GitHub 会返回 502 ----
set http_proxy=
set https_proxy=
set all_proxy=

rem ---- 找 git ----
set "GIT=D:\workbuddy\resources\vendor\PortableGit\mingw64\bin\git.exe"
if not exist "%GIT%" set "GIT=C:\Program Files\Git\bin\git.exe"
if not exist "%GIT%" set "GIT=C:\Program Files\Git\cmd\git.exe"
if not exist "%GIT%" goto NOGIT

echo ============================================================
echo   上传 FPGA 编码器项目到 GitHub   (组号 51528)
echo ============================================================
echo.
echo   还没有仓库? 到 github.com 新建空仓库, 选 Public,
echo   不要勾选 README / .gitignore / license,
echo   然后把页面上的 HTTPS 地址粘到下面.
echo.
echo   提示: 窗口内点右键即粘贴
echo ------------------------------------------------------------
set /p REPO=仓库地址:
echo ------------------------------------------------------------

if "%REPO%"=="" goto NOREPO

echo.
echo [0/3] 先测试能不能连上 GitHub (约 10 秒) ...
"%GIT%" -c http.proxy= -c https.proxy= ls-remote %REPO% >nul 2>&1
if errorlevel 1 goto NETFAIL
echo         网络正常, 开始上传.

echo.
echo [1/3] 关联远程仓库 ...
"%GIT%" remote remove origin 2>nul
"%GIT%" remote add origin %REPO%
"%GIT%" branch -M main

echo.
echo [2/3] 正在推送 135 个文件 (约 26 MB), 请稍候 ...
echo       弹出登录窗口时:
echo         用户名 = 你的 GitHub 用户名 (satydr)
echo         密码   = 令牌 github_pat_... (不是账号密码)
echo       若弹出浏览器, 直接登录 GitHub 授权即可
echo.
"%GIT%" -c http.proxy= -c https.proxy= push -u origin main

echo.
echo [3/3] 结束. 出现 "Branch main set up to track" 即为成功.
echo.
echo 若上面有红色报错, 请不要关窗口, 把报错拍下来发给我.
echo.
pause
exit /b

:NETFAIL
echo.
echo   x 连不上 GitHub. 常见原因: 校园网/宽带屏蔽, 或网络抽风.
echo     三招任选其一:
echo     1) 手机开热点, 电脑连上后再双击本文件 (最灵)
echo     2) 等几分钟再试一次 (刚才测试时就是时好时坏)
echo     3) 换 Gitee: 到 gitee.com 建仓库, 地址填 gitee 的即可
echo.
pause
exit /b

:NOGIT
echo.
echo   没找到 git. 请在 PowerShell 里跑这一行安装:
echo   winget install --id Git.Git -e
echo.
pause
exit /b

:NOREPO
echo.
echo   地址是空的, 什么都没做. 重新双击本文件再试一次.
echo.
pause
exit /b
