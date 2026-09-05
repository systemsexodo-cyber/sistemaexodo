"""Inspeciona o XML e valida contra o schema NFC-e manualmente."""
import os
from lxml import etree

xml_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_nfce.xml')
ns = "http://www.portalfiscal.inf.br/nfe"

xml_doc = etree.parse(xml_path)
root = xml_doc.getroot()

inf_nfe = root.find(f"{{{ns}}}infNFe")
ide = inf_nfe.find(f"{{{ns}}}ide")
transp = inf_nfe.find(f"{{{ns}}}transp")

# modFrete
print(f"modFrete: {transp.find(f'{{{ns}}}modFrete').text}")

# xNome
emit = inf_nfe.find(f"{{{ns}}}emit")
xnome = emit.find(f"{{{ns}}}xNome")
print(f"xNome: '{xnome.text}' (len={len(xnome.text)})")

# QR Code token
inf_supl = root.find(f"{{{ns}}}infNFeSupl")
if inf_supl is not None:
    qr = inf_supl.find(f"{{{ns}}}qrCode")
    print(f"QR: {qr.text[:120]}")

# Verificar se infNFeSupl está na posição correta (entre infNFe[0] e Signature[2])
print(f"\nOrdem dos filhos do NFe:")
for i, child in enumerate(root):
    print(f"  [{i}] {child.tag.split('}')[-1]}")

# Simular o enviNFe que o pynfe vai criar
from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
enviNFe = etree.Element("enviNFe", xmlns=NAMESPACE_NFE, versao=VERSAO_PADRAO)
etree.SubElement(enviNFe, "idLote").text = "1"
etree.SubElement(enviNFe, "indSinc").text = "1"
enviNFe.append(root)

print(f"\nXML enviNFe montado:")
result = etree.tostring(enviNFe, encoding='unicode')
print(result[:500])
