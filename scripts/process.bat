@echo off
:: Subtitle Text Processor
:: Usage: process.bat <subtitle_file>

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0process.ps1" %*
if errorlevel 1 exit /b 1
