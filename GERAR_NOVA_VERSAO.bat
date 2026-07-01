@echo off
chcp 65001 >nul
cls
echo.
echo ============================================
echo    GERAR NOVA VERSAO DO BRIDGE NFC-e
echo ============================================
echo.
echo Versao atual: v350
echo Nova versao:  v351
echo.

:: Verificar Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python nao encontrado!
    pause
    exit /b 1
)

cd /d "%~dp0backend_nfce"

:: Verificar/criar venv
if not exist "venv" (
    echo 📦 Criando ambiente virtual...
    python -m venv venv
)

:: Ativar venv
call venv\Scripts\activate.bat

:: Instalar dependencias
echo 📦 Instalando dependencias...
pip install -q pyinstaller fastapi uvicorn pydantic requests pynfe signxml lxml cryptography pystray Pillow firebase-admin

:: Limpar builds anteriores
echo 🧹 Limpando builds anteriores...
if exist "build" rmdir /s /q "build"
if exist "dist" rmdir /s /q "dist"

:: Criar arquivo spec atualizado
echo 📝 Criando arquivo de configuracao...
(
echo # -*- mode: python ; coding: utf-8 -*-
echo from PyInstaller.utils.hooks import collect_all
echo.
echo datas = [('firebase-credentials.json', '.'), ('../icon_green.ico', '.'), ('../icon_red.ico', '.'), ('../icon_orange.ico', '.')]
echo binaries = []
echo hiddenimports = [
echo     'multiprocessing',
echo     '_multiprocessing',
echo     'multiprocessing.resource_tracker',
echo     'multiprocessing.popen_spawn_win32',
echo     'uvicorn',
echo     'pynfe',
echo     'unicodedata',
echo     'tempfile',
echo     '_tempfile',
echo     'pystray',
echo     'pystray._win32',
echo     'PIL',
echo     'PIL.Image',
echo     'PIL.ImageDraw',
echo     'firebase_admin',
echo     'firebase_admin.credentials',
echo     'firebase_admin.firestore',
echo ]
echo.
echo import pynfe
echo import os
echo pynfe_dir = os.path.dirname(pynfe.__file__)
echo pynfe_data = os.path.join(pynfe_dir, 'data')
echo datas += [(pynfe_data, 'pynfe/data')]
echo.
echo tmp_ret = collect_all('firebase_admin')
echo datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
echo tmp_ret = collect_all('pynfe')
echo datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
echo tmp_ret = collect_all('pystray')
echo datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
echo tmp_ret = collect_all('PIL')
echo datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
echo.
echo a = Analysis(
echo     ['main.py'],
echo     pathex=['..\\backend_pynfe', '..', '.'],
echo     binaries=binaries,
echo     datas=datas,
echo     hiddenimports=hiddenimports,
echo     hookspath=[],
echo     hooksconfig={},
echo     runtime_hooks=[],
echo     excludes=[],
echo     noarchive=False,
echo     optimize=0,
echo )
echo pyz = PYZ(a.pure)
echo.
echo exe = EXE(
echo     pyz,
echo     a.scripts,
echo     a.binaries,
echo     a.datas,
echo     [],
echo     name='ExodoNfceBridge_v351',
echo     debug=False,
echo     bootloader_ignore_signals=False,
echo     strip=False,
echo     upx=True,
echo     upx_exclude=[],
echo     runtime_tmpdir=None,
echo     console=False,
echo     disable_windowed_traceback=False,
echo     argv_emulation=False,
echo     target_arch=None,
echo     codesign_identity=None,
echo     entitlements_file=None,
echo     icon=['exodo_logo.ico'],
echo )
) > ExodoNfceBridge_v351.spec

:: Compilar
echo 🔨 Compilando Bridge v351...
pyinstaller ExodoNfceBridge_v351.spec --clean --noconfirm

:: Verificar se compilou
echo.
if exist "dist\ExodoNfceBridge_v351.exe" (
    echo ✅ Compilacao concluida com sucesso!
    echo.
    echo 📋 Arquivo gerado:
    echo    dist\ExodoNfceBridge_v351.exe
    echo.
    echo 📝 Para usar:
    echo    1. Copie para a pasta principal do projeto
    echo    2. Execute: ExodoNfceBridge_v351.exe
    echo.
    :: Copiar para pasta raiz automaticamente
    copy /Y "dist\ExodoNfceBridge_v351.exe" "..\ExodoNfceBridge_v351.exe"
    echo ✅ Copiado para pasta principal!
) else (
    echo ❌ Erro na compilacao!
    echo Verifique os erros acima.
)

:: Desativar venv
call venv\Scripts\deactivate.bat

echo.
pause
