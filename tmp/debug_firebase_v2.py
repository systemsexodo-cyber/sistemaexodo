import firebase_admin
from firebase_admin import credentials, firestore
import os
import time
from datetime import datetime

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

print(f"--- DEBUG FIREBASE ---")
print(f"Local Time: {datetime.now()}")
print(f"UTC Time (System): {datetime.utcnow()}")
print(f"Time Unix: {time.time()}")

try:
    print(f"Tentando inicializar com: {cred_path}")
    if firebase_admin._apps:
        for app in list(firebase_admin._apps.values()):
            firebase_admin.delete_app(app)
            
    cred = credentials.Certificate(cred_path)
    # Tenta obter um token manualmente para ver o erro real sem o gRPC escondendo
    token = cred.get_access_token()
    print("Token gerado com sucesso!")
    print(f"Expires at: {token.expiry}")
    
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    print("Firestore client OK. Tentando gravar...")
    
    db.collection('test_connection').document('ping').set({
        'timestamp': firestore.SERVER_TIMESTAMP,
        'msg': 'Teste de conexao manual'
    })
    print("Gravação OK!")
    
except Exception as e:
    print(f"ERRO IDENTIFICADO: {e}")
    import traceback
    traceback.print_exc()
