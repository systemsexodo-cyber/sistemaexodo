
import os

path = os.path.join(os.environ.get('TEMP', 'C:/temp'), 'last_envEvento.xml')

if not os.path.exists(path):
    print("Arquivo nao encontrado")
    exit(1)

with open(path, 'r', encoding='utf-8') as f:
    xml = f.read()

# Procurar pela Signature
sig_start = xml.find('<Signature')
if sig_start != -1:
    print(f"DEBUG SIGNATURE: {xml[sig_start:sig_start+150]}")
else:
    print("Signature nao encontrada")
