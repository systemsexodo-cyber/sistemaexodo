import os
import requests
from dotenv import load_dotenv

load_dotenv()

url = f"{os.getenv('SUPABASE_URL')}/rest/v1/vendas_balcao"
headers = {
    "apikey": os.getenv("SUPABASE_ANON_KEY"),
    "Authorization": f"Bearer {os.getenv('SUPABASE_ANON_KEY')}",
    "Range": "0-0"
}
res = requests.get(url, headers=headers)
print("Supabase row payload:", res.json())
