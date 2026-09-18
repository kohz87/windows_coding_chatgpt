@echo off
setlocal
set "WCA_HOME=%WINDOWS_CODING_AGENT_HOME%"
if "%WCA_HOME%"=="" set "WCA_HOME=%USERPROFILE%\.windows-coding-agent"
if exist "%WCA_HOME%\bin\Start-Agent.cmd" (
  call "%WCA_HOME%\bin\Start-Agent.cmd" %*
  exit /b %ERRORLEVEL%
)
echo Windows Coding Agent is not installed in its managed location.
echo Run Setup.cmd first.
exit /b 1
