import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_file = "c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json"

if not os.path.exists(cred_file):
    print(f"ERRO: Arquivo {cred_file} nao encontrado!")
    exit()

try:
    cred = credentials.Certificate(cred_file)
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    
    docs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(1).get()
    
    if not docs:
        print("Nenhuma requisicao encontrada.")
    else:
        doc = docs[0]
        data = doc.to_dict()
        print(f"ID: {doc.id}")
        print(f"Status: {data.get('status')}")
        print(f"Resultado type: {type(data.get('resultado'))}")
        print(f"Resultado: {data.get('resultado')}")

except Exception as e:
    print(f"ERRO: {e}")
