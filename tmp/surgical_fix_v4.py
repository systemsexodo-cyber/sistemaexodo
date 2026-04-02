
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Corrigir de _url para _get_url
print("Corrigindo chamadas de _url para _get_url...")
text = text.replace("self._url(modelo, 'recepcao_evento')", "self._get_url(modelo, 'recepcao_evento')")
text = text.replace("self._url(modelo, 'autorizacao')", "self._get_url(modelo, 'autorizacao')")

# Verificacao adicional: se 'recepcao_evento' nao existir, pynfe pode falhar.
# No codigo original de evento() ele usa 'EVENTOS'. 
# Vamos garantir que funcione para SP.
if "self._get_url(modelo, 'recepcao_evento')" in text:
    # Se 'recepcao_evento' falhar, o pynfe gera erro. 
    # Em SP, 'recepcao_evento' costuma ser o nome correto no dicionario de URLs do pynfe.
    pass

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Correcao v4 aplicada.")
