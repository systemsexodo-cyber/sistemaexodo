import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

try:
    print(f"Testando credenciais em: {cred_path}")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    # Tenta uma leitura simples
    doc = db.collection('bridge_status').limit(1).get()
    print("Conexao com Firebase: SUCESSO!")
except Exception as e:
    print(f"Conexao com Firebase: FALHA!")
    print(f"Erro: {e}")
    import traceback
    traceback.print_exc()
