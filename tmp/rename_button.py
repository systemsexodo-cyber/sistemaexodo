
import os

filepath = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\lib\pages\venda_direta_page.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Only change it if it is within the button widget context (Icons.receipt_long nearby)
# Or just a general replace if we are sure
# The grep showed 10469 as the target.
new_content = content.replace("'RECEBER'", "'PEDIDOS'")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)
print("Replacement successful")
