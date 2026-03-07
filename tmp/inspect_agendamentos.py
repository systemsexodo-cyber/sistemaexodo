import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n--- INSPEÇÃO DE AGENDAMENTOS POR EMPRESA ---")
try:
    empresas = db.collection('empresas').get()
    for emp in empresas:
        emp_id = emp.id
        # Firebase Admin SDK subcollections access
        sub_col_ref = db.collection('empresas').document(emp_id).collection('agendamentos_servico')
        docs = sub_col_ref.limit(5).get()
        count = len(sub_col_ref.get()) # Getting total count
        
        print(f"\nEmpresa: {emp_id}")
        print(f"Total Agendamentos: {count}")
        
        for doc in docs:
            data = doc.to_dict()
            print(f"  - ID: {doc.id} | Numero: {data.get('numero')} | Status: {data.get('status')} | Pet: {data.get('petNome')} | Cliente: {data.get('clienteNome')}")
            # print(f"    Raw data: {data}")

except Exception as e:
    print(f"Erro ao acessar Firestore: {e}")
