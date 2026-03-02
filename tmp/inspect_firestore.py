import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n--- LISTANDO ÚLTIMAS 5 REQUISIÇÕES DE NFC-e ---")
requests = db.collection('nfce_requests').order_by('data_hora', direction=firestore.Query.DESCENDING).limit(5).get()

for req in requests:
    data = req.to_dict()
    print(f"ID: {req.id}")
    print(f"Data: {data.get('data_hora')}")
    print(f"Status: {data.get('status')}")
    print(f"Erro: {data.get('erro_mensagem')}")
    print(f"Venda: {data.get('venda_numero')}")
    print("-" * 30)
