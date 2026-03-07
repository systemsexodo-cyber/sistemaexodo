import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n--- ÚLTIMAS REQUISIÇÕES NFC-E ---")
try:
    reqs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(5).get()
    for r in reqs:
        data = r.to_dict()
        status = data.get('status')
        created = data.get('created_at')
        print(f"ID: {r.id} | Status: {status} | Criado: {created}")
        if status == 'erro':
            res = data.get('resultado', {})
            print(f"   Erro: {res.get('mensagem') or res.get('error')}")
except Exception as e:
    print(f"Erro ao acessar Firestore: {e}")
