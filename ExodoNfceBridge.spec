# -*- mode: python ; coding: utf-8 -*-
# ExodoNfceBridge v3.5.0 — Local-first, sem Firebase obrigatório
from PyInstaller.utils.hooks import collect_all, collect_submodules

datas = []
binaries = []
hiddenimports = [
    'multiprocessing', '_multiprocessing',
    'multiprocessing.resource_tracker',
    'multiprocessing.popen_spawn_win32',
    'uvicorn', 'uvicorn.logging', 'uvicorn.loops', 'uvicorn.loops.auto',
    'uvicorn.protocols', 'uvicorn.protocols.http', 'uvicorn.protocols.http.auto',
    'unicodedata', 'encodings', 'encodings.utf_8', 'encodings.cp1252',
    'pynfe',
    'pystray', 'PIL', 'PIL.Image', 'PIL.ImageDraw',
    'fastapi', 'pydantic',
    'nfce_handler',
    'cryptography', 'lxml', 'signxml',
    'requests', 'json', 'logging',
]

# Coletar pynfe completo (inclui dados MunIBGE)
tmp = collect_all('pynfe')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar cffi e _cffi_backend (obrigatório para cryptography/signxml em PyInstaller)
tmp = collect_all('_cffi_backend')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

tmp = collect_all('cffi')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

tmp = collect_all('cryptography')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

tmp = collect_all('signxml')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar lxml
tmp = collect_all('lxml')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar uvicorn
tmp = collect_all('uvicorn')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar PIL (extensão nativa _imaging obrigatória para a bandeja/pystray)
tmp = collect_all('PIL')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar pydantic_core (extensão nativa obrigatória do pydantic v2)
tmp = collect_all('pydantic_core')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Coletar pydantic e fastapi (dependências do FastAPI)
tmp = collect_all('pydantic')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

tmp = collect_all('starlette')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

tmp = collect_all('fastapi')
datas += tmp[0]; binaries += tmp[1]; hiddenimports += tmp[2]

# Ícones para a bandeja
import os
icon_files = []
base = os.path.dirname(os.path.abspath('ExodoNfceBridge.spec'))
nfce_dir = os.path.join(base, 'backend_nfce')
for icon in ['icon_green.ico', 'icon_orange.ico', 'icon_red.ico', 'exodo_logo.ico']:
    for search_dir in [base, nfce_dir]:
        full = os.path.join(search_dir, icon)
        if os.path.exists(full):
            datas.append((full, '.'))
            break

a = Analysis(
    ['backend_nfce\\main.py'],
    pathex=['backend_nfce'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'numpy', 'scipy', 'pandas'],
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
    name='ExodoNfceBridge',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,           # SEM janela de console
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['exodo_logo.ico'],
    version_file=None,
)
