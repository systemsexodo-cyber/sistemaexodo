
import os

filepath = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\lib\pages\venda_direta_page.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace Delivery labels
new_content = content.replace("_isDelivery ? 'Delivery Ativo' : 'Delivery'", "_isDelivery ? 'Entrega Ativa' : 'Entregas'")

# Also replace some other common Delivery terms in the UI/Dialogs if needed
new_content = new_content.replace("'Configurar Delivery'", "'Configurar Entrega'")
new_content = new_content.replace("'Selecione um cliente antes de configurar o Delivery.'", "'Selecione um cliente antes de configurar a Entrega.'")
new_content = new_content.replace("'Selecione um endereço para o Delivery'", "'Selecione um endereço para a Entrega'")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)
print("Delivery rename successful")
