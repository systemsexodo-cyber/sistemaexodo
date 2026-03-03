"""Analisa rapidamente as tags de namespace no XML salvo"""
import re

with open(r'C:/Users/USER/AppData/Local/Temp/last_enviNFe.xml', 'r', encoding='utf-8') as f:
    content = f.read()

# Extrair o conteúdo entre nfeDadosMsg e o primeiro </NFe>
start = content.find('<enviNFe')
nfe_start = content.find('<NFe', start)
nfe_open = content[nfe_start:content.find('>', nfe_start)+1]
print("NFe tag:", nfe_open[:300])

envi_open = content[start:content.find('>', start)+1]
print("enviNFe tag:", envi_open[:300])

supl_start = content.find('<infNFeSupl')
if supl_start >= 0:
    supl_open = content[supl_start:content.find('>', supl_start)+1]
    print("infNFeSupl tag:", supl_open[:300])

# Verificar o QR Code
qr_start = content.find('<qrCode>')
qr_end = content.find('</qrCode>')
if qr_start >= 0:
    qr_text = content[qr_start+8:qr_end]
    print("qrCode:", qr_text[:150])
    
# Ver a resposta do SEFAZ se existir
import os
resp_path = r'C:/Users/USER/AppData/Local/Temp/last_sefaz_response.xml'
if os.path.exists(resp_path):
    with open(resp_path, 'r', encoding='utf-8') as f:
        resp = f.read()
    print("\nResposta SEFAZ:", resp[:500])
else:
    print("\nNão há arquivo de resposta SEFAZ salvo")
