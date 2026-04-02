import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
doc_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"
ref = db.collection('empresas').document(doc_id)
data = ref.get().to_dict()
configs = data.get('configuracoes', {})
old_num = configs.get('ultimo_numero_nfce')
configs['ultimo_numero_nfce'] = "131"
ref.update({'configuracoes': configs})
print(f"Número da NFC-e resetado de {old_num} para 131.")
