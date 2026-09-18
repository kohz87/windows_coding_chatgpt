@echo off
setlocal
cd /d "%~dp0"
where powershell >nul 2>nul || (
  echo Windows PowerShell was not found.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Dependencies.ps1" -RequiredOnly
if errorlevel 1 exit /b %ERRORLEVEL%

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1" -InstallCurrent -Yes
if errorlevel 1 exit /b %ERRORLEVEL%

set "WCA_HOME=%WINDOWS_CODING_AGENT_HOME%"
if "%WCA_HOME%"=="" set "WCA_HOME=%USERPROFILE%\.windows-coding-agent"
if not exist "%WCA_HOME%\bin\Setup.cmd" (
  echo Managed launcher was not created.
  exit /b 1
)

call "%WCA_HOME%\bin\Setup.cmd"
exit /b %ERRORLEVEL%
