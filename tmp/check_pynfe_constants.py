from pynfe.utils.flags import VERSAO_QRCODE, CODIGOS_ESTADOS
from pynfe.utils.webservices import NFCE

print(f"VERSAO_QRCODE: {VERSAO_QRCODE}")
print(f"SP QR: {NFCE.get('SP', {}).get('QR')}")
print(f"SP HTTPS: {NFCE.get('SP', {}).get('HTTPS')}")
print(f"SP URL: {NFCE.get('SP', {}).get('URL')}")
