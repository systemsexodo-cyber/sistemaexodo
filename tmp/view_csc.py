import firebase_admin
from firebase_admin import credentials, firestore
import os

# Usar a credencial que ele já tem no backend_nfce
cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Listar empresas
empresas = db.collection('empresas').get()
print("\n--- DADOS DE CSC NAS EMPRESAS ---")
for emp in empresas:
    data = emp.to_dict()
    print(f"Empresa: {data.get('nome_fantasia') or data.get('razao_social')}")
    print(f"CNPJ: {data.get('cnpj')}")
    print(f"Ambiente: {data.get('ambiente')} (1=Prod, 2=Homol)")
    print(f"CSC: {data.get('csc')}")
    print(f"CSC_ID: {data.get('csc_id')}")
    print("---------------------------------")
