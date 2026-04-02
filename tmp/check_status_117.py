import base64
import tempfile
import os
from pynfe.processamento.comunicacao import ComunicacaoSefaz
from lxml import etree

def check_status():
    chave = '35260304829400000165650010000001171990069434' # Note 117
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
        for homolog in [False, True]:
            env_name = "HOMOLOGAÇÃO" if homolog else "PRODUÇÃO"
            print(f"\n--- CHECKING IN {env_name} (tpAmb={'2' if homolog else '1'}) ---")
            con = ComunicacaoSefaz(uf=uf, certificado=cert_path, certificado_senha=pwd, homologacao=homolog)
            resp = con.consulta_nota(modelo='nfce', chave=chave)
            print(f"Status HTTP: {resp.status_code}")
            print(f"Resposta SEFAZ: {resp.text[:500]}...")
            
    finally:
        if os.path.exists(cert_path):
            os.remove(cert_path)

if __name__ == "__main__":
    check_status()
