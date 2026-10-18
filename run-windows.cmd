@echo off
setlocal
set "RTL_ROOT=%~dp0"
if not exist "%RTL_ROOT%.tools\tcl\bin\wish86.exe" (
    echo Install dependencies first:
    echo powershell -ExecutionPolicy Bypass -File scripts\install-windows-dependencies.ps1
    exit /b 1
)
start "RTL Explorer" "%RTL_ROOT%.tools\tcl\bin\wish86.exe" "%RTL_ROOT%src\main.tcl"
