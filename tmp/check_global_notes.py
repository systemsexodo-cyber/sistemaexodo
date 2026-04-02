import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = 'backend_nfce/firebase-credentials.json'
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Buscar as últimas 10 notas globais
docs = db.collection('nfce').order_by('created_at', direction=firestore.Query.DESCENDING).limit(10).stream()

print("Global Notes:")
for doc in docs:
    data = doc.to_dict()
    print(f"Num: {data.get('numero')} | Company: {data.get('empresa_id')} | Status: {data.get('status')} | Prot: {data.get('protocolo')} | ID: {doc.id}")
