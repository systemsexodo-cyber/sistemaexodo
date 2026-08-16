# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_all

datas = [('firebase-credentials.json', '.'), ('../icon_green.ico', '.'), ('../icon_red.ico', '.'), ('../icon_orange.ico', '.')]
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
    'pystray',
    'pystray._win32',
    'PIL',
    'PIL.Image',
    'PIL.ImageDraw',
    'firebase_admin',
    'firebase_admin.credentials',
    'firebase_admin.firestore',
]

import pynfe
import os
pynfe_dir = os.path.dirname(pynfe.__file__)
pynfe_data = os.path.join(pynfe_dir, 'data')
datas += [(pynfe_data, 'pynfe/data')]

tmp_ret = collect_all('firebase_admin')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('pynfe')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('pystray')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('PIL')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]

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
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='ExodoNfceBridge_v352',
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
