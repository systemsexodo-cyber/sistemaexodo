import json
import time
import requests
from google.auth import crypt
from google.auth import jwt

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

with open(cred_path, 'r') as f:
    info = json.load(f)

signer = crypt.RSASigner.from_service_account_info(info)

# O segredo pode estar aqui: Google as vezes exige o 'kid' no header
header = {'kid': info['private_key_id']}
now = int(time.time())
payload = {
    'iat': now,
    'exp': now + 3600,
    'iss': info['client_email'],
    'sub': info['client_email'],
    'aud': info['token_uri'],
    'scope': 'https://www.googleapis.com/auth/cloud-platform'
}

signed_jwt = jwt.encode(signer, payload, header=header)

resp = requests.post(info['token_uri'], data={
    'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    'assertion': signed_jwt
})

print(f"Status: {resp.status_code}")
print(f"Response: {resp.text}")
