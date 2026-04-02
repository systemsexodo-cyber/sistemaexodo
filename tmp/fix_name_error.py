
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    # Remove as linhas de monkeypatching externo que estao causando NameError
    if "ComunicacaoSefaz._post = _fixed_post" in line:
        print("Removendo monkeypatch invalido de _fixed_post")
        continue
    if "[PATCH] ComunicacaoSefaz._post aplicado" in line:
        continue
    new_lines.append(line)

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("Limpeza concluida.")
