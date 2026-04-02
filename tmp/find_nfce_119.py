import firebase_admin
from firebase_admin import credentials, firestore
import os

def find_nfces():
    cred_file = "backend_nfce/firebase-credentials.json"
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_file)
        firebase_admin.initialize_app(cred)
        
    db = firestore.client()
    # Find empresa ID from requests first to be sure
    reqs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(10).get()
    
    # Try different request indices to find valid empresa_id
    empresa_id = None
    for r in reqs:
        eid = r.to_dict().get('empresa_id')
        if eid:
            empresa_id = eid
            break
            
    if not empresa_id:
        print("Empresa ID not found in requests")
        return
        
    print(f"Empresa: {empresa_id}")
    
    nfces = db.collection('empresas').document(empresa_id).collection('nfces').where('numero', '==', '119').get()
    
    print(f"Encontradas {len(nfces)} notas com o n 119")
    for nfce in nfces:
        data = nfce.to_dict()
        print(f"ID: {nfce.id}")
        print(f"Status: {data.get('status')}")
        print(f"Data: {data.get('createdAt')}")
        print(f"Chave: {data.get('chaveAcesso')}")
        print("-" * 20)

if __name__ == "__main__":
    find_nfces()
