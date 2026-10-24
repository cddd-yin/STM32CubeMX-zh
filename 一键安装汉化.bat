@echo off
chcp 936 >nul
title STM32CubeMX 汉化 - 一键安装
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0工具\安装汉化.ps1"
