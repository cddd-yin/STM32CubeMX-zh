@echo off
rem 安装 STM32CubeMX 汉化（运行时翻译，不改程序文件；桌面快捷方式直接生效）
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装汉化.ps1" %*
pause
