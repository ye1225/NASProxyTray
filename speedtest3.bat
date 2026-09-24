@echo off
rem NASProxyTray speed test - 3 rounds (global / rule / off)
chcp 65001 >nul
title NASProxyTray SpeedTest
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
    py -3 -u speedtest3.py
    goto :end
)
where python >nul 2>nul
if %errorlevel%==0 (
    python -u speedtest3.py
    goto :end
)
echo [ERROR] Python not found. Please install Python 3 from python.org
echo         (check "Add python.exe to PATH" during install)
pause
:end
