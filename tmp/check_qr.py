"""Verifica o qrCode completo no XML"""
with open(r'C:/Users/USER/AppData/Local/Temp/last_enviNFe.xml', 'r', encoding='utf-8') as f:
    content = f.read()

# Encontrar o qrCode completo (incluindo CDATA)
import re
qr_match = re.search(r'<qrCode>(.*?)</qrCode>', content, re.DOTALL)
if qr_match:
    qr_full = qr_match.group(1)
    print(f"qrCode COMPLETO ({len(qr_full)} chars):")
    print(repr(qr_full))
    print("\nTexto legível:")
    print(qr_full)
else:
    print("qrCode não encontrado!")
    # Mostrar o contexto ao redor de infNFeSupl
    supl_idx = content.find('infNFeSupl')
    if supl_idx >= 0:
        print("\nContexto infNFeSupl:")
        print(content[supl_idx-5:supl_idx+300])
