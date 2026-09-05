import os

data_dir = r"C:\Program Files\PostgreSQL\18\data"
if os.path.exists(data_dir):
    try:
        items = os.listdir(data_dir)
        print(f"Contents of {data_dir}:")
        for item in items:
            full_path = os.path.join(data_dir, item)
            is_dir = os.path.isdir(full_path)
            print(f"  • {item} {'(Dir)' if is_dir else '(File)'}")
    except Exception as e:
        print(f"Error listing data directory: {e}")
else:
    print(f"PG data directory does not exist: {data_dir}")
