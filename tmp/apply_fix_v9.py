
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Substituir o try: ... except: pass de uma linha so por multiplas linhas para evitar SyntaxError
# Antes: if os.path.exists(chave): try: os.remove(chave) except: pass
# Varios lugares no _post tem esse padrao. Vamos consertar todos.

def replace_one_liner_try(text):
    # Procura '): try: ' e substitui por ):\n            try:
    text = text.replace("): try: ", "):\\n            try: ")
    # Procura '} except: pass' e substitui por }\\n            except: pass
    text = text.replace("} except: pass", "}\\n            except: pass")
    # Procura 'try: os.remove(chave) except: pass' e similares e quebra
    text = text.replace("try: os.remove(chave) except: pass", "try:\\n                os.remove(chave)\\n            except: pass")
    text = text.replace("try: os.remove(cert) except: pass", "try:\\n                os.remove(cert)\\n            except: pass")
    text = text.replace("try: certificado_a1.excluir() except: pass", "try:\\n                certificado_a1.excluir()\\n            except: pass")
    return text

text = replace_one_liner_try(text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Patch v9 (SyntaxError Fix) aplicado.")
