@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul || (
  echo Node.js was not found. Install Node.js 20 or newer and try again.
  exit /b 1
)
if not exist node_modules (
  echo Dependencies are missing. Run Setup.cmd first.
  exit /b 1
)
node src\startup.js
