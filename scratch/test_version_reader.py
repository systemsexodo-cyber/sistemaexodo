import ctypes
import struct
import os

def get_file_version(filepath):
    if not os.path.exists(filepath):
        return "Não encontrado"
    try:
        size = ctypes.windll.version.GetFileVersionInfoSizeW(filepath, None)
        if not size:
            return "Indefinida"
        res = ctypes.create_string_buffer(size)
        if not ctypes.windll.version.GetFileVersionInfoW(filepath, 0, size, res):
            return "Indefinida"
        r = ctypes.c_void_p()
        u = ctypes.c_uint()
        if not ctypes.windll.version.VerQueryValueW(res, "\\", ctypes.byref(r), ctypes.byref(u)):
            return "Indefinida"
        header_data = ctypes.string_at(r, u.value)
        dwSignature, dwStrucVersion, dwFileVersionMS, dwFileVersionLS = struct.unpack('IIII', header_data[:16])
        major = dwFileVersionMS >> 16
        minor = dwFileVersionMS & 0xFFFF
        build = dwFileVersionLS >> 16
        revision = dwFileVersionLS & 0xFFFF
        return f"{major}.{minor}.{build}.{revision}"
    except Exception as e:
        return f"Erro: {e}"

if __name__ == "__main__":
    for f in ["ExodoNfceBridge.exe", "SincronizadorNuvem.exe", "sistema_exodo_novo.exe"]:
        print(f"{f}: {get_file_version(f)}")
