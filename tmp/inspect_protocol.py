import firebase_admin
from firebase_admin import credentials, firestore

def inspect():
    cred = credentials.Certificate('firebase-credentials.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    
    protocol = "13526000004232364"
    print(f"Searching for protocol {protocol} in all nfces...")
    
    docs = db.collection_group('nfces').where('protocolo', '==', protocol).get()
    print(f"Found {len(docs)} docs")
    for d in docs:
        print(f"Path: {d.reference.path}")
        data = d.to_dict()
        print(f"Key: {data.get('chaveAcesso')}")
        print(f"Date: {data.get('createdAt')}")

if __name__ == "__main__":
    inspect()
