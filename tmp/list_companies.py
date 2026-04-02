import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
docs = db.collection('empresas').get()
for doc in docs:
    data = doc.to_dict()
    print(f"ID: {doc.id} | CNPJ: {data.get('cnpj')} | Nome: {data.get('razaoSocial', data.get('nomeFantasia'))}")
    configs = data.get('configuracoes', {})
    print(f"  > ultimo_numero_nfce: {configs.get('ultimo_numero_nfce')}")
