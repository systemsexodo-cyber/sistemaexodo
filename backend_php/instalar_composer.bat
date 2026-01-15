@echo off
echo ========================================
echo Instalacao do Composer
echo ========================================
echo.

REM Verificar se PHP esta instalado
php --version >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: PHP nao encontrado!
    echo.
    echo Por favor, instale o PHP primeiro:
    echo 1. Baixe em: https://windows.php.net/download/
    echo 2. Adicione ao PATH do sistema
    echo 3. Execute este script novamente
    pause
    exit /b 1
)

echo [1/2] Baixando Composer...
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

echo [2/2] Instalando Composer...
php composer-setup.php
php -r "unlink('composer-setup.php');"

if exist composer.phar (
    echo.
    echo ========================================
    echo Composer instalado com sucesso!
    echo ========================================
    echo.
    echo Para instalar as dependencias, execute:
    echo   php composer.phar install
    echo.
) else (
    echo ERRO: Falha ao instalar Composer
)

pause











