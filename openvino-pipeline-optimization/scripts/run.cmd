@echo off
REM Double-click / CLI wrapper for the OpenVINO Pipeline Optimization skill.
REM Passes all arguments through to run.ps1 with ExecutionPolicy bypassed and the user
REM profile skipped (a broken PowerShell profile must not take the skill down with it).
setlocal
set "HERE=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%run.ps1" %*
endlocal
