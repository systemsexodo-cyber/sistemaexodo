import json
import time
import requests
from google.auth import crypt
from google.auth import jwt

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

with open(cred_path, 'r') as f:
    info = json.load(f)

signer = crypt.RSASigner.from_service_account_info(info)

def try_with_offset(offset_seconds):
    now = int(time.time()) + offset_seconds
    payload = {
        'iat': now,
        'exp': now + 3600,
        'iss': info['client_email'],
        'sub': info['client_email'],
        'aud': info['token_uri'],
        'scope': 'https://www.googleapis.com/auth/cloud-platform'
    }
    signed_jwt = jwt.encode(signer, payload)
    resp = requests.post(info['token_uri'], data={
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': signed_jwt
    })
    return resp.status_code, resp.text

print("Testando JWT Real (iat 0s)...")
status, text = try_with_offset(0)
print(f"Status: {status}")
print(f"Response: {text}")
