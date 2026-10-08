@echo off
rem 还原 STM32CubeMX 英文界面
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0还原英文.ps1" %*
pause
