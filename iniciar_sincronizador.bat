@echo off
title Exodo - Sincronizador Nuvem
color 0B
echo ========================================================
echo     SISTEMA EXODO - SINCRONIZADOR LOCAL PARA SUPABASE
echo ========================================================
echo.
echo Iniciando o agente de sincronizacao em background...
echo Pressione CTRL+C para parar.
echo.

python sincronizar_local_supabase.py --interval 5
pause
