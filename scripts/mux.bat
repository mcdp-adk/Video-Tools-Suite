@echo off
:: Subtitle Muxer
:: Usage: mux.bat <video_file> <subtitle_file>

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mux.ps1" %*
if errorlevel 1 exit /b 1
