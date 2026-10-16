@echo off
REM Haven OS - build from Windows (double-click, or run from a command prompt)
REM   build-windows.bat            full build: kernel + installer + ISO
REM   build-windows.bat iso        rebuild only the ISO
REM   build-windows.bat kernel     build only the kernel
REM   build-windows.bat clean      delete the build files inside WSL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\build-windows.ps1" %*
echo.
pause
