import base64
import tempfile
import os
from pynfe.processamento.comunicacao import ComunicacaoSefaz

def check_status():
    chave = '35260304829400000165650010000001181679438617' # Note 118
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
        print("\n--- CHECKING IN PRODUCTION (tpAmb=1) ---")
        con_p = ComunicacaoSefaz(uf=uf, certificado=cert_path, certificado_senha=pwd, homologacao=False)
        resp_p = con_p.consulta_nota(modelo='nfce', chave=chave)
        print(f"Status: {resp_p.status_code}")
        print(f"Body: {resp_p.text}")
        
        print("\n--- CHECKING IN HOMOLOGATION (tpAmb=2) ---")
        con_h = ComunicacaoSefaz(uf=uf, certificado=cert_path, certificado_senha=pwd, homologacao=True)
        resp_h = con_h.consulta_nota(modelo='nfce', chave=chave)
        print(f"Status: {resp_h.status_code}")
        print(f"Body: {resp_h.text}")
        
    finally:
        if os.path.exists(cert_path):
            os.remove(cert_path)

if __name__ == "__main__":
    check_status()
