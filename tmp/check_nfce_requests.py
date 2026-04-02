import firebase_admin
from firebase_admin import credentials, firestore
import json
import os

def check_requests():
    cred_file = "backend_nfce/firebase-credentials.json"
    if not os.path.exists(cred_file):
        print("Credentials not found")
        return
        
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_file)
        firebase_admin.initialize_app(cred)
        
    db = firestore.client()
    docs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(10).get()
    
    for doc in docs:
        data = doc.to_dict()
        print(f"ID: {doc.id}")
        oper = data.get('operacao', 'emissao')
        print(f"Operacao: {oper}")
        print(f"Status: {data.get('status')}")
        if oper == 'cancelamento':
            print(f"Chave Acesso na Req: {data.get('chave_acesso')}")
        else:
            res = data.get('resultado', {})
            print(f"Chave Acesso no Res: {res.get('chave') if isinstance(res, dict) else '?'}")
        print("-" * 20)

if __name__ == "__main__":
    check_requests()
