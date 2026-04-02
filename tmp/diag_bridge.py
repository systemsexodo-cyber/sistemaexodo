
import firebase_admin
from firebase_admin import credentials, firestore
import os
import datetime

def main():
    base_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce"
    cred_file = os.path.join(base_path, "firebase-credentials.json")
    
    if not os.path.exists(cred_file):
        print(f"Erro: {cred_file} não encontrado.")
        return

    cred = credentials.Certificate(cred_file)
    firebase_admin.initialize_app(cred)
    db = firestore.client()

    print("--- STATUS DO BRIDGE NO FIRESTORE ---")
    docs = db.collection('bridge_status').get()
    for doc in docs:
        data = doc.to_dict()
        last_seen = data.get('last_seen')
        if last_seen:
            # Firestore returns datetime objects for timestamps
            last_seen_str = last_seen.strftime('%Y-%m-%d %H:%M:%S')
            diff = datetime.datetime.now(datetime.timezone.utc) - last_seen
            status = "ONLINE" if diff.total_seconds() < 900 else "OFFLINE"
        else:
            last_seen_str = "NUNCA"
            status = "DESCONHECIDO"
            
        print(f"PC: {doc.id} | Status: {status} | Visto em: {last_seen_str} | Versão: {data.get('versao')}")

    print("\n--- ÚLTIMAS REQUISIÇÕES DE NFC-e ---")
    reqs = db.collection('nfce_requests').order_by('created_at', direction=firestore.Query.DESCENDING).limit(5).get()
    for req in reqs:
        data = req.to_dict()
        created_at = data.get('created_at')
        created_at_str = created_at.strftime('%Y-%m-%d %H:%M:%S') if created_at else "N/A"
        print(f"ID: {req.id} | Status: {data.get('status')} | Criado em: {created_at_str} | CNPJ: {data.get('empresa', {}).get('cnpj')}")

if __name__ == "__main__":
    main()
