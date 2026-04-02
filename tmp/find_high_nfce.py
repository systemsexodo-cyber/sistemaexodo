import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
company_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"

print("Checking company config...")
doc = db.collection('empresas').document(company_id).get()
print(f"Company Data: {doc.to_dict().get('configuracoes', {}).get('ultimo_numero_nfce')}")

print("\nChecking NFCe records with high numbers...")
docs = db.collection('empresas').document(company_id).collection('nfces').get()
for d in docs:
    data = d.to_dict()
    num = data.get('numero')
    if num:
        try:
            val = int(num)
            if val > 1000:
                print(f"Found high number NFCe: {num} (Doc: {d.id})")
        except:
            pass

docs_global = db.collection('nfces').get()
for d in docs_global:
    data = d.to_dict()
    num = data.get('numero')
    if num:
        try:
            val = int(num)
            if val > 1000:
                print(f"Found global high number NFCe: {num} (Doc: {d.id})")
        except:
            pass
