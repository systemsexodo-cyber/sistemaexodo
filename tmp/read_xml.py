
import os
import re

path = r'C:\Users\USER\AppData\Local\Temp\last_envEvento.xml'

if not os.path.exists(path):
    print("Arquivo nao encontrado")
    exit(1)

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    xml = f.read()

# Limpar o XML para exibicao
xml_clean = re.sub(r'>\s+<', '><', xml)
# Pegar apenas o miolo do evento
match = re.search(r'<evento.*?</evento>', xml_clean)
if match:
    print("EVENTO XML:")
    print(match.group(0))
else:
    print("Bloco <evento> nao encontrado. XML completo (truncado):")
    print(xml_clean[:2000])
