@echo off
setlocal
title AI Deep Monitor
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai-deep-monitor.ps1"
if errorlevel 1 (
  echo.
  echo AI Deep Monitor a rencontre une erreur. Le detail est affiche ci-dessus.
  pause
)
