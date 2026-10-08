@echo off
rem 收集模式：正常使用 CubeMX，未翻译文字自动记入 %ProgramData%\stm32zh\发现-未翻译.tsv
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0安装汉化.ps1" -Discover %*
pause
