
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# --- FIX 1: _fixed_post (Regex de Signature e Namespaces) ---
print("Corrigindo _fixed_post...")
start_fixed = -1
end_fixed = -1
for i, line in enumerate(lines):
    if "def _fixed_post(self, url, xml, timeout=None):" in line:
        start_fixed = i
    if start_fixed != -1 and "certificado_a1.excluir()" in line:
        end_fixed = i + 1
        break

if start_fixed != -1 and end_fixed != -1:
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
        '                # Fluxo de Eventos (Cancelamento)\n',
        '                xml_str = xml_raw\n',
        '                # Limpa nsX\n',
        '                if "ns0:" in xml_str or "ns1:" in xml_str: xml_str = re.sub(r"<(/?)ns[0-9]+:", r"<\\1", xml_str)\n',
        '                \n',
        '                # Re-insere namespaces de forma limpa\n',
        '                xml_str = xml_str.replace("<envEvento", \'<envEvento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')\n',
        '                xml_str = xml_str.replace("<evento", \'<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00"\')\n',
        '                xml_str = xml_str.replace("<detEvento", \'<detEvento versao="1.00"\')\n',
        '                \n',
        '                # Corrigir Signature de forma segura (SEM CORROMPER TAGS ADJACENTES)\n',
        '                # Usamos um replacement que garante espaco se houver atributos seguintes\n',
        '                xml_str = re.sub(r\'<Signature(\\\\s|>)\', r\'<Signature xmlns="http://www.w3.org/2000/09/xmldsig#"\\\\1\', xml_str)\n',
        '                \n',
        '                # Limpar duplicidades acidentais\n',
        '                xml_str = xml_str.replace(\'xmlns="http://www.portalfiscal.inf.br/nfe" xmlns="http://www.portalfiscal.inf.br/nfe"\', \'xmlns="http://www.portalfiscal.inf.br/nfe"\')\n',
        '                xml_final = xml_declaration + xml_str\n',
        '            \n',
        '            # Debug Logs\n',
        '            try:\n',
        '                dbg_name = "last_enviNFe.xml" if "<enviNFe" in xml_raw else "last_envEvento.xml"\n',
        '                with open(os.path.join(os.environ.get("TEMP", "C:/temp"), dbg_name), "w", encoding="utf-8") as f: f.write(xml_final)\n',
        '            except: pass\n',
        '            \n',
        '            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)\n',
        '            res.encoding = "utf-8"\n',
        '            \n',
        '            try:\n',
        '                with open(os.path.join(os.environ.get("TEMP", "C:/temp"), "last_sefaz_response.xml"), "w", encoding="utf-8") as f: f.write(res.text)\n',
        '            except: pass\n',
        '            \n',
        '            return res\n',
        '        finally:\n',
        '            certificado_a1.excluir()\n'
    ]
    lines[start_fixed:end_fixed] = new_fixed

# --- FIX 2: cancelar_nfce_pynfe (Compatibilidade de campos de retorno) ---
print("Corrigindo cancelar_nfce_pynfe...")
start_cancel = -1
end_cancel = -1
for i, line in enumerate(lines):
    if "def cancelar_nfce_pynfe(req_dict):" in line:
        start_cancel = i
    if start_cancel != -1 and "return {\"success\": False, \"error\": str(e), \"traceback\": traceback.format_exc()}" in line:
        end_cancel = i + 1
        break

if start_cancel != -1 and end_cancel != -1:
    new_cancel = [
        'def cancelar_nfce_pynfe(req_dict):\n',
        '    """Cancela uma NFC-e delegando a assinatura para o ComunicacaoSefaz robusto."""\n',
        '    from pynfe.processamento.comunicacao import ComunicacaoSefaz\n',
        '    from lxml import etree\n',
        '    from datetime import datetime\n',
        '    import base64, tempfile, os, re, traceback\n',
        '    try:\n',
        '        empresa_data = req_dict.get("empresa", {})\n',
        '        chave_acesso = req_dict.get("chave_acesso")\n',
        '        justificativa = req_dict.get("justificativa", "Cancelamento por erro de emissao ou devolucao")\n',
        '        protocolo = req_dict.get("protocolo")\n',
        '        if not chave_acesso or not empresa_data.get("certificado_base64"):\n',
        '            return {"success": False, "error": "Chave de acesso ou certificado ausentes.", "mensagem": "Dados insuficientes"}\n',
        '        \n',
        '        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))\n',
        '        senha_cert = empresa_data.get("senha_certificado")\n',
        '        uf = empresa_data.get("uf", "SP")\n',
        '        is_homolog = (empresa_data.get("ambiente") == 2)\n',
        '        \n',
        '        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp:\n',
        '            tmp.write(cert_data)\n',
        '            caminho_cert = tmp.name\n',
        '        try:\n',
        '            dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")\n',
        '            # XML limpo, sem assinatura (delegado ao ComunicacaoSefaz)\n',
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
        '            r_text = resp.text if resp else ""\n',
        '            if not r_text:\n',
        '                return {"success": False, "error": "SEFAZ retornou resposta vazia", "mensagem": "Sem resposta da SEFAZ (Conexao interrompida?)"}\n',
        '            \n',
        '            cstat = re.search(r"<cStat>(.*?)</cStat>", r_text)\n',
        '            cstat = cstat.group(1) if cstat else ""\n',
        '            xmotivo = re.search(r"<xMotivo>(.*?)</xMotivo>", r_text)\n',
        '            xmotivo = xmotivo.group(1) if xmotivo else "Erro desconhecido na resposta da SEFAZ"\n',
        '            \n',
        '            success = cstat in ["135", "128", "101", "155"]\n',
        '            return {\n',
        '                "success": success, \n',
        '                "cStat": cstat, \n',
        '                "xMotivo": xmotivo, \n',
        '                "mensagem": xmotivo, \n',
        '                "error": None if success else xmotivo,\n',
        '                "data": {"cStat": cstat, "xMotivo": xmotivo}\n',
        '            }\n',
        '        finally:\n',
        '            if os.path.exists(caminho_cert): os.remove(caminho_cert)\n',
        '    except Exception as e:\n',
        '        return {"success": False, "error": str(e), "mensagem": f"Erro interno: {str(e)}", "traceback": traceback.format_exc()}\n'
    ]
    lines[start_cancel:end_cancel] = new_cancel

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
print("Patch aplicado com sucesso.")
