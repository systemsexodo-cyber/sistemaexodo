import http.client
import time
from datetime import datetime, timezone

def get_google_time():
    conn = http.client.HTTPSConnection("google.com")
    conn.request("HEAD", "/")
    res = conn.getresponse()
    date_str = res.getheader('date')
    # Wed, 11 Mar 2026 21:50:00 GMT
    remote_time = datetime.strptime(date_str, "%a, %d %b %Y %H:%M:%S GMT").replace(tzinfo=timezone.utc)
    return remote_time

google_time = get_google_time()
local_time_utc = datetime.now(timezone.utc)

diff = (google_time - local_time_utc).total_seconds()

print(f"Google UTC Time: {google_time}")
print(f"Local UTC Time:  {local_time_utc}")
print(f"Difference:      {diff} seconds")

if abs(diff) > 30:
    print("O seu relógio ainda está fora de sincronia!")
else:
    print("O seu relógio parece OK.")
