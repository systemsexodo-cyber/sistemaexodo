"""Mede a taxa real de frames do Xenia contando mudancas na tela.

Captura uma regiao pequena da janela do emulador o mais rapido possivel,
detecta quando o conteudo muda e calcula quantos frames distintos por
segundo foram desenhados.
"""
import ctypes
import statistics
import sys
import time

from ctypes import wintypes

from PIL import ImageGrab

user32 = ctypes.windll.user32


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


def find_window_rect():
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _):
        length = user32.GetWindowTextLengthW(hwnd)
        if length:
            buf = ctypes.create_unicode_buffer(length + 1)
            user32.GetWindowTextW(hwnd, buf, length + 1)
            if "xenia" in buf.value.lower():
                found.append(int(hwnd))
        return True

    user32.EnumWindows(callback, 0)
    if not found:
        return None
    rect = RECT()
    user32.GetWindowRect(wintypes.HWND(found[0]), ctypes.byref(rect))
    return rect


def main():
    duration = float(sys.argv[1]) if len(sys.argv) > 1 else 15.0
    rect = find_window_rect()
    if rect is None or rect.right - rect.left < 100:
        print("JANELA DO XENIA NAO ENCONTRADA")
        return

    width = rect.right - rect.left
    height = rect.bottom - rect.top
    # Faixa central: area 3D ativa, longe das bordas e do HUD fixo.
    x0 = rect.left + int(width * 0.30)
    y0 = rect.top + int(height * 0.30)
    x1 = x0 + 320
    y1 = y0 + 160
    print(f"janela {width}x{height} | amostrando {x1 - x0}x{y1 - y0} por {duration:.0f}s")

    changes = []
    samples = 0
    last = None
    start = time.perf_counter()
    last_change = start
    while time.perf_counter() - start < duration:
        shot = ImageGrab.grab(bbox=(x0, y0, x1, y1))
        samples += 1
        key = shot.tobytes()
        now = time.perf_counter()
        if last is not None and key != last:
            changes.append(now - last_change)
            last_change = now
        last = key
    elapsed = time.perf_counter() - start

    print(f"capturas: {samples} ({samples / elapsed:.1f}/s)")
    print(f"mudancas de frame detectadas: {len(changes)}")
    print(f"FPS medido: {len(changes) / elapsed:.1f}")
    if changes:
        media = statistics.mean(changes)
        p95 = sorted(changes)[int(len(changes) * 0.95) - 1]
        print(f"intervalo medio entre frames: {media * 1000:.1f} ms")
        print(f"pior intervalo (p95): {p95 * 1000:.1f} ms")
        print(f"FPS pela media dos intervalos: {1 / media:.1f}")


main()
