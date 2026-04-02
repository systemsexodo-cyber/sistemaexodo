
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Corrigir de keys erradas para as keys oficiais do pynfe
print("Corrigindo keys de URL para EVENTOS e AUTORIZACAO...")
text = text.replace("self._get_url(modelo, 'recepcao_evento')", "self._get_url(modelo, 'EVENTOS')")
text = text.replace("self._get_url(modelo, 'autorizacao')", "self._get_url(modelo, 'AUTORIZACAO')")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Correcao v5 aplicada.")
