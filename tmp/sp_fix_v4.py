
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

if not os.path.exists(path):
    print(f"Erro: Arquivo nao encontrado {path}")
    exit(1)

with open(path, 'rb') as f:
    text = f.read().decode('utf-8', errors='ignore')

# --- FIX 1: cancelar_nfce_pynfe ---
print("Aplicação do fix em cancelar_nfce_pynfe...")
# Vamos usar uma substituição de bloco mais segura sem depender de regex complexo para o replacement
start_marker = "def cancelar_nfce_pynfe(req_dict):"
end_marker = "return {'success': False, 'error': f'Erro interno: {str(e)}', 'traceback': traceback.format_exc()}"

if start_marker in text:
    parts = text.split(start_marker)
    after_func = parts[1].split(end_marker, 1)
    
    new_func_body = r'''
    """Cancela uma NFC-e de forma robusta, delegando a assinatura para o ComunicacaoSefaz."""
    from pynfe.entidades.certificado import CertificadoA1
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    from lxml import etree
    from datetime import datetime
    import base64
    import tempfile
    import os
    import re

    try:
        def log_message(msg): print(f"[CANCEL] {msg}")
        
        def parse_sefaz_resp(xml_text):
            if not xml_text: return None
            try:
                cStat, xMotivo = "", ""
                m_c = re.search(r'<cStat>(.*?)</cStat>', xml_text)
                if m_c: cStat = m_c.group(1).strip()
                m_x = re.search(r'<xMotivo>(.*?)</xMotivo>', xml_text)
                if m_x: xMotivo = m_x.group(1).strip()
                if cStat:
                    return {
                        'success': cStat in ['135', '128', '101', '155'],
                        'data': {'cStat': cStat, 'xMotivo': xMotivo},
                        'cStat': cStat
                    }
            except: pass
            return None

        empresa_data = req_dict.get('empresa', {})
        chave_acesso = req_dict.get('chave_acesso')
        justificativa = req_dict.get('justificativa', 'Cancelamento por erro de emissao ou devolucao de mercadoria')
        protocolo = req_dict.get('protocolo')

        if not chave_acesso or not empresa_data.get('certificado_base64'):
            return {'success': False, 'error': 'Chave de acesso ou certificado ausentes.'}

        cert_data = base64.b64decode(empresa_data.get('certificado_base64'))
        senha_cert = empresa_data.get('senha_certificado')
        uf = empresa_data.get('uf', 'SP')
        is_homologacao = (empresa_data.get('ambiente') == 2)

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp:
            tmp.write(cert_data)
            caminho_cert = tmp.name

        try:
            dh_evento = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00')
            id_evento = f"ID110111{chave_acesso}01"
            
            xml_str = f"""<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">
                <infEvento Id="{id_evento}">
                    <cOrgao>35</cOrgao>
                    <tpAmb>{'2' if is_homologacao else '1'}</tpAmb>
                    <CNPJ>{re.sub(r'[^0-9]', '', empresa_data.get('cnpj', ''))}</CNPJ>
                    <chNFe>{chave_acesso}</chNFe>
                    <dhEvento>{dh_evento}</dhEvento>
                    <tpEvento>110111</tpEvento>
                    <nSeqEvento>1</nSeqEvento>
                    <verEvento>1.00</verEvento>
                    <detEvento versao="1.00">
                        <descEvento>Cancelamento</descEvento>
                        <nProt>{protocolo}</nProt>
                        <xJust>{justificativa}</xJust>
                    </detEvento>
                </infEvento>
            </evento>"""
            
            root = etree.fromstring(xml_str.encode('utf-8'))
            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homologacao)
            resp = con.evento('nfce', root, 1)
            
            res = parse_sefaz_resp(resp.text if resp else "")
            
            if not res or res.get('cStat') in ['252', '494', '225']:
                is_homolog_retry = not is_homologacao
                con_retry = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homolog_retry)
                for tp in root.xpath('//*[local-name()="tpAmb"]'):
                    tp.text = '2' if is_homolog_retry else '1'
                
                resp_retry = con_retry.evento('nfce', root, 1)
                res_retry = parse_sefaz_resp(resp_retry.text if resp_retry else "")
                if res_retry: res = res_retry

            return res or {'success': False, 'error': 'Resposta malformada da SEFAZ', 'details': resp.text[:200] if resp else "Sem resposta"}
        finally:
            if os.path.exists(caminho_cert): os.remove(caminho_cert)
    except Exception as e:
        import traceback
'''
    text = parts[0] + start_marker + new_func_body + end_marker + after_func[1]

# --- FIX 2: _fixed_post ---
print("Aplicação do fix em _fixed_post...")
start_fixed = "def _fixed_post(self, url, xml, timeout=None):"
end_fixed = "certificado_a1.excluir()"

if start_fixed in text:
    parts = text.split(start_fixed)
    after_fixed = parts[1].split(end_fixed, 1)
    
    new_fixed_body = r'''
    """Interceptor SOAP para SP: Limpa namespaces nsX e evita corrupcao de SignatureMethod."""
    from pynfe.utils import etree as _etree
    from pynfe.entidades.certificado import CertificadoA1 as _CertA1
    import re
    import os
    import requests as _requests

    _NS_NFE = "http://www.portalfiscal.inf.br/nfe"
    _NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"

    certificado_a1 = _CertA1(self.certificado)
    chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
    chave_cert = (cert, chave)
    
    try:
        xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
        xml_raw = _etree.tostring(xml, encoding="unicode").replace("\n", "")

        if '<enviNFe' in xml_raw:
            xml_str = re.sub("<qrCode>(.*?)</qrCode>", lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), xml_raw)
            xml_final = xml_declaration + xml_str
        else:
            # Fluxo de Eventos: Limpeza Segura
            xml_str = xml_raw
            if 'ns0:' in xml_str or 'ns1:' in xml_str or 'ns2:' in xml_str:
                xml_str = re.sub(r'<(/?)ns[0-9]+:', r'<\1', xml_str)

            # Re-inserir namespaces nas tags base (MUITO CUIDADO COM SIGNATURE)
            xml_str = xml_str.replace('<envEvento', f'<envEvento xmlns="{_NS_NFE}" versao="1.00"')
            xml_str = xml_str.replace('<evento', f'<evento xmlns="{_NS_NFE}" versao="1.00"')
            xml_str = xml_str.replace('<detEvento', f'<detEvento versao="1.00"')
            
            # Signature: Usar regex com escape duplo para evitar erro de grupo
            xml_str = re.sub(r'<Signature(\s|>)', r'<Signature xmlns="' + _NS_DSIG + r'"\1', xml_str)
            
            xml_str = xml_str.replace(f'xmlns="{_NS_NFE}" xmlns="{_NS_NFE}"', f'xmlns="{_NS_NFE}"')
            xml_str = xml_str.replace('xmlns=""', '').replace('  ', ' ')
            xml_final = xml_declaration + xml_str

        # Debug
        try:
            temp_name = 'last_enviNFe.xml' if '<enviNFe' in xml_raw else 'last_envEvento.xml'
            dbg_path = os.path.join(os.environ.get('TEMP', 'C:/temp'), temp_name)
            with open(dbg_path, 'w', encoding='utf-8') as f: f.write(xml_final)
        except: pass

        result = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)
        result.encoding = "utf-8"
        
        try:
            resp_path = os.path.join(os.environ.get('TEMP', 'C:/temp'), 'last_sefaz_response.xml')
            with open(resp_path, 'w', encoding='utf-8') as f: f.write(result.text)
        except: pass

        return result
    finally:
'''
    text = parts[0] + start_fixed + new_fixed_body + end_fixed + after_fixed[1]

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Patch aplicado com sucesso via split.")
