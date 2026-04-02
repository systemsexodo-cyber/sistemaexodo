import firebase_admin
from firebase_admin import credentials, firestore
import json
import os

def check_one():
    cred_file = "backend_nfce/firebase-credentials.json"
    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_file)
        firebase_admin.initialize_app(cred)
        
    db = firestore.client()
    doc = db.collection('nfce_requests').document('80UuIdU3L3H6F7v7Bv7B').get()
    if doc.exists:
        print(json.dumps(doc.to_dict(), indent=2, default=str))
    else:
        print("Doc not found")

if __name__ == "__main__":
    check_one()
