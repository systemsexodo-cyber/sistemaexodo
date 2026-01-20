@echo off
REM Correcao de problemas do Flutter
echo.
echo ============================================================
echo   Corrigindo problemas do Flutter...
echo ============================================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0fix_flutter.ps1"
pause
