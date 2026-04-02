import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
company_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"

print("Cleaning up high number NFCe records for company...")
docs = db.collection('empresas').document(company_id).collection('nfces').get()
count = 0
for d in docs:
    data = d.to_dict()
    num = data.get('numero')
    if num:
        try:
            val = int(num)
            if val > 1000:
                print(f"Deleting high number NFCe: {num} (Doc: {d.id})")
                d.reference.delete()
                count += 1
        except:
            pass
print(f"Deleted {count} records from company subcollection.")

print("\nCleaning up high number NFCe records from global collection...")
docs_global = db.collection('nfces').get()
count_global = 0
for d in docs_global:
    data = d.to_dict()
    num = data.get('numero')
    if d.to_dict().get('empresaId') == company_id or d.to_dict().get('cnpj') == '04829400000165':
        if num:
            try:
                val = int(num)
                if val > 1000:
                    print(f"Deleting global high number NFCe: {num} (Doc: {d.id})")
                    d.reference.delete()
                    count_global += 1
            except:
                pass
print(f"Deleted {count_global} records from global collection.")
