@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    DIAGNÓSTICO DO BANCO SQLITE
echo ============================================
echo.
echo Este script verifica o estado do banco
echo SQLite local do sistema.
echo.
pause

echo.
echo ============================================
echo VERIFICANDO ARQUIVO DO BANCO
echo ============================================
echo.

set DB_PATH=%USERPROFILE%\Documents\exodo_local.db
echo Caminho do banco: %DB_PATH%
echo.

if exist "%DB_PATH%" (
    echo ✅ Arquivo do banco encontrado!
    for %%I in ("%DB_PATH%") do (
        echo    Tamanho: %%~zI bytes
    )
) else (
    echo ❌ Arquivo do banco NÃO encontrado!
    echo    Caminho esperado: %DB_PATH%
    pause
    exit /b 1
)

echo.
echo ============================================
echo VERIFICANDO PERMISSÕES
echo ============================================
echo.

icacls "%DB_PATH%" >nul 2>&1
if %errorlevel% equ 0 (
    echo ✅ Permissões verificadas com sucesso
) else (
    echo ⚠️ Não foi possível verificar permissões
)

echo.
echo ============================================
echo VERIFICANDO SE O BANCO ESTÁ BLOQUEADO
echo ============================================
echo.

echo Tentando abrir o banco em modo leitura...
(
    echo PRAGMA integrity_check;
    echo SELECT COUNT(*) FROM sqlite_master;
) > "%TEMP%\check_sqlite.sql"

sqlite3 "%DB_PATH%" < "%TEMP%\check_sqlite.sql" > "%TEMP%\sqlite_result.txt" 2>&1

if %errorlevel% equ 0 (
    echo ✅ Banco acessível e íntegro!
    type "%TEMP%\sqlite_result.txt"
) else (
    echo ❌ Erro ao acessar o banco!
    echo.
    echo Possíveis causas:
    echo   1. Banco corrompido
    echo   2. Banco bloqueado por outro processo
    echo   3. Permissões insuficientes
    echo.
    echo Tentando recuperar informações do erro...
    type "%TEMP%\sqlite_result.txt"
)

del "%TEMP%\check_sqlite.sql" >nul 2>&1
del "%TEMP%\sqlite_result.txt" >nul 2>&1

echo.
echo ============================================
echo SOLUÇÕES SUGERIDAS
echo ============================================
echo.
echo Se o banco estiver corrompido ou bloqueado:
echo.
echo 1. REINICIAR O APP:
echo    - Feche completamente o app Flutter
echo    - Verifique no Gerenciador de Tarefas se há processos rodando
echo    - Reinicie o app
echo.
echo 2. REINICIAR O COMPUTADOR:
echo    - Isso libera locks de arquivos
echo.
echo 3. RESTAURAR BACKUP:
echo    - Se tiver backup do banco, substitua o arquivo corrompido
echo.
echo 4. REINICIAR O BANCO (ÚLTIMA OPÇÃO):
echo    - Renomeie o arquivo atual para .bak
echo    - O app criará um novo banco vazio
echo    - Você precisará sincronizar novamente com o Supabase
echo.
pause
