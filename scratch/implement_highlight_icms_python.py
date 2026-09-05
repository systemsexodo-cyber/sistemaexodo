import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\backend_nfce\nfce_handler.py"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Injetar a injeção de ICMS900 na árvore DOM no Python ---
target_xml = """        # Garantir namespace correto em todo o XML (evitar xmlns="")
        ns_nfe = "http://www.portalfiscal.inf.br/nfe"
        fix_xml_namespaces(xml_element, ns_nfe)"""

replacement_xml = """        # Garantir namespace correto em todo o XML (evitar xmlns="")
        ns_nfe = "http://www.portalfiscal.inf.br/nfe"
        fix_xml_namespaces(xml_element, ns_nfe)

        # Injetar destaque de ICMS900 para Simples Nacional (NT 2025.002 / CSOSN 900)
        try:
            det_tags = xml_element.findall(f".//{{{ns_nfe}}}det")
            for idx, det in enumerate(det_tags):
                if idx < len(req.itens):
                    item_req = req.itens[idx]
                    csosn_atual = str(getattr(item_req, 'csosn', '') or '').strip()
                    if not csosn_atual:
                        csosn_atual = str(getattr(item_req, 'icms_csosn', '') or '').strip()
                    
                    if csosn_atual == '900':
                        imposto = det.find(f".//{{{ns_nfe}}}imposto")
                        if imposto is not None:
                            icms_tag = imposto.find(f".//{{{ns_nfe}}}ICMS")
                            if icms_tag is not None:
                                # Limpar filhos antigos do ICMS (como ICMS102 ou outro vazio)
                                for child in list(icms_tag):
                                    icms_tag.remove(child)
                                
                                # Criar a estrutura do ICMS900
                                icms900 = etree.SubElement(icms_tag, f"{{{ns_nfe}}}ICMS900")
                                etree.SubElement(icms900, f"{{{ns_nfe}}}orig").text = str(getattr(item_req, 'icms_origem', 0) or 0)
                                etree.SubElement(icms900, f"{{{ns_nfe}}}CSOSN").text = "900"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}modBC").text = "3" # Valor da operação
                                
                                vBC = float(getattr(item_req, 'icms_base_calculo', 0.0) or 0.0)
                                pRedBC = float(getattr(item_req, 'icms_reducao_bc', 0.0) or 0.0)
                                pICMS = float(getattr(item_req, 'icms_aliquota', 0.0) or 0.0)
                                vICMS = float(getattr(item_req, 'icms_valor', 0.0) or 0.0)
                                pCredSN = float(getattr(item_req, 'credito_aliquota', 0.0) or 0.0)
                                vCredICMSSN = float(getattr(item_req, 'credito_valor', 0.0) or 0.0)
                                
                                # Se não foi preenchido, calcula dinamicamente
                                if vBC <= 0.0:
                                    vBC = float(item_req.valor_total)
                                if vICMS <= 0.0 and pICMS > 0.0:
                                    vICMS = vBC * (pICMS / 100.0)
                                if vCredICMSSN <= 0.0 and pCredSN > 0.0:
                                    vCredICMSSN = vBC * (pCredSN / 100.0)
                                    
                                etree.SubElement(icms900, f"{{{ns_nfe}}}vBC").text = f"{vBC:.2f}"
                                if pRedBC > 0.0:
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}pRedBC").text = f"{pRedBC:.2f}"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}pICMS").text = f"{pICMS:.2f}"
                                etree.SubElement(icms900, f"{{{ns_nfe}}}vICMS").text = f"{vICMS:.2f}"
                                
                                if pCredSN > 0.0:
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}pCredSN").text = f"{pCredSN:.2f}"
                                    etree.SubElement(icms900, f"{{{ns_nfe}}}vCredICMSSN").text = f"{vCredICMSSN:.2f}"
        except Exception as e_icms:
            print(f">>> [FISCAL] ⚠️ Falha ao injetar bloco ICMS900: {e_icms}")"""

if target_xml in content:
    content = content.replace(target_xml, replacement_xml)
    print("DOM_XML_ICMS900_INJETADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_xml.replace("\r\n", "\n")
    normalized_replacement = replacement_xml.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DOM_XML_ICMS900_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_DOM_XML_ICMS900")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
