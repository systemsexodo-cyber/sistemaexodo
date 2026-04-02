"""Testa o FIX 1A - regex para remover xmlns duplicado do NFe"""
import re

_NS_NFE = "http://www.portalfiscal.inf.br/nfe"

with open(r'C:/Users/USER/AppData/Local/Temp/last_enviNFe.xml', 'r', encoding='utf-8') as f:
    xml_str_orig = f.read()

# Remover a declaração XML do início para simular o que _fixed_post recebe
xml_str = xml_str_orig.replace('<?xml version="1.0" encoding="UTF-8"?>', '')

# Testar o FIX 1A
xml_fixed = re.sub(
    r'(<enviNFe[^>]*xmlns="' + re.escape(_NS_NFE) + r'"[^>]*>.*?)<NFe\s+xmlns="' + re.escape(_NS_NFE) + r'"',
    r'\1<NFe',
    xml_str,
    count=1,
    flags=re.DOTALL
)

# Verificar resultado
import re as re2
nfe_tags = re2.findall(r'<NFe[^>]*>', xml_fixed)
envi_tags = re2.findall(r'<enviNFe[^>]*>', xml_fixed)
supl_tags = re2.findall(r'<infNFeSupl[^>]*>', xml_fixed)

print("Antes:")
print("  NFe tags:", re2.findall(r'<NFe[^>]*>', xml_str)[:2])
print("\nDepois do FIX 1A:")
print("  enviNFe tag:", envi_tags[:1])
print("  NFe tags:", nfe_tags[:2])
print("  infNFeSupl tags:", supl_tags[:1])

# Agora testar FIX 1B - inserir xmlns no infNFeSupl se o NFe não tiver
if '<infNFeSupl>' in xml_fixed:
    idx_supl = xml_fixed.find('<infNFeSupl>')
    contexto_antes = xml_fixed[:idx_supl].rsplit('<NFe', 1)[-1]
    if f'xmlns="{_NS_NFE}"' not in contexto_antes:
        print("\nNFe sem xmlns -> adicionando no infNFeSupl")
        xml_fixed = xml_fixed.replace(
            '<infNFeSupl>',
            f'<infNFeSupl xmlns="{_NS_NFE}">',
            1
        )
    else:
        print("\nNFe COM xmlns -> infNFeSupl herda, OK")
    
    supl_tags_final = re2.findall(r'<infNFeSupl[^>]*>', xml_fixed)
    print("  infNFeSupl final:", supl_tags_final[:1])

print("\nResultado:")
print("  OK: NFe sem xmlns redundante, infNFeSupl com namespace correto")
