
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

if not os.path.exists(path):
    print(f"Erro: Arquivo nao encontrado {path}")
    exit(1)

with open(path, 'rb') as f:
    content = f.read()

text = content.decode('utf-8', errors='ignore')

# --- FIX 1: cancelar_nfce_pynfe (Remover assinatura dupla e corrigir ambiente) ---
print("Corrigindo cancelar_nfce_pynfe...")
new_cancel_func = r'''
def cancelar_nfce_pynfe(req_dict):
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
            """Parser Ultra-Robusto com Regex Fallback para evitar Erro 500/Resposta Vazia."""
            if not xml_text: return None
            try:
                cStat, xMotivo = "", ""
                m_c = re.search(r'<cStat>(.*?)</cStat>', xml_text)
                if m_c: cStat = m_c.group(1).strip()
                m_x = re.search(r'<xMotivo>(.*?)</xMotivo>', xml_text)
                if m_x: xMotivo = m_x.group(1).strip()
                
                # Sucessos: 135 (Evento Registrado), 128 (Lote), 101 (Canc Homologado), 155 (Cancelado ja)
                if cStat:
                    return {
                        'success': cStat in ['135', '128', '101', '155'],
                        'data': {'cStat': cStat, 'xMotivo': xMotivo},
                        'cStat': cStat
                    }
            except: pass
            return None

        # Dados do request
        empresa_data = req_dict.get('empresa', {})
        chave_acesso = req_dict.get('chave_acesso')
        justificativa = req_dict.get('justificativa', 'Cancelamento por erro de emissao ou devolucao de mercadoria')
        protocolo = req_dict.get('protocolo')

        if not chave_acesso or not empresa_data.get('certificado_base64'):
            return {'success': False, 'error': 'Chave de acesso ou certificado ausentes.'}

        cert_b64 = empresa_data.get('certificado_base64')
        senha_cert = empresa_data.get('senha_certificado')
        uf = empresa_data.get('uf', 'SP')
        is_homologacao = (empresa_data.get('ambiente') == 2)

        cert_data = base64.b64decode(cert_b64)
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp:
            tmp.write(cert_data)
            caminho_cert = tmp.name

        try:
            # 1. Montagem do XML de Evento (Cru, sem assinatura - ComunicacaoSefaz assina)
            dh_evento = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00')
            id_evento = f"ID110111{chave_acesso}01"
            
            # XML Estrutural (SEFAZ-SP rigorosa com namespaces e versoes)
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
            
            # 2. Envio via ComunicacaoSefaz (que cuida da assinatura digital)
            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homologacao)
            # Ordem correta na pynfe: con.evento(modelo, root, id_lote)
            resp = con.evento('nfce', root, 1)
            
            res = parse_sefaz_resp(resp.text if resp else "")
            
            # Retrocompatibilidade de erro de ambiente (252) ou schema (225)
            if not res or res.get('cStat') in ['252', '494', '225']:
                log_message("Tentando ambiente alternativo...")
                is_homolog_retry = not is_homologacao
                con_retry = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homolog_retry)
                
                # Ajusta tpAmb no XML root antes da nova tentativa
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
        return {'success': False, 'error': f'Erro interno: {str(e)}', 'traceback': traceback.format_exc()}
'''

pattern_cancel = re.compile(r'def cancelar_nfce_pynfe\(req_dict\):.*?traceback\.format_exc\(\)\}', re.DOTALL)
if pattern_cancel.search(text):
    text = pattern_cancel.sub(new_cancel_func.strip(), text)
else:
    print("Nao foi possivel localizar cancelar_nfce_pynfe para substituicao.")

# --- FIX 2: _fixed_post (Corrigir corrupcao de SignatureMethod e namespaces) ---
print("Corrigindo _fixed_post...")
new_fixed_post = r'''
def _fixed_post(self, url, xml, timeout=None):
    """_post robusto para SP: foca em namespaces limpos e evita corrupcao de tags."""
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
            # --- EMISSAO ---
            xml_str = re.sub("<qrCode>(.*?)</qrCode>", lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), xml_raw)
            xml_final = xml_declaration + xml_str
        else:
            # --- EVENTOS (CANCELAMENTO) ---
            # 1. Limpeza seletiva de nsX: (para evitar problemas de schema em SP)
            # Somente se houver prefixo nsX nos blocos principais
            xml_str = xml_raw
            if 'ns0:' in xml_str or 'ns1:' in xml_str or 'ns2:' in xml_str:
                xml_str = re.sub(r'<(/?)ns[0-9]+:', r'<\1', xml_str)

            # 2. Corrigir namespaces de forma cirurgica (EVITANDO SignatureMethod)
            # Nao usamos replace generico em '<Signature'
            xml_str = xml_str.replace('<envEvento', f'<envEvento xmlns="{_NS_NFE}" versao="1.00"')
            xml_str = xml_str.replace('<evento', f'<evento xmlns="{_NS_NFE}" versao="1.00"')
            xml_str = xml_str.replace('<detEvento', f'<detEvento versao="1.00"')
            
            # Aplicar namespace na tag Signature EXATA (espaco ou final de tag)
            xml_str = re.sub(r'<Signature(\s|>)', rf'<Signature xmlns="{_NS_DSIG}"\1', xml_str)
            
            # Limpar duplicidades acidentais (caso o pynfe ja tenha colocado)
            xml_str = xml_str.replace(f'xmlns="{_NS_NFE}" xmlns="{_NS_NFE}"', f'xmlns="{_NS_NFE}"')
            xml_str = xml_str.replace('xmlns=""', '').replace('  ', ' ')

            xml_final = xml_declaration + xml_str

        # Logs de Debug
        try:
            temp_name = 'last_enviNFe.xml' if '<enviNFe' in xml_raw else 'last_envEvento.xml'
            dbg_path = os.path.join(os.environ.get('TEMP', os.path.join(os.getcwd(), 'tmp')), temp_name)
            with open(dbg_path, 'w', encoding='utf-8') as f: f.write(xml_final)
        except: pass

        result = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)
        result.encoding = "utf-8"
        
        try:
            resp_path = os.path.join(os.environ.get('TEMP', os.path.join(os.getcwd(), 'tmp')), 'last_sefaz_response.xml')
            with open(resp_path, 'w', encoding='utf-8') as f: f.write(result.text)
        except: pass

        return result
    finally:
        certificado_a1.excluir()
'''

pattern_post = re.compile(r'def _fixed_post\(self, url, xml, timeout=None\):.*?certificado_a1\.excluir\(\)', re.DOTALL)
if pattern_post.search(text):
    text = pattern_post.sub(new_fixed_post.strip(), text)
else:
    print("Nao foi possivel localizar _fixed_post para substituicao.")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Patch aplicado com sucesso.")
