import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('c:/Users/USER/.gemini/antigravity/sistema_exodo_01-12/backend_nfce/firebase-credentials.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
# The ID of the record is the access key
key = "35260304829400000165650010734224451899926835"
company_id = "22ae2c16-a730-43f3-a4f9-19f105eb0d13"

# In some structures, nfces might be a subcollection of company
# Let's check common locations.
docs = db.collection('nfces').where('chaveAcesso', '==', key).get()
for doc in docs:
    print(f"Deletando record na coleção global 'nfces': {doc.id}")
    doc.reference.delete()

# Checking if it's in empresa/id/nfces
docs = db.collection('empresas').document(company_id).collection('nfces').document(key).get()
if docs.exists:
    print(f"Deletando record na subcoleção da empresa: {key}")
    docs.reference.delete()
