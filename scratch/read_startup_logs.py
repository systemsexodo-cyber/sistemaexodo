import os

for f in ['tray_startup_stderr.txt', 'tray_startup_stdout.txt', 'watchdog_log.txt']:
    if os.path.exists(f):
        with open(f, 'r', encoding='utf-8', errors='ignore') as file:
            print(f"=== {f} ===")
            print(file.read()[-1000:])
    else:
        print(f"{f} not found")
