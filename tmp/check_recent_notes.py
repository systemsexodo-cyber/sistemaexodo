import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = 'backend_nfce/firebase-credentials.json'
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()
company_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"

# Buscar as últimas 5 notas
docs = db.collection('companies').document(company_id).collection('nfce').order_by('created_at', direction=firestore.Query.DESCENDING).limit(5).stream()

print(f"Notes for {company_id}:")
for doc in docs:
    data = doc.to_dict()
    print(f"Num: {data.get('numero')} | Status: {data.get('status')} | Prot: {data.get('protocolo')} | ID: {doc.id}")
