@echo off
setlocal
cd /d "%~dp0"
echo Updating Windows Coding Agent from the current Git branch...
git pull --ff-only || exit /b 1
call npm install || exit /b 1
call npm test || exit /b 1
call npm run validate || exit /b 1
echo Update complete.
