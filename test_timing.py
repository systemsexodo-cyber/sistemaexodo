import json, time, base64, os, sys
sys.path.insert(0, 'backend_nfce')

with open('empresa_dump.json', 'r') as f:
    data = json.load(f)

razao = data['razao_social']
configs = data['configuracoes']
configs = configs if isinstance(configs, dict) else json.loads(configs or '{}')
cert_b64 = configs.get('certificadoDigitalBytes')
senha = data['senha'] or configs.get('certificadoDigitalSenha')
homologacao = data['homologacao']

print(f'Empresa: {razao}')
print(f'Homologacao: {homologacao}')
print(f'Cert b64 len: {len(cert_b64) if cert_b64 else 0}, Senha: {bool(senha)}')

from cryptography.hazmat.primitives.serialization import pkcs12
t0 = time.time()
pfx_bytes = base64.b64decode(cert_b64)
key, cert, extras = pkcs12.load_key_and_certificates(pfx_bytes, senha.encode())
print(f'1. PKCS12 load time: {time.time()-t0:.3f}s')

from pynfe.entidades.certificado import CertificadoA1
import tempfile
tmp_pfx = os.path.join(tempfile.gettempdir(), 'test_cert.pfx')
with open(tmp_pfx, 'wb') as f:
    f.write(pfx_bytes)

t1 = time.time()
cert_a1 = CertificadoA1(tmp_pfx)
chave_path, cert_path = cert_a1.separar_arquivo(senha, caminho=True)
print(f'2. CertificadoA1.separar_arquivo time: {time.time()-t1:.3f}s')

import requests
import urllib3
urllib3.disable_warnings()

url_status = 'https://homologacao.nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx' if homologacao else 'https://nfce.fazenda.sp.gov.br/ws/NFeStatusServico4.asmx'
print(f'Testing SEFAZ URL: {url_status}')

for i in range(3):
    t2 = time.time()
    try:
        r = requests.get(url_status, cert=(cert_path, chave_path), verify=False, timeout=15)
        print(f'3.{i+1} SEFAZ mTLS GET status: {r.status_code}, time: {time.time()-t2:.3f}s')
    except Exception as e:
        print(f'3.{i+1} SEFAZ error: {e}, time: {time.time()-t2:.3f}s')

cert_a1.excluir()
if os.path.exists(tmp_pfx): os.remove(tmp_pfx)
