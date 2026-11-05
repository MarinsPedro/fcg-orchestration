@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\FCG-K8S.ps1" %*
if errorlevel 1 (
  echo.
  echo [FCG] Kubernetes setup FAILED. See error above. Persistent data were not purged.
  exit /b 1
)
