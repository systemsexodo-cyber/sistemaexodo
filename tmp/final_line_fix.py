
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# Localizar cancelar_nfce_pynfe
start_idx = -1
for i, line in enumerate(lines):
    if "def cancelar_nfce_pynfe(req_dict):" in line:
        start_idx = i
        break

if start_idx != -1:
    print(f"Substituindo cancelar_nfce_pynfe em {start_idx+1}...")
    # Tenta achar o fim do bloco
    end_idx = start_idx + 1
    for j in range(start_idx + 1, len(lines)):
        if "traceback.format_exc()}" in lines[j]:
            end_idx = j + 1
            break
    
    new_cancel = [
        'def cancelar_nfce_pynfe(req_dict):\n',
        '    """Cancela uma NFC-e delegando a assinatura para o ComunicacaoSefaz."""\n',
        '    from pynfe.processamento.comunicacao import ComunicacaoSefaz\n',
        '    from lxml import etree\n',
        '    from datetime import datetime\n',
        '    import base64\n',
        '    import tempfile\n',
        '    import os\n',
        '    import re\n',
        '    try:\n',
        '        empresa_data = req_dict.get("empresa", {})\n',
        '        chave_acesso = req_dict.get("chave_acesso")\n',
        '        justificativa = req_dict.get("justificativa", "Cancelamento por erro de emissao")\n',
        '        protocolo = req_dict.get("protocolo")\n',
        '        if not chave_acesso or not empresa_data.get("certificado_base64"):\n',
        '            return {"success": False, "error": "Dados insuficientes"}\n',
        '        senha_cert = empresa_data.get("senha_certificado")\n',
        '        uf = empresa_data.get("uf", "SP")\n',
        '        is_homolog = (empresa_data.get("ambiente") == 2)\n',
        '        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))\n',
        '        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp:\n',
        '            tmp.write(cert_data)\n',
        '            caminho_cert = tmp.name\n',
        '        try:\n',
        '            dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")\n',
        '            xml_str = f\'\'\'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">\n',
        '                <infEvento Id="ID110111{chave_acesso}01">\n',
        '                    <cOrgao>35</cOrgao><tpAmb>{"2" if is_homolog else "1"}</tpAmb>\n',
        '                    <CNPJ>{re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))}</CNPJ>\n',
        '                    <chNFe>{chave_acesso}</chNFe><dhEvento>{dh_evento}</dhEvento>\n',
        '                    <tpEvento>110111</tpEvento><nSeqEvento>1</nSeqEvento><verEvento>1.00</verEvento>\n',
        '                    <detEvento versao="1.00"><descEvento>Cancelamento</descEvento><nProt>{protocolo}</nProt><xJust>{justificativa}</xJust></detEvento>\n',
        '                </infEvento></evento>\'\'\'\n',
        '            root = etree.fromstring(xml_str.encode("utf-8"))\n',
        '            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homolog)\n',
        '            resp = con.evento("nfce", root, 1)\n',
        '            \n',
        '            # Parser simples\n',
        '            r_text = resp.text if resp else ""\n',
        '            cstat = re.search(r"<cStat>(.*?)</cStat>", r_text)\n',
        '            cstat = cstat.group(1) if cstat else ""\n',
        '            xmotivo = re.search(r"<xMotivo>(.*?)</xMotivo>", r_text)\n',
        '            xmotivo = xmotivo.group(1) if xmotivo else "Sem resposta"\n',
        '            \n',
        '            success = cstat in ["135", "128", "101", "155"]\n',
        '            return {"success": success, "cStat": cstat, "xMotivo": xmotivo, "data": {"cStat": cstat, "xMotivo": xmotivo}}\n',
        '        finally:\n',
        '            if os.path.exists(caminho_cert): os.remove(caminho_cert)\n',
        '    except Exception as e:\n',
        '        import traceback\n',
        '        return {"success": False, "error": str(e), "traceback": traceback.format_exc()}\n'
    ]
    lines[start_idx:end_idx] = new_cancel

# Localizar _fixed_post
start_fixed = -1
for i, line in enumerate(lines):
    if "def _fixed_post(self, url, xml, timeout=None):" in line:
        start_fixed = i
        break

if start_fixed != -1:
    print(f"Substituindo _fixed_post em {start_fixed+1}...")
    end_fixed = start_fixed + 1
    for k in range(start_fixed + 1, len(lines)):
        if "certificado_a1.excluir()" in lines[k]:
            end_fixed = k + 1
            break
    
    new_fixed = [
        '    def _fixed_post(self, url, xml, timeout=None):\n',
        '        from pynfe.utils import etree as _etree\n',
        '        from pynfe.entidades.certificado import CertificadoA1 as _CertA1\n',
        '        import re, os, requests as _requests\n',
        '        certificado_a1 = _CertA1(self.certificado)\n',
        '        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)\n',
        '        chave_cert = (cert, chave)\n',
        '        try:\n',
        '            xml_declaration = \'<?xml version="1.0" encoding="UTF-8"?>\'\n',
        '            xml_raw = _etree.tostring(xml, encoding="unicode").replace("\\n", "")\n',
        '            if "<enviNFe" in xml_raw:\n',
        '                xml_str = re.sub("<qrCode>(.*?)</qrCode>", lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), xml_raw)\n',
        '                xml_final = xml_declaration + xml_str\n',
        '            else:\n',
        '                xml_str = xml_raw\n',
        '                if "ns0:" in xml_str or "ns1:" in xml_str: xml_str = re.sub(r"<(/?)ns[0-9]+:", r"<\\1", xml_str)\n',
        '                xml_str = xml_str.replace("<envEvento", \'<envEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')\n',
        '                xml_str = xml_str.replace("<evento", \'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')\n',
        '                xml_str = xml_str.replace("<detEvento", \'<detEvento versao="1.00"\')\n',
        '                xml_str = re.sub(r"<Signature(\\s|>) ", r"<Signature xmlns=\\"http://www.w3.org/2000/09/xmldsig#\\"\\1", xml_str)\n',
        '                xml_final = xml_declaration + xml_str\n',
        '            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)\n',
        '            res.encoding = "utf-8"\n',
        '            return res\n',
        '        finally:\n',
        '            certificado_a1.excluir()\n'
    ]
    lines[start_fixed:end_fixed] = new_fixed

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Sucesso total.")
