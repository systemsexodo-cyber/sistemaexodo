import json
import time
from google.auth import crypt
from google.auth import jwt

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

with open(cred_path, 'r') as f:
    info = json.load(f)

signer = crypt.RSASigner.from_service_account_info(info)
now = int(time.time())
payload = {
    'iat': now,
    'exp': now + 3600,
    'iss': info['client_email'],
    'sub': info['client_email'],
    'aud': info['token_uri']
}

print(f"Payload: {payload}")
signed_jwt = jwt.encode(signer, payload)
print("JWT assinado com sucesso localmente!")

# Agora tenta trocar por um access token
import requests
resp = requests.post(info['token_uri'], data={
    'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    'assertion': signed_jwt
})

print(f"Status: {resp.status_code}")
print(f"Response: {resp.text}")
