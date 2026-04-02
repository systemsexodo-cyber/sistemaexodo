
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# 1. Corrigir o Regex do Signature no _fixed_post
print("Refinando _fixed_post para evitar corrupcao de SignatureMethod...")
# O problema anterior era o excesso de backslashes e o regex pegando SignatureMethod

old_line = 'xml_str = re.sub(r"<Signature(\\s|>)", r"<Signature xmlns=\\"http://www.w3.org/2000/09/xmldsig#\\"\\1", xml_str)'
# Vamos usar uma substituição mais segura via replace de strings específicas
new_logic = '''
                # Re-insere namespaces de forma limpa e segura
                xml_str = xml_str.replace("<envEvento", \'<envEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')
                xml_str = xml_str.replace("<evento", \'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')
                xml_str = xml_str.replace("<detEvento", \'<detEvento versao="1.00"\')
                
                # Signature: Substituir apenas se não tiver xmlns e for a tag exata
                if \'<Signature xmlns="\' not in xml_str:
                    xml_str = xml_str.replace("<Signature>", \'<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">\')
                    xml_str = xml_str.replace("<Signature ", \'<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" \')
                
                # Remover duplicidades acidentais (caso o replace tenha inserido onde já existia parciais)
                xml_str = xml_str.replace(\'xmlns="http://www.portalfiscal.inf.br/nfe" xmlns="http://www.portalfiscal.inf.br/nfe"\', \'xmlns="http://www.portalfiscal.inf.br/nfe"\')
                xml_str = xml_str.replace(\'xmlns="http://www.w3.org/2000/09/xmldsig#" xmlns="http://www.w3.org/2000/09/xmldsig#"\', \'xmlns="http://www.w3.org/2000/09/xmldsig#"\')
'''

# Localizar o bloco de substituição no _fixed_post
if '# Re-insere namespaces de forma limpa' in text:
    print("Localizado bloco de namespaces. Substituindo...")
    # Vamos usar uma abordagem de busca por linhas para ser mais preciso
    lines = text.splitlines()
    start_idx = -1
    end_idx = -1
    for i, line in enumerate(lines):
        if '# Re-insere namespaces de forma limpa' in line:
            start_idx = i
        if start_idx != -1 and 'xml_final = xml_declaration + xml_str' in line:
            end_idx = i
            break
    
    if start_idx != -1 and end_idx != -1:
        new_block = [
            '                # Re-insere namespaces de forma limpa e segura (Correcao SP)',
            '                xml_str = xml_str.replace("<envEvento", \'<envEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')',
            '                xml_str = xml_str.replace("<evento", \'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')',
            '                xml_str = xml_str.replace("<detEvento", \'<detEvento versao="1.00"\')',
            '                if \'<Signature xmlns="\' not in xml_str:',
            '                    xml_str = xml_str.replace("<Signature>", \'<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">\')',
            '                    xml_str = xml_str.replace("<Signature ", \'<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" \')',
            '                xml_str = xml_str.replace(\'xmlns="http://www.portalfiscal.inf.br/nfe" xmlns="http://www.portalfiscal.inf.br/nfe"\', \'xmlns="http://www.portalfiscal.inf.br/nfe"\')',
            '                xml_str = xml_str.replace(\'xmlns="http://www.w3.org/2000/09/xmldsig#" xmlns="http://www.w3.org/2000/09/xmldsig#"\', \'xmlns="http://www.w3.org/2000/09/xmldsig#"\')',
            '                xml_str = xml_str.replace(\' xmlns=""\', \'\')'
        ]
        lines[start_idx:end_idx] = new_block
        text = "\n".join(lines)

# 2. Ajuste fino no cancelar_nfce_pynfe para garantir a ordem das tags (SP rigorosa)
# cOrgao, tpAmb, CNPJ, chNFe, dhEvento, tpEvento, nSeqEvento, verEvento, detEvento
if 'def cancelar_nfce_pynfe(req_dict):' in text:
    print("Ajustando ordem das tags em cancelar_nfce_pynfe...")
    # Garantir que a ordem segue exatamente o XSD
    old_xml_str = 'xml_str = f\'\'\'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">'
    new_xml_str = 'xml_str = f\'\'\'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"><infEvento Id="ID110111{chave_acesso}01"><cOrgao>35</cOrgao><tpAmb>{"2" if is_homolog else "1"}</tpAmb><CNPJ>{re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))}</CNPJ><chNFe>{chave_acesso}</chNFe><dhEvento>{dh_evento}</dhEvento><tpEvento>110111</tpEvento><nSeqEvento>1</nSeqEvento><verEvento>1.00</verEvento><detEvento versao="1.00"><descEvento>Cancelamento</descEvento><nProt>{protocolo}</nProt><xJust>{justificativa}</xJust></detEvento></infEvento></evento>\'\'\''
    
    # Encontrar a linha da xml_str
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if 'xml_str = f\'\'\'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">' in line:
            # Substituir as próximas linhas até o fechamento da string
            end_q = -1
            for j in range(i, i+10):
                if '\'\'\'' in lines[j] and j > i:
                    end_q = j
                    break
            if end_q != -1:
                lines[i:end_q+1] = ['            ' + new_xml_str]
                break
    text = "\n".join(lines)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print("Sucesso.")
