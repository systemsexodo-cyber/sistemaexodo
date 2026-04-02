import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/firebase_key.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
empresa_id = '04829400000165' # Using CNPJ as ID often in this project, or actual doc id
# Let's find the company doc
docs = db.collection('empresas').where('cnpj', '==', '04829400000165').get()
for doc in docs:
    print(f"Company ID: {doc.id}")
    data = doc.to_dict()
    configs = data.get('configuracoes', {})
    print(f"ultimo_numero_nfce: {configs.get('ultimo_numero_nfce')}")
    print(f"ambiente_nfe: {configs.get('ambiente_nfe')}")
