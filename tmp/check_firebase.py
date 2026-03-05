import firebase_admin
from firebase_admin import credentials, firestore
import os

base_path = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce"
cred_file = os.path.join(base_path, "firebase-credentials.json")

cred = credentials.Certificate(cred_file)
firebase_admin.initialize_app(cred)
db = firestore.client()

print("Empresas cadastradas no Firestore:")
empresas = db.collection('empresas').get()
for emp in empresas:
    data = emp.to_dict()
    print(f"ID: {emp.id} | Razão: {data.get('razaoSocial')} | Slug: {data.get('slug')}")

print("\nÚltimas 5 requisições no Firestore:")
for doc in docs:
    data = doc.to_dict()
    print(f"ID: {doc.id} | Status: {data.get('status')} | Data: {data.get('created_at')} | Empresa: {data.get('empresa', {}).get('cnpj')}")

cmds = db.collection('bridge_commands').where('status', '==', 'pendente').get()
print(f"\nComandos Remotos PENDENTES: {len(cmds)}")
for cmd in cmds:
    print(f"ID: {cmd.id} | Comando: {cmd.to_dict().get('comando')}")
