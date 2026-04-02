import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('backend_nfce/firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

doc = db.collection('bridge_config').document('latest').get()
if doc.exists:
    data = doc.to_dict()
    print(f"VERSAO: {data.get('version')}")
    print(f"URL: {data.get('download_url')[:50]}...")
    print(f"DATA: {data.get('updated_at')}")
else:
    print("ERRO: Documento bridge_config/latest não existe!")
