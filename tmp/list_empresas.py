import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n--- LISTAGEM DE EMPRESAS NO FIRESTORE ---")
try:
    empresas = db.collection('empresas').get()
    for emp in empresas:
        data = emp.to_dict()
        print(f"ID: {emp.id} | Nome: {data.get('nomeFantasia') or data.get('razaoSocial')} | Slug: {data.get('slug')}")
except Exception as e:
    print(f"Erro ao acessar Firestore: {e}")
