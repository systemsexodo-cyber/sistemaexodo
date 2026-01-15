@echo off
echo ========================================
echo Instalando Dependencias do Backend PHP
echo ========================================
echo.

REM Verificar se composer.phar existe localmente
if exist composer.phar (
    echo Usando composer.phar local...
    php composer.phar install
    goto :fim
)

REM Verificar se composer esta no PATH
composer --version >nul 2>&1
if %errorlevel% equ 0 (
    echo Usando Composer do PATH...
    composer install
    goto :fim
)

REM Se nao encontrou, tentar instalar
echo Composer nao encontrado!
echo.
echo Opcao 1: Instalar Composer localmente
echo   Execute: instalar_composer.bat
echo   Depois: php composer.phar install
echo.
echo Opcao 2: Instalar Composer globalmente
echo   1. Baixe em: https://getcomposer.org/download/
echo   2. Execute o instalador
echo   3. Execute este script novamente
echo.
pause

:fim











