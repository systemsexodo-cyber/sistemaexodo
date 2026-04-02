from PIL import Image, ImageDraw
import os

def create_status_icons():
    base_dir = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12'
    
    def create_circle_icon(color, name):
        # Cria uma imagem 64x64 com fundo transparente
        img = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        # Desenha um círculo preenchido
        draw.ellipse([4, 4, 60, 60], fill=color, outline=(255, 255, 255, 200), width=2)
        
        # Salva como ICO
        path = os.path.join(base_dir, name)
        img.save(path, format='ICO')
        print(f"Icone criado: {path}")

    create_circle_icon((34, 197, 94, 255), 'icon_green.ico')  # Emerald Green
    create_circle_icon((239, 68, 68, 255), 'icon_red.ico')    # Red
    create_circle_icon((249, 115, 22, 255), 'icon_orange.ico') # Orange

create_status_icons()
