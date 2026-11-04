# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all
import importlib.util as _ilu
import sys as _sys

# Falha cedo se o Python que esta compilando nao tem as dependencias do bridge.
# Sem isso o PyInstaller so avisa "missing module named uvicorn" no warn-*.txt e
# gera um EXE que abre com ModuleNotFoundError: No module named 'uvicorn'.
_OBRIGATORIOS = ('uvicorn', 'fastapi', 'starlette', 'pydantic')
_faltando = [m for m in _OBRIGATORIOS if _ilu.find_spec(m) is None]
if _faltando:
    raise SystemExit(
        "\n[ERRO] O Python do build nao tem: %s\n"
        "        Interprete usado: %s\n"
        "        Use o venv do bridge: backend_nfce\\venv\\Scripts\\python.exe -m PyInstaller ...\n"
        % (", ".join(_faltando), _sys.executable)
    )

datas = [('firebase-credentials.json', '.')]
binaries = []
hiddenimports = [
    'multiprocessing',
    '_multiprocessing',
    'multiprocessing.resource_tracker',
    'multiprocessing.popen_spawn_win32',
    'uvicorn',
    'pynfe',
    'unicodedata',
    'tempfile',
    '_tempfile',
    # Dependencias da bandeja no Windows
    'pystray',
    'pystray._win32',
    'PIL',
    'PIL.Image',
    'PIL.ImageDraw',
]
import pynfe
import os
pynfe_dir = os.path.dirname(pynfe.__file__)
pynfe_data = os.path.join(pynfe_dir, 'data')
datas += [(pynfe_data, 'pynfe/data')]
datas += [('../icon_green.ico', '.'), ('../icon_red.ico', '.'), ('../icon_orange.ico', '.')]
tmp_ret = collect_all('firebase_admin')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('pynfe')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('pystray')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('PIL')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


# --- Bridge Analysis ---
a = Analysis(
    ['main.py'],
    pathex=['.', '..'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz_a = PYZ(a.pure)

# --- Watchdog Analysis ---
w = Analysis(
    ['watchdog.py'],
    pathex=['.', '..'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz_w = PYZ(w.pure)

# --- Bridge EXE (Modo Diretório - OneDir) ---
exe_bridge = EXE(
    pyz_a,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='ExodoNfceBridge_v358',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['exodo_logo.ico'],
)

# --- Watchdog EXE ---
exe_watchdog = EXE(
    pyz_w,
    w.scripts,
    w.binaries,
    w.datas,
    [],
    name='ExodoNfceBridgeWatchdog_v358',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['exodo_logo.ico'],
)
