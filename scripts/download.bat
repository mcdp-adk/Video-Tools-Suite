@echo off
:: YouTube Video Downloader
:: Usage: download.bat <URL or Video ID>

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download.ps1" %*
if errorlevel 1 exit /b 1
