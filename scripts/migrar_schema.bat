@echo off
rem ============================================================
rem  MIGRAR SCHEMA - Sistema Exodo
rem  Corrige o banco local (uuid -> text) para sincronizar
rem  com a nuvem. Pode rodar quantas vezes quiser.
rem ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0migrar_schema.ps1"
echo.
pause
