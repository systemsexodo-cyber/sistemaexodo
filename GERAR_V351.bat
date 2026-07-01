@echo off
chcp 65001 >nul
echo ============================================
echo    GERAR BRIDGE v351 - VERSAO PYTHON
echo ============================================
echo.
python GERAR_V351.py
if errorlevel 1 (
    echo.
    echo ❌ Erro na geracao!
    pause
) else (
    echo.
    echo ✅ Processo concluido!
    pause
)
