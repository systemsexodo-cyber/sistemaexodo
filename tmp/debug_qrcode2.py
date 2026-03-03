"""
Debug Script v2: Testa a geração de QR Code após o fix.
Execute: python tmp/debug_qrcode2.py
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend_nfce'))

from lxml import etree

# Carregar o último XML gerado (deve ser o XML assinado, sem QR code ainda)
temp_xml = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_nfce.xml')
print(f"[1] Carregando XML de: {temp_xml}")

with open(temp_xml, 'rb') as f:
    xml_bytes = f.read()

xml_element = etree.fromstring(xml_bytes)
print(f"[2] Root tag: {xml_element.tag}")

# Verificar o import correto
print("\n[3] Testando importações corrigidas:")
try:
    from pynfe.utils.flags import CODIGOS_ESTADOS, VERSAO_QRCODE
    from pynfe.utils.webservices import NFCE
    print(f"    VERSAO_QRCODE: {VERSAO_QRCODE}")
    print(f"    CODIGOS_ESTADOS['SP']: {CODIGOS_ESTADOS.get('SP')}")
    print(f"    NFCE['SP']: {NFCE.get('SP')}")
    print(f"    [OK] Importações corretas!")
except Exception as e:
    print(f"    ERRO: {e}")
    import traceback; traceback.print_exc()

# Testar a geração completa do QR Code com o monkeypatch corrigido
print("\n[4] Testando geração completa do QR Code:")
try:
    import nfce_handler  # Aplica os monkeypatches
    from pynfe.processamento.serializacao import SerializacaoQrcode
    
    monkeypatched = SerializacaoQrcode.gerar_qrcode.__module__ == 'nfce_handler'
    print(f"    Monkeypatch aplicado: {monkeypatched}")
    
    # CSC e IdToken de TESTE - SP Homologação (values fictícios)
    csc_teste = "ABCDEFGHIJKLMNOPQRSTUVWXYZ123456"  
    id_token_teste = "1"
    
    qrcode_gen = SerializacaoQrcode()
    xml_com_qr, qr_url = qrcode_gen.gerar_qrcode(
        token=id_token_teste,
        csc=csc_teste,
        xml=xml_element,
        return_qr=True
    )
    
    # Verificar se o infNFeSupl foi adicionado
    ns_nfe = "http://www.portalfiscal.inf.br/nfe"
    supl = xml_com_qr.find(f".//{{{ns_nfe}}}infNFeSupl")
    if supl is not None:
        qr = supl.find(f"{{{ns_nfe}}}qrCode")
        url = supl.find(f"{{{ns_nfe}}}urlChave")
        print(f"\n    [OK] infNFeSupl adicionado com sucesso!")
        print(f"    qrCode URL: {qr.text[:100] if qr is not None else 'AUSENTE'}...")
        print(f"    urlChave: {url.text if url is not None else 'AUSENTE'}")
        print(f"\n    QR URL completa:\n    {qr_url}")
    else:
        print(f"    [ERRO] infNFeSupl NÃO foi adicionado!")
        # Listar todos os filhos
        print(f"    Filhos do root: {[c.tag for c in xml_com_qr]}")
        
except Exception as e:
    print(f"    ERRO: {e}")
    import traceback; traceback.print_exc()

print("\n[CONCLUÍDO]")
