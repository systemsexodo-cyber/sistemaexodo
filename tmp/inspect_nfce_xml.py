import firebase_admin
from firebase_admin import credentials, firestore
import os

def find_nfces():
    cred_file = "backend_nfce/firebase-credentials.json"
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_file)
        firebase_admin.initialize_app(cred)
        
    db = firestore.client()
    reqs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(10).get()
    
    empresa_id = None
    for r in reqs:
        eid = r.to_dict().get('empresa_id')
        if eid:
            empresa_id = eid
            break
            
    if not empresa_id:
        print("Empresa ID not found")
        return
        
    nfces = db.collection('empresas').document(empresa_id).collection('nfces').where('numero', '==', '119').get()
    
    for nfce in nfces:
        data = nfce.to_dict()
        print(f"ID: {nfce.id}")
        xml = data.get('xmlEnviado', '')
        print(f"XML Start: {xml[:200]}")
        # Procura por chNFe no XML
        import re
        match = re.search(r'<chNFe>(.*?)</chNFe>', xml)
        if match:
            print(f"Chave no XML: {match.group(1)}")
        print("-" * 20)

if __name__ == "__main__":
    find_nfces()
