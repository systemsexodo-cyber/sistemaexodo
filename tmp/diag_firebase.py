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
    
    docs = db.collection('nfce_requests').where('status', '==', 'pendente').limit(5).get()
    
    if not docs:
        print("INFO: Nenhuma requisicao pendente encontrada no Firebase.")
    else:
        print(f"INFO: Encontradas {len(docs)} requisicoes pendentes no Firebase.")
        for doc in docs:
            print(f"ID: {doc.id} - Data: {doc.to_dict().get('created_at')}")

except Exception as e:
    print(f"ERRO ao conectar ao Firebase: {e}")
