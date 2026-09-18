@echo off
setlocal
set "WCA_HOME=%WINDOWS_CODING_AGENT_HOME%"
if "%WCA_HOME%"=="" set "WCA_HOME=%USERPROFILE%\.windows-coding-agent"
if exist "%WCA_HOME%\bin\Update.cmd" (
  call "%WCA_HOME%\bin\Update.cmd" %*
  exit /b %ERRORLEVEL%
)
cd /d "%~dp0"
where powershell >nul 2>nul || (
  echo Windows PowerShell was not found.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1" %*
exit /b %ERRORLEVEL%
