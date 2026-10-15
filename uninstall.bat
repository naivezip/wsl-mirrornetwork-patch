@echo off
title WSL Mirrored Network Patch Uninstaller
cd /d "%~dp0"

net session >nul 2>&1
if %errorLevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
) else (
    echo [*] 正在请求管理员权限...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0uninstall.ps1\"\"' -Verb RunAs"
)
