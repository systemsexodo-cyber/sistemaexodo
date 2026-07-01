from PIL import Image
import os

def convert_to_ico(source_png, target_ico):
    img = Image.open(source_png)
    # Windows icons usually contain multiple sizes
    icon_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    img.save(target_ico, sizes=icon_sizes)
    print(f"Sucesso: Icone final do 'e' criado em {target_ico}")

# Caminho da imagem nova com apenas o 'ê'
source = r"C:\Users\USER\.gemini\antigravity\brain\55072c69-00ec-4a20-b680-e0c6a97c5fd1\exodo_icon_letter_e_gold_1776037608907.png"
target = r"c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\windows\runner\resources\app_icon.ico"

if os.path.exists(source):
    convert_to_ico(source, target)
else:
    print(f"Erro: Arquivo fonte nao encontrado em {source}")
