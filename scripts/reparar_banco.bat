@echo off
title Reparo do Banco - Sistema Exodo
echo ============================================
echo  Reparo do Banco - Sistema Exodo
echo  Cria o banco exodo_db e as tabelas se
echo  nao existirem. Pode rodar quantas vezes
echo  quiser.
echo ============================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0reparar_banco.ps1"

echo.
echo Pressione qualquer tecla para fechar...
pause > nul
