
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

with open(path, 'rb') as f:
    content = f.read()

text = content.decode('utf-8', errors='ignore')

# Remove a linha ") que está sobrando após o print do patch
# Usamos regex para encontrar o print seguido opcionalmente de nova linha e depois ") solitário
# print("[PATCH] ...")
# ")
text = re.sub(r'print\("\[PATCH\] ComunicacaoSefaz\._post aplicado \(Definitivo / Correcao Namespaces\)"\)\s+"\)', 'print("[PATCH] ComunicacaoSefaz._post aplicado (Definitivo / Correcao Namespaces)")\n', text)

# Outra tentativa se tiver quebra de linha real
text = text.replace('Correcao Namespaces)")\n")', 'Correcao Namespaces)")')
text = text.replace('Correcao Namespaces)\")\n\")', 'Correcao Namespaces)\")')

# E se tiver espaços no meio
text = re.sub(r'print\("\[PATCH\].*?"\)\s*\n\s*"\)', 'print("[PATCH] ComunicacaoSefaz._post aplicado (Definitivo / Correcao Namespaces)")', text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Limpeza realizada.")
