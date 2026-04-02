
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

if not os.path.exists(path):
    print(f"Erro: Arquivo nao encontrado {path}")
    exit(1)

with open(path, 'rb') as f:
    content = f.read()

text = content.decode('utf-8', errors='ignore')

# --- ETAPA 1: Limpeza Profunda ---
print("Limpando file...")
# Reduz múltiplas quebras de linha para no máximo 2
text = re.sub(r'\n\s*\n\s*\n+', '\n\n', text)
# Remove espaços no fim das linhas
text = re.sub(r'[ \t]+\n', '\n', text)

# --- ETAPA 2: Fix do cancelamento ---
# Vamos definir a função cancelar_nfce_pynfe de forma limpa e sem o bug da assinatura dupla
new_cancelar_func = r'''
def cancelar_nfce_pynfe(req_dict):
    """Cancela uma NFC-e de forma robusta e com tratamento de erro aprimorado."""
    from pynfe.entidades.certificado import CertificadoA1
    from pynfe.processamento.assinatura import AssinaturaA1
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
            """Parser Ultra-Robusto com Regex Fallback."""
            if not xml_text: return None
            try:
                cStat, xMotivo = "", ""
                # Regex (mais seguro contra schemas zumbis)
                m_c = re.search(r'<cStat>(.*?)</cStat>', xml_text)
                if m_c: cStat = m_c.group(1).strip()
                m_x = re.search(r'<xMotivo>(.*?)</xMotivo>', xml_text)
                if m_x: xMotivo = m_x.group(1).strip()
                
                # Sucessos: 135 (Evento Registrado), 128 (Lote), 101 (Canc Homologado)
                if cStat:
                    return {
                        'success': cStat in ['135', '128', '101', '155'],
                        'data': {'cStat': cStat, 'xMotivo': xMotivo},
                        'cStat': cStat
                    }
                # Fallback etree
                root = etree.fromstring(xml_text.encode('utf-8'))
                ns = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                c = root.xpath('//ns:cStat/text()', namespaces=ns) or root.xpath('//cStat/text()')
                if c:
                    cStat = c[0].strip()
                    m = root.xpath('//ns:xMotivo/text()', namespaces=ns) or root.xpath('//xMotivo/text()')
                    xMotivo = m[0].strip() if m else "Sem motivo"
                    return {'success': cStat in ['135', '128', '101'], 'data': {'cStat': cStat, 'xMotivo': xMotivo}, 'cStat': cStat}
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
            # 1. Montagem do XML de Evento
            dh_evento = datetime.now().strftime('%Y-%m-%dT%H:%M:%S-03:00')
            id_evento = f"ID110111{chave_acesso}01"
            
            # XML Estrutural
            xml_str = f"""<evento xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.00">
                <infEvento Id="{id_evento}">
                    <cOrgao>{uf_to_cod(uf)}</cOrgao>
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
            assinador = AssinaturaA1(caminho_cert, senha_cert)
            # ASSINAR APENAS UMA VEZ
            xml_assinado = assinador.assinar(root)
            
            # 2. Envio
            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homologacao)
            resp = con.evento(xml_assinado, 1) # 1 = Cancelamento
            
            res = parse_sefaz_resp(resp.text if resp else "")
            
            # Retrocompatibilidade de erro "Diverge" ou "Rejeição 252"
            if not res or res.get('cStat') in ['252', '494', '225']:
                log_message("Tentando ambiente alternativo (Producao/Homologacao)...")
                is_homolog_retry = not is_homologacao
                con_retry = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homolog_retry)
                
                # AJUSTA AMBIENTE ANTES DE RE-ASSINAR (Para nao ter 2 assinaturas)
                ns_nfe = "http://www.portalfiscal.inf.br/nfe"
                for tp in root.xpath('//ns:tpAmb', namespaces={'ns': ns_nfe}):
                    tp.text = '2' if is_homolog_retry else '1'
                
                # Assinar novamente o root modificado (ou criar novo)
                xml_retry = assinador.assinar(root)
                resp_retry = con_retry.evento(xml_retry, 1)
                res_retry = parse_sefaz_resp(resp_retry.text if resp_retry else "")
                if res_retry: res = res_retry

            return res or {'success': False, 'error': 'Resposta malformada da SEFAZ', 'details': resp.text[:200] if resp else "Sem resposta"}

        finally:
            if os.path.exists(caminho_cert): os.remove(caminho_cert)

    except Exception as e:
        import traceback
        return {'success': False, 'error': f'Erro interno: {str(e)}', 'traceback': traceback.format_exc()}
'''

# Substituição do bloco cancelar_nfce_pynfe
print("Substituindo cancelar_nfce_pynfe...")
pattern = re.compile(r'def cancelar_nfce_pynfe\(req_dict\):.*?finally:.*?if os\.path\.exists\(caminho_cert\):.*?except Exception as e:.*?return \{.*?\}', re.DOTALL)

if pattern.search(text):
    text = pattern.sub(new_cancelar_func.strip(), text)
    print("Sucesso!")
else:
    # Se falhou, tenta um padrão mais simples de substituição (procure por def e até onde o script termina)
    print("Tentando padrão alternativo...")
    text = re.sub(r'def cancelar_nfce_pynfe\(req_dict\):.*', new_cancelar_func.strip(), text, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Tudo pronto.")
