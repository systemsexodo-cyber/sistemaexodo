import firebase_admin
from firebase_admin import credentials, firestore
import json

cred = credentials.Certificate("c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("--- BRIDGE STATUS ---")
docs = db.collection("bridge_status").get()
for doc in docs:
    data = doc.to_dict()
    print(f"{doc.id}: {data.get('pc_name')} - Online: {data.get('online')} - Last Seen: {data.get('last_seen')}")

print("\n--- PENDENTE REQUESTS ---")
reqs = db.collection("nfce_requests").where("status", "==", "pendente").get()
for req in reqs:
    print(f"Pendente: {req.id}")
    
print("\n--- PROCESSANDO REQUESTS ---")
reqs2 = db.collection("nfce_requests").where("status", "==", "processando").get()
for req in reqs2:
    print(f"Processando: {req.id}")
