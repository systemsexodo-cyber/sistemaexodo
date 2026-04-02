import firebase_admin
from firebase_admin import credentials, firestore
import os

cred_path = 'backend_nfce/firebase-credentials.json'
if not firebase_admin._apps:
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()
doc_id = "TZpCXotqOm5jRpyZTzqx"

doc = db.collection('nfce_requests').document(doc_id).get()
if doc.exists:
    print(doc.to_dict())
else:
    print("Not found")
