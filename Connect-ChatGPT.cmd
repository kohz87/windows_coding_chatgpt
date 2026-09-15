@echo off
setlocal
cd /d "%~dp0"
where powershell >nul 2>nul || (
  echo Windows PowerShell was not found.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Connect-ChatGPT.ps1" %*
