import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json"
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

print("\n--- DETALHES DA ÚLTIMA REQUISIÇÃO ---")
try:
    # Como não tenho um campo de timestamp confiável que ordene por inserção (além de data_hora que pode ser nulo ou string)
    # Vou tentar pegar os últimos processados
    requests = db.collection('nfce_requests').order_by('updated_at', direction=firestore.Query.DESCENDING).limit(1).get()
    
    if not requests:
        # Tentar sem ordem se der erro
        requests = db.collection('nfce_requests').limit(1).get()

    for req in requests:
        data = req.to_dict()
        print(f"ID: {req.id}")
        print(f"Status: {data.get('status')}")
        res = data.get('resultado', {})
        print(f"Mensagem Erro: {res.get('mensagem')}")
        if 'traceback' in res:
             print(f"Traceback: {res.get('traceback')}")
except Exception as e:
    print(f"Erro ao acessar: {e}")
