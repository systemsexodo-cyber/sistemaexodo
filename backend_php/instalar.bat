@echo off
echo ========================================
echo Instalacao Backend PHP NFC-e
echo ========================================
echo.

echo [1/3] Verificando PHP...
php -v
if %errorlevel% neq 0 (
    echo ERRO: PHP nao encontrado! Instale o PHP 7.4+ e tente novamente.
    pause
    exit /b 1
)
echo OK!
echo.

echo [2/3] Verificando Composer...
composer --version
if %errorlevel% neq 0 (
    echo ERRO: Composer nao encontrado! Instale o Composer e tente novamente.
    echo Download: https://getcomposer.org/download/
    pause
    exit /b 1
)
echo OK!
echo.

echo [3/3] Instalando dependencias...
composer install
if %errorlevel% neq 0 (
    echo ERRO: Falha ao instalar dependencias!
    pause
    exit /b 1
)
echo OK!
echo.

echo ========================================
echo Instalacao concluida com sucesso!
echo ========================================
echo.
echo Para iniciar o servidor:
echo   php -S localhost:8000 -t .
echo.
pause











