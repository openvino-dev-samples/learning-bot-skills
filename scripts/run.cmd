@echo off
REM Double-click / CLI wrapper for the OpenVINO Pipeline Optimization skill.
REM Passes all arguments through to run.ps1 with ExecutionPolicy bypassed.
setlocal
set "HERE=%~dp0"
powershell -ExecutionPolicy Bypass -File "%HERE%run.ps1" %*
endlocal
