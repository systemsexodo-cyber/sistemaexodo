import firebase_admin
from firebase_admin import credentials, firestore

def inspect():
    cred = credentials.Certificate('firebase-credentials.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    
    empresa_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"
    key_correct = "35260304829400000165650010000001241694161989"
    
    col_ref = db.collection('empresas').document(empresa_id).collection('nfces')
    
    print(f"Searching for {key_correct} in company {empresa_id}...")
    docs = col_ref.where('chaveAcesso', '==', key_correct).get()
    print(f"Found {len(docs)} docs")
    for d in docs:
        data = d.to_dict()
        print(f"ID: {d.id}")
        print(f"Number: {data.get('numero')}")
        print(f"Protocol: {data.get('protocolo')}")
        print(f"Status: {data.get('status')}")
        print(f"Created: {data.get('createdAt')}")

if __name__ == "__main__":
    inspect()
