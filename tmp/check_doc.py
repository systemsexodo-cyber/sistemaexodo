import firebase_admin
from firebase_admin import credentials, firestore
import os

base_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce"
cred_file = os.path.join(base_path, "firebase-credentials.json")

if not firebase_admin._apps:
    cred = credentials.Certificate(cred_file)
    firebase_admin.initialize_app(cred)
db = firestore.client()

doc_id = "PxfsAUKfuZHMZy9vDGou"
doc = db.collection('nfce_requests').document(doc_id).get()
if doc.exists:
    data = doc.to_dict()
    print(f"ID: {doc.id}")
    print(f"Status: {data.get('status')}")
    print(f"Resultado: {data.get('resultado')}")
else:
    print("Documento não encontrado.")
