import base64
import tempfile
import os
from pynfe.processamento.comunicacao import ComunicacaoSefaz

def check_status():
    keys = [
        '35260304829400000165650010000001241694161989', # Correct key (2026/03)
        '35250604829400000165650010000001241813859290'  # Rejected key mentioned in error (2025/06)
    ]
    uf = 'SP'
    pwd = 'Rotwailler1'
    
    import firebase_admin
    from firebase_admin import credentials, firestore
    cred = credentials.Certificate('firebase-credentials.json')
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    
    empresa = db.collection('empresas').document('22ae2c16-a730-43f3-a4f9-19f105eb0d13').get().to_dict()
    cert_base64 = empresa['configuracoes'].get('certificadoDigitalBytes')
    
    cert_data = base64.b64decode(cert_base64)
    with tempfile.NamedTemporaryFile(delete=False, suffix='.pfx') as tf:
        tf.write(cert_data)
        cert_path = tf.name
        
    try:
        con = ComunicacaoSefaz(uf=uf, certificado=cert_path, certificado_senha=pwd, homologacao=False)
        for chave in keys:
            print(f"\n--- Checking key {chave} ---")
            resp = con.consulta_nota(modelo='nfce', chave=chave)
            print(f"Status Code: {resp.status_code}")
            print(f"Response: {resp.text}")
    finally:
        if os.path.exists(cert_path):
            os.remove(cert_path)

if __name__ == "__main__":
    check_status()
