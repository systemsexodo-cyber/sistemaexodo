
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# Corrigir a linha 9 que foi comentada incorretamente
print("Corrigindo import de OriginalComunicacaoSefaz...")
text = text.replace('# Usando ComunicacaoSefaz global as OriginalComunicacaoSefaz', 
                    'from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz')

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Correcao concluida.")
