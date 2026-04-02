"""
Valida o XML contra o schema XSD da NFC-e e lista TODOS os erros.
Execute: python tmp/validar_xsd.py
"""
import sys, os
# Usar python puro sem importar nada do projeto para não travar
from lxml import etree

# Carregar o XML
xml_path = os.path.join(os.environ.get('TEMP', 'C:/Temp'), 'last_nfce.xml')
print(f"[1] Carregando: {xml_path}")

with open(xml_path, 'rb') as f:
    xml_bytes = f.read()

xml_doc = etree.fromstring(xml_bytes)
ns = "http://www.portalfiscal.inf.br/nfe"

print(f"[2] Root: {xml_doc.tag}")
print(f"[3] Filhos: {[c.tag.split('}')[-1] for c in xml_doc]}")

# Verificar campos críticos
def get(tag):
    el = xml_doc.find(f".//{{{ns}}}{tag}")
    return el.text if el is not None else "NAO_ENCONTRADO"

print("\n=== CAMPOS CRÍTICOS ===")
print(f"xNome: [{get('xNome')}] len={len(get('xNome'))}")
print(f"NCM: [{get('NCM')}] len={len(get('NCM'))}")
print(f"cEAN: [{get('cEAN')}]")
print(f"cEANTrib: [{get('cEANTrib')}]")
print(f"vUnCom: [{get('vUnCom')}]")
print(f"vUnTrib: [{get('vUnTrib')}]")
print(f"qCom: [{get('qCom')}]")
print(f"CSOSN: [{get('CSOSN')}]")
print(f"modFrete: [{get('modFrete')}]")
print(f"tpAmb: [{get('tpAmb')}]")
print(f"cIdToken no QR:")

# Verificar infNFeSupl
supl = xml_doc.find(f".//{{{ns}}}infNFeSupl")
if supl is None:
    supl = xml_doc.find(".//infNFeSupl")
    print(f"  infNFeSupl (sem ns): {supl is not None}")
else:
    print(f"  infNFeSupl (com ns): OK")
    qr = supl.find(f"{{{ns}}}qrCode") or supl.find("qrCode")
    if qr is not None and qr.text:
        # Extrair cIdToken do QR
        import re
        parts = qr.text.replace('<![CDATA[', '').replace(']]>', '').split('|')
        print(f"  QR partes: chNFe={parts[0][:10]}... versao={parts[1] if len(parts)>1 else '?'} tpAmb={parts[2] if len(parts)>2 else '?'} cIdToken=[{parts[3] if len(parts)>3 else '?'}]")
        cid = parts[3] if len(parts) > 3 else ''
        if cid and len(cid) > 6:
            print(f"  ⚠️  PROBLEMA: cIdToken tem {len(cid)} dígitos! Deveria ter 1-6 dígitos.")
            print(f"  CAUSA PROVÁVEL: Campo 'ID Token CSC' no app está preenchido com o CSC (token longo) em vez do ID numérico pequeno.")

# Verificar enviNFe
print("\n=== SIMULANDO enviNFe ===")
from pynfe.utils.flags import NAMESPACE_NFE, VERSAO_PADRAO
enviNFe = etree.Element("enviNFe", versao=VERSAO_PADRAO)
enviNFe.set("xmlns", NAMESPACE_NFE)
etree.SubElement(enviNFe, "idLote").text = "1"
etree.SubElement(enviNFe, "indSinc").text = "1"
enviNFe.append(xml_doc)

xml_str = etree.tostring(enviNFe, encoding='unicode')
print(f"enviNFe primeiros 200 chars:")
print(xml_str[:200])

# Tentar validar com XSD se disponível
pynfe_path = None
try:
    import pynfe
    pynfe_path = os.path.dirname(pynfe.__file__)
except:
    pass

if pynfe_path:
    xsd_candidates = [
        os.path.join(pynfe_path, 'data', 'XSD', 'nfe_v4.00.xsd'),
        os.path.join(pynfe_path, 'data', 'XSD', 'enviNFe_v4.00.xsd'),
        os.path.join(pynfe_path, 'Extra', 'XSD', 'nfe_v4.00.xsd'),
    ]
    for xsd_path in xsd_candidates:
        if os.path.exists(xsd_path):
            print(f"\n=== VALIDAÇÃO XSD: {xsd_path} ===")
            try:
                schema = etree.XMLSchema(etree.parse(xsd_path))
                result = schema.validate(xml_doc)
                if result:
                    print("✅ XML VÁLIDO!")
                else:
                    print("❌ ERROS DE SCHEMA:")
                    for err in schema.error_log:
                        print(f"  Linha {err.line}: {err.message}")
            except Exception as e:
                print(f"Erro ao validar: {e}")

print("\n[CONCLUÍDO]")
