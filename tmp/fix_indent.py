
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "class ComunicacaoSefaz(OriginalComunicacaoSefaz):" in line:
        lines[i] = "class ComunicacaoSefaz(OriginalComunicacaoSefaz):\n"
    if "def _fixed_post(self, url, xml, timeout=None):" in line:
        lines[i] = "    def _fixed_post(self, url, xml, timeout=None):\n"
    if "from pynfe.utils import etree as _etree" in line and i > 2880: # corpo do fixed_post
        if not line.startswith("        "):
            lines[i] = "        " + line.lstrip()

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Indêntação corrigida.")
