
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Corrigir o bloco finally que tem sintaxe invalida (try/except na mesma linha)
print("Corrigindo sintaxe do bloco finally...")

correct_finally = """        finally:
            if os.path.exists(chave):
                try: os.remove(chave)
                except: pass
            if os.path.exists(cert):
                try: os.remove(cert)
                except: pass
            try:
                certificado_a1.excluir()
            except:
                pass"""

# Localizar o bloco problematico e substituir
text = re.sub(r'finally:.*?certificado_a1\.excluir\(\) except: pass', correct_finally, text, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Sintaxe corrigida.")
