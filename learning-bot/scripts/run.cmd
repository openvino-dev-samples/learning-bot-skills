@echo off
REM Double-click / CLI wrapper for the Learning Bot launcher skill.
REM Forwards every argument to run.ps1 with ExecutionPolicy bypassed and the user
REM profile skipped (a broken PowerShell profile must not take the skill down with it).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
