import os

log_path = 'bridge_log.txt'
if os.path.exists(log_path):
    with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
        print("Last 50 lines of bridge_log.txt in root:")
        for line in lines[-50:]:
            print(line.strip())
else:
    print(f"Log file {log_path} not found")
