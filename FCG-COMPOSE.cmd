@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\FCG-Compose.ps1" %*
if errorlevel 1 (
  echo.
  echo [FCG] Compose setup FAILED. See error above; data were not purged.
  exit /b 1
)
