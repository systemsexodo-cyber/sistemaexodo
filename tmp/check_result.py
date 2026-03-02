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
    
    doc = db.collection('nfce_requests').document('7GT3ztQWrp5gyHiZ0EZe').get()
    
    if not doc.exists:
        print("ERROR: Documento nao encontrado.")
    else:
        print(f"STATUS ATUAL: {doc.to_dict().get('status')}")
        print(f"RESULTADO: {doc.to_dict().get('resultado')}")

except Exception as e:
    print(f"ERRO: {e}")
