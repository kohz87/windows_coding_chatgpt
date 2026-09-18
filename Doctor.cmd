@echo off
setlocal
set "WCA_HOME=%WINDOWS_CODING_AGENT_HOME%"
if "%WCA_HOME%"=="" set "WCA_HOME=%USERPROFILE%\.windows-coding-agent"
if exist "%WCA_HOME%\bin\Doctor.cmd" (
  call "%WCA_HOME%\bin\Doctor.cmd" %*
  exit /b %ERRORLEVEL%
)
cd /d "%~dp0"
where node >nul 2>nul || (
  echo Node.js was not found. Run Install-Dependencies.cmd.
  exit /b 1
)
node src\doctor.js
exit /b %ERRORLEVEL%
