"""
Debug Script: Testa a geração de QR Code com o XML real salvo em TEMP.
Execute: python tmp/debug_qrcode.py
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend_nfce'))

from lxml import etree

# Carregar o último XML gerado
temp_xml = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_nfce.xml')
print(f"[1] Carregando XML de: {temp_xml}")

with open(temp_xml, 'rb') as f:
    xml_bytes = f.read()

xml_element = etree.fromstring(xml_bytes)
print(f"[2] Root tag: {xml_element.tag}")
print(f"[3] Filhos diretos: {[c.tag for c in xml_element]}")

# Verificar namespace
ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
sig = {"sig": "http://www.w3.org/2000/09/xmldsig#"}

# Tentar extrair dados do QR Code
print("\n[4] Testando XPaths para QR Code:")
try:
    chave = xml_element.xpath("ns:infNFe/@Id", namespaces=ns)
    print(f"    chave (xpath): {chave}")
    if chave:
        chave_val = chave[0][3:]  # Remove 'NFe'
        print(f"    chave_val: {chave_val}")
    else:
        print("    ERRO: infNFe/@Id retornou vazio!")
except Exception as e:
    print(f"    ERRO XPath: {e}")

try:
    v_nf = xml_element.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vNF/text()", namespaces=ns)
    print(f"    vNF: {v_nf}")
except Exception as e:
    print(f"    ERRO vNF: {e}")

try:
    digest = xml_element.xpath("sig:Signature/sig:SignedInfo/sig:Reference/sig:DigestValue/text()", namespaces=sig)
    print(f"    DigestValue: {digest[:1]}")
except Exception as e:
    print(f"    ERRO DigestValue: {e}")

try:
    tpamb = xml_element.xpath("ns:infNFe/ns:ide/ns:tpAmb/text()", namespaces=ns)
    print(f"    tpAmb: {tpamb}")
except Exception as e:
    print(f"    ERRO tpAmb: {e}")

try:
    uf_val = xml_element.xpath("ns:infNFe/ns:ide/ns:cUF/text()", namespaces=ns)
    print(f"    cUF: {uf_val}")
except Exception as e:
    print(f"    ERRO cUF: {e}")

# Testar importação das flags NFCE
print("\n[5] Testando importação das flags NFCE:")
try:
    from pynfe.utils.flags import NFCE, VERSAO_QRCODE
    uf_code = "35"
    print(f"    NFCE importado. Chaves disponíveis: {list(NFCE.keys())[:5]}")
    print(f"    VERSAO_QRCODE: {VERSAO_QRCODE}")
    if uf_code in NFCE:
        print(f"    NFCE[{uf_code}]: {NFCE[uf_code]}")
    else:
        print(f"    ERRO: UF '{uf_code}' não encontrada em NFCE!")
except Exception as e:
    print(f"    ERRO ao importar flags: {e}")
    import traceback; traceback.print_exc()

# Agora testar a geração completa do QR Code
print("\n[6] Testando geração completa do QR Code (simulação):")
try:
    # CSC e IdToken de TESTE - Vamos simular com valores fictícios
    csc_teste = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"  # 32 chars (padrão SP SEFAZ)
    id_token_teste = "1"
    
    from pynfe.processamento.serializacao import SerializacaoQrcode
    
    # Verificar se o monkeypatch foi aplicado
    import nfce_handler  # Isso vai aplicar os monkeypatches
    
    print(f"    nfce_handler importado com sucesso!")
    print(f"    SerializacaoQrcode.gerar_qrcode está monkeypatched: {SerializacaoQrcode.gerar_qrcode.__module__ == 'nfce_handler'}")
    
    qrcode_gen = SerializacaoQrcode()
    xml_com_qr = qrcode_gen.gerar_qrcode(
        token=id_token_teste,
        csc=csc_teste,
        xml=xml_element
    )
    
    # Verificar se o infNFeSupl foi adicionado
    supl = xml_com_qr.find(".//{http://www.portalfiscal.inf.br/nfe}infNFeSupl")
    if supl is not None:
        qr = supl.find("{http://www.portalfiscal.inf.br/nfe}qrCode")
        url = supl.find("{http://www.portalfiscal.inf.br/nfe}urlChave")
        print(f"    [OK] infNFeSupl adicionado!")
        print(f"    qrCode: {qr.text[:80] if qr is not None else 'AUSENTE'}...")
        print(f"    urlChave: {url.text if url is not None else 'AUSENTE'}")
    else:
        print(f"    [ERRO] infNFeSupl NÃO foi adicionado!")
        
except Exception as e:
    print(f"    ERRO: {e}")
    import traceback; traceback.print_exc()

print("\n[CONCLUÍDO]")
