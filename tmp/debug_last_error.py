import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = 'c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json'
cred = credentials.Certificate(cred_path)
firebase_admin.initialize_app(cred)
db = firestore.client()

print("Buscando o último erro em 'nfce_requests'...")
docs = db.collection('nfce_requests').where('status', '==', 'erro').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(1).get()

if not docs:
    print("Nenhum erro encontrado.")
else:
    doc = docs[0]
    data = doc.to_dict()
    print(f"\nDocumento ID: {doc.id}")
    print(f"Resultado: {data.get('resultado')}")
    print("\nDados do documento:")
    import json
    def serialize(obj):
        if hasattr(obj, 'isoformat'): return obj.isoformat()
        return str(obj)
    print(json.dumps(data, indent=2, default=serialize))
