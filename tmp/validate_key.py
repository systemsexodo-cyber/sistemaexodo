from cryptography.hazmat.primitives import serialization
import json

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

try:
    with open(cred_path, 'r') as f:
        data = json.load(f)
    pk_str = data['private_key']
    
    # Tenta carregar a chave
    key = serialization.load_pem_private_key(pk_str.encode('utf-8'), password=None)
    print("Sucesso: Chave privada RSA carregada e valida!")
    print(f"Key Size: {key.key_size} bits")
except Exception as e:
    print(f"Erro ao carregar chave: {e}")
