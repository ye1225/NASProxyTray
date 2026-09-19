@echo off
chcp 65001 >nul
cd /d "%~dp0"
title ProxyTray - DEBUG

echo.>> "%~dp0run.log"
echo ========== %date% %time% ==========>> "%~dp0run.log"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { & '%~dp0ProxyTray.ps1' *>&1 | Tee-Object -FilePath '%~dp0run.log' -Append }"

echo.
echo ==============================================
echo  Process finished. Exit code = %errorlevel%
echo  Full output saved to run.log
echo ==============================================
pause
