@echo off
setlocal
echo ============================================================
echo   SOLUCAO: Falha ao Iniciar Navegador (Chrome)
echo ============================================================
echo.

echo [PASSO 1] Verificando e encerrando processos do Chrome...
taskkill /F /IM chrome.exe /T 2>nul
if %ERRORLEVEL% EQU 1 echo [INFO] Nenhum processo do Chrome encontrado.

echo.
echo [PASSO 2] Encerrando processos do Flutter e Dart...
taskkill /F /IM flutter.exe /T 2>nul
taskkill /F /IM dart.exe /T 2>nul
echo [OK] Processos encerrados.

echo.
echo [PASSO 3] Limpando arquivos temporarios do Flutter...
echo Isso remove perfis de teste travados.
powershell -Command "Get-ChildItem -Path $env:TEMP -Filter 'flutter_tools.*' -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue"
echo [OK] Arquivos temporarios limpos.

echo.
echo [PASSO 4] Verificando se a porta 8080 est├í livre...
powershell -Command "$p = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue; if ($p) { Stop-Process -Id $p.OwningProcess -Force }"
echo [OK] Porta verificada/liberada.

echo.
echo ============================================================
echo   SISTEMA PRONTO PARA TENTAR NOVAMENTE
echo ============================================================
echo.
echo Tente rodar o projeto novamente agora.
echo.
pause
