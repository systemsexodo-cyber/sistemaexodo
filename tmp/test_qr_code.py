from lxml import etree
import re
from decimal import Decimal

# Simulator for nfce_handler logic
def test_xml_gen():
    ns_nfe = "http://www.portalfiscal.inf.br/nfe"
    
    # Simple NFe structure
    nfe = etree.Element(f"{{{ns_nfe}}}NFe")
    infNFe = etree.SubElement(nfe, f"{{{ns_nfe}}}infNFe")
    infNFe.set("Id", "NFe35260304829400000165650010724781061897686852")
    
    ide = etree.SubElement(infNFe, f"{{{ns_nfe}}}ide")
    etree.SubElement(ide, f"{{{ns_nfe}}}tpAmb").text = "2"
    etree.SubElement(ide, f"{{{ns_nfe}}}cUF").text = "35"
    
    total = etree.SubElement(infNFe, f"{{{ns_nfe}}}total")
    icms_tot = etree.SubElement(total, f"{{{ns_nfe}}}ICMSTot")
    etree.SubElement(icms_tot, f"{{{ns_nfe}}}vNF").text = "100.00"
    
    # Signature placeholder
    sig_ns = "http://www.w3.org/2000/09/xmldsig#"
    signature = etree.SubElement(nfe, f"{{{sig_ns}}}Signature")
    signed_info = etree.SubElement(signature, f"{{{sig_ns}}}SignedInfo")
    reference = etree.SubElement(signed_info, f"{{{sig_ns}}}Reference")
    etree.SubElement(reference, f"{{{sig_ns}}}DigestValue").text = "digest_value"

    print("--- BEFORE ---")
    print(etree.tostring(nfe, pretty_print=True).decode())

    # Mock the gerar_qrcode logic
    def mock_gerar_qrcode(nfe, token="1", csc="CSC_VALUE"):
        ns = {"ns": "http://www.portalfiscal.inf.br/nfe"}
        sig = {"sig": "http://www.w3.org/2000/09/xmldsig#"}
        
        # Line 184 logic:
        # If nfe is <NFe>, then ns:infNFe/@Id works.
        try:
            chave = nfe.xpath("ns:infNFe/@Id", namespaces=ns)[0][3:]
            v_nf = nfe.xpath("ns:infNFe/ns:total/ns:ICMSTot/ns:vNF/text()", namespaces=ns)[0]
            digest = nfe.xpath("sig:Signature/sig:SignedInfo/sig:Reference/sig:DigestValue/text()", namespaces=sig)[0]
            print(f"Extracted: Chave={chave}, vNF={v_nf}, Digest={digest}")
        except Exception as e:
            print(f"Extraction failed: {e}")
            return nfe

        # infNFeSupl logic Line 227
        info = etree.Element(f"{{{ns_nfe}}}infNFeSupl")
        etree.SubElement(info, f"{{{ns_nfe}}}qrCode").text = etree.CDATA("http://url_qr_code")
        etree.SubElement(info, f"{{{ns_nfe}}}urlChave").text = "http://url_chave"
        
        # Line 232: insert at 1
        nfe.insert(1, info)
        return nfe

    nfe_final = mock_gerar_qrcode(nfe)
    
    print("--- AFTER ---")
    print(etree.tostring(nfe_final, pretty_print=True).decode())

test_xml_gen()
