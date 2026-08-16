@echo off
title Instalar pgAdmin 4 - Sistema Êxodo
setlocal enabledelayedexpansion

echo ============================================
echo   Instalador do pgAdmin 4
echo   Sistema Êxodo
echo ============================================
echo.
echo Este script vai abrir a pagina de download do
echo pgAdmin 4 para voce visualizar os dados do banco.
echo.
echo ============================================
echo DADOS DE CONEXAO (guarde para depois):
echo ============================================
echo   Host:       localhost
echo   Porta:      5432
echo   Usuario:    exodo_user
echo   Senha:      ex@#$
echo   Banco:      exodo_db
echo ============================================
echo.

:: Verificar se pgAdmin ja esta instalado
if exist "C:\Program Files\pgAdmin 4\pgAdmin4.exe" (
    echo [OK] pgAdmin 4 ja esta instalado!
    echo.
    echo Para abrir, va em: Menu Iniciar ^> pgAdmin 4
    echo.
    pause
    goto :fim
)
if exist "C:\Program Files (x86)\pgAdmin 4\pgAdmin4.exe" (
    echo [OK] pgAdmin 4 ja esta instalado!
    echo.
    echo Para abrir, va em: Menu Iniciar ^> pgAdmin 4
    echo.
    pause
    goto :fim
)

:confirmar
echo.
echo Deseja abrir a pagina de download do pgAdmin 4?
echo (Voce baixa e instala manualmente - mais seguro)
echo.
set /p confirmacao="Abrir pagina de download? (S/N): "
if /i "!confirmacao!"=="S" goto abrir_pagina
if /i "!confirmacao!"=="N" goto sair
echo Digite S ou N
goto confirmar

:abrir_pagina
echo.
echo Abrindo pagina de download do pgAdmin 4...
echo.
echo Se o navegador nao abrir, acesse manualmente:
echo https://www.pgadmin.org/download/pgadmin-4-windows/
echo.
start https://www.pgadmin.org/download/pgadmin-4-windows/
echo.echo ============================================
echo   Pagina aberta no seu navegador!
echo ============================================
echo.
echo Apos baixar e instalar o pgAdmin 4:
echo.
echo 1. Abra o pgAdmin 4 pelo Menu Iniciar
echo 2. Clique com direito em "Servers" ^> "Register" ^> "Server..."
echo 3. Aba General - Name: Sistema Exodo
echo 4. Aba Connection:
echo    - Host: localhost
echo    - Port: 5432
echo    - Username: exodo_user
echo    - Password: ex@#$
echo 5. Clique em Save
echo.
echo Pronto! Voce vai ver todos os dados do sistema.
echo.
pause
goto :fim

:sair
echo.
echo Instalacao cancelada.
echo Voce pode instalar o pgAdmin depois pelo atalho no Menu Iniciar.
pause
goto :fim

:fim
