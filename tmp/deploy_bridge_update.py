import sys
import os
import datetime
import firebase_admin
from firebase_admin import credentials, firestore, storage

# Initialize firebase
cred = credentials.Certificate('backend_nfce/firebase-credentials.json')
firebase_admin.initialize_app(cred, {
    'storageBucket': 'exodosystems-1541d.firebasestorage.app'
})

db = firestore.client()
bucket = storage.bucket()

exe_path = 'backend_nfce/dist/ExodoNfceBridge.exe'
if not os.path.exists(exe_path):
    print(f"Erro: {exe_path} não encontrado!")
    sys.exit(1)

print("Iniciando Upload do Bridge para Firebase Storage...")
version = '2.8'
blob_name = f'bridge_updates/ExodoNfceBridge_v{version}.exe'
blob = bucket.blob(blob_name)

# Upload the file
blob.upload_from_filename(exe_path)
print(f"Upload concluído para {blob_name}.")

# Make it public and get the public URL natively 
# (Or we can generate a long-lived signed URL if public access is blocked)
# Generates a long-lived signed url (Valid for 100 years for example)
url = blob.generate_signed_url(expiration=datetime.timedelta(days=36500), method='GET')
print(f"URL Gerada: {url}")

# Update Firestore config
doc_ref = db.collection('bridge_config').document('latest')
doc_ref.set({
    'version': version,
    'download_url': url,
    'script_url': '',
    'updated_at': firestore.SERVER_TIMESTAMP
})
print("Coleção bridge_config/latest atualizada com sucesso!")
