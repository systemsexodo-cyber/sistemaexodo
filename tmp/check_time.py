import time
from datetime import datetime
import os

print(f"Time: {time.time()}")
print(f"UTC Now: {datetime.utcnow()}")
print(f"Local Now: {datetime.now()}")
print(f"TZ Name: {time.tzname}")
