@echo off
chcp 936 >nul
title STM32CubeMX 汉化 - 一键还原英文
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0工具\还原英文.ps1"
