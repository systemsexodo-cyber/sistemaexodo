import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
docs = db.collection('empresas').where('cnpj', '==', '04829400000165').get()
for doc in docs:
    print(f"ID Doc: {doc.id}")
    data = doc.to_dict()
    configs = data.get('configuracoes', {})
    print(f"ultimo_numero_nfce atual: {configs.get('ultimo_numero_nfce')}")
