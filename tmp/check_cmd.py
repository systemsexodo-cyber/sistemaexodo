import firebase_admin
from firebase_admin import credentials, firestore
import os

def check_latest_command():
    # Use the same path-finding logic as the bridge
    base_path = os.getcwd()
    cred_file = os.path.join(base_path, "backend_nfce", "firebase-credentials.json")
    
    if not os.path.exists(cred_file):
        cred_file = "firebase-credentials.json"
    
    if not os.path.exists(cred_file):
        print("Credentials not found")
        return

    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(cred_file)
            firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        docs = db.collection('bridge_commands').order_by('started_at', direction=firestore.Query.DESCENDING).limit(1).get()
        
        for doc in docs:
            data = doc.to_dict()
            print(f"ID: {doc.id}")
            print(f"Status: {data.get('status')}")
            print(f"Resultado: {data.get('resultado')}")
            print(f"Sucesso: {data.get('sucesso')}")
            print(f"Comando: {data.get('comando')}")
            print(f"PC: {data.get('processor_pc')}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    check_latest_command()
