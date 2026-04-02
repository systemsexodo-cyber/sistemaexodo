import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta, timezone

cred_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\firebase-credentials.json'

try:
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
    
    db = firestore.client()
    docs = db.collection('bridge_status').get()
    
    print(f"--- STATUS NO SERVIDOR (Ultimo Minuto) ---")
    now = datetime.now(timezone.utc)
    found = False
    for doc in docs:
        data = doc.to_dict()
        last_seen = data.get('last_seen')
        if last_seen:
            # last_seen is a datetime object
            diff = (now - last_seen).total_seconds()
            if diff < 120:
                print(f"✅ PC: {data.get('pc_name')} está ONLINE! (visto ha {diff:.1f}s)")
                found = True
            else:
                print(f"❌ PC: {data.get('pc_name')} visto ha {diff:.1f}s")
    
    if not found:
        print("Nenhum sinal de vida recente encontrado no servidor.")
        
except Exception as e:
    print(f"Erro ao consultar servidor: {e}")
