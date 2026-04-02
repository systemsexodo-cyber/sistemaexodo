import sys
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('backend_nfce/firebase-key.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

docs = db.collection('bridge_commands').order_by('created_at', direction=firestore.Query.DESCENDING).limit(5).stream()

print("ULTIMOS COMANDOS BRIDGE:")
for doc in docs:
    data = doc.to_dict()
    print(f"ID: {doc.id}")
    print(f"Comando: {data.get('comando')}")
    print(f"Status: {data.get('status')}")
    print(f"Resultado: {data.get('resultado')}")
    print(f"Criado em: {data.get('created_at')}")
    print("-" * 40)
