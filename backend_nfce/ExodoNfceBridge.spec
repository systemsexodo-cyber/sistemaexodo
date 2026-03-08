# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = [('firebase-credentials.json', '.')]
binaries = []
hiddenimports = ['multiprocessing', '_multiprocessing', 'multiprocessing.resource_tracker', 'multiprocessing.popen_spawn_win32', 'uvicorn', 'pynfe']
import pynfe
import os
pynfe_dir = os.path.dirname(pynfe.__file__)
pynfe_data = os.path.join(pynfe_dir, 'data')
datas += [(pynfe_data, 'pynfe/data')]
tmp_ret = collect_all('firebase_admin')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('pynfe')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


# --- Bridge Analysis ---
a = Analysis(
    ['main.py'],
    pathex=['..\\backend_pynfe', '..', '.'],
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
    pathex=['..\\backend_pynfe', '..', '.'],
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

# --- Bridge EXE ---
exe_bridge = EXE(
    pyz_a,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='ExodoNfceBridge',
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
    icon=['..\\exodo_logo.ico'],
)

# --- Watchdog EXE ---
exe_watchdog = EXE(
    pyz_w,
    w.scripts,
    w.binaries,
    w.datas,
    [],
    name='ExodoNfceBridgeWatchdog',
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
    icon=['..\\exodo_logo.ico'],
)
