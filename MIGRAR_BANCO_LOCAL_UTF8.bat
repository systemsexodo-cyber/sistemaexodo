@echo off
title Migrar Banco Local para UTF8 - Sistema Exodo
chcp 65001 >nul
cd /d "%~dp0"

cls
echo ============================================================
echo   MIGRAR O BANCO LOCAL PARA UTF8
echo ============================================================
echo.
echo Isto corrige o erro 22P05 ("caractere ... na codificacao UTF8
echo nao tem equivalente na codificacao WIN1252") - setas como a do
echo historico de produtos (Estoque: 10 -^> 8) nao entravam no banco
echo local porque ele foi criado em WIN1252.
echo.
echo ANTES DE CONTINUAR, FECHE:
echo   1. o SISTEMA (a janela do Sistema Exodo);
echo   2. o SincronizadorNuvem (icone na bandeja do Windows - botao
echo      direito -^> Sair).
echo.
echo Nada e apagado: o script tira um backup (.dump), cria um banco
echo novo em UTF8, copia tudo, confere as contagens tabela por tabela
echo e so entao troca os nomes. Se algo falhar, nada muda.
echo.
echo Pressione qualquer tecla para continuar, ou feche a janela para sair.
pause >nul

echo.
REM Tenta usar o python do venv primeiro
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" migrar_banco_local_utf8.py %*
) else if exist "venv\Scripts\python.exe" (
    "venv\Scripts\python.exe" migrar_banco_local_utf8.py %*
) else (
    python migrar_banco_local_utf8.py %*
)

echo.
if errorlevel 1 (
    echo ============================================================
    echo   A MIGRACAO NAO FOI CONCLUIDA
    echo ============================================================
    echo Confira as mensagens acima. Se o motivo foi "conexoes abertas",
    echo feche o sistema e o SincronizadorNuvem e rode este script de novo.
) else (
    echo ============================================================
    echo   PRONTO - abra o sistema normalmente
    echo ============================================================
)

echo.
pause
