@echo off
:: Video Tools Suite - Main Entry Point
:: Launches the interactive TUI menu

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\vts.ps1"
if errorlevel 1 pause
