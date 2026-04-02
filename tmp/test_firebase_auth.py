import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = 'backend_nfce/firebase-credentials.json'
if not os.path.exists(cred_path):
    print(f"ERRO: {cred_path} nao existe")
    exit(1)

try:
    cred = credentials.Certificate(cred_path)
    # Tenta inicializar e fazer uma query simples
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    print("Tentando ler colecao 'bridge_config'...")
    doc = db.collection('bridge_config').document('latest').get()
    if doc.exists:
        print(f"SUCESSO! Versao atual na nuvem: {doc.to_dict().get('version')}")
    else:
        print("Documento nao encontrado, mas conexao OK.")
except Exception as e:
    print(f"FALHA NA CONEXAO FIREBASE: {e}")
