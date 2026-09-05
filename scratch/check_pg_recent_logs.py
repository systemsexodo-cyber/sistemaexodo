import os
import glob

log_dir = r"C:\Program Files\PostgreSQL\18\data\log"
if os.path.exists(log_dir):
    files = glob.glob(os.path.join(log_dir, "*.log"))
    if files:
        # Sort by modification time
        files.sort(key=os.path.getmtime)
        latest_file = files[-1]
        print(f"Latest PG log file: {latest_file}")
        try:
            with open(latest_file, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                print("\nLast 50 lines of PG log:")
                for line in lines[-50:]:
                    print(line.strip())
        except Exception as e:
            print(f"Error reading log file: {e}")
    else:
        print("No log files found in pg log directory.")
else:
    print(f"PG log directory does not exist: {log_dir}")
