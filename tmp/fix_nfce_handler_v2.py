
import re
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

if not os.path.exists(path):
    print(f"Erro: Arquivo nao encontrado {path}")
    exit(1)

with open(path, 'rb') as f:
    content = f.read()

text = content.decode('utf-8', errors='ignore')

# Definimos o novo bloco _fixed_post definitivo e robusto
new_block = r'''
def _fixed_post(self, url, xml, timeout=None):
    """_post com fix seletivo: mantém emissão original e corrige cancelamento."""
    from pynfe.utils import etree as _etree
    from pynfe.entidades.certificado import CertificadoA1 as _CertA1
    import re
    import os
    import requests as _requests

    # Constantes de Namespace
    _NS_NFE = "http://www.portalfiscal.inf.br/nfe"
    _NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"

    # Salva o certificado para a conexão
    certificado_a1 = _CertA1(self.certificado)
    chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
    chave_cert = (cert, chave)
    
    try:
        xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
        
        # Serialize original do pynfe para detectar o tipo
        xml_raw = _etree.tostring(xml, encoding="unicode").replace("\n", "")

        if '<enviNFe' in xml_raw:
            # --- FLUXO DE EMISSÃO: MÁXIMA FIDELIDADE AO ORIGINAL ---
            xml_str = re.sub(
                "<qrCode>(.*?)</qrCode>",
                lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""),
                xml_raw
            )
            xml_final = xml_declaration + xml_str
        else:
            # --- FLUXO DE EVENTOS (CANCELAMENTO): CORREÇÃO DE SCHEMA ---
            # 1. Limpeza segura de prefixos nsX: (preservando barra de fechamento)
            xml_str = re.sub(r'<(/?)ns[0-9]+:', r'<\1', xml_raw)
            
            # 2. Limpeza de atributos redundantes nas tags de evento
            tags_evento = ['envEvento', 'evento', 'infEvento', 'detEvento', 'Signature']
            for tag in tags_evento:
                pattern = rf'<([a-z0-9]+:)?{tag}(\s+[^>]*?)?>'
                def _clean_attrs(m):
                    attrs = m.group(2) or ""
                    # Remove xmlns e versao para reinserção limpa
                    attrs = re.sub(r'\s+xmlns(:[a-z0-9]+)?=["\'][^"\']*["\']', '', attrs, flags=re.I)
                    attrs = re.sub(r'\s+versao=["\'][^"\']*["\']', '', attrs, flags=re.I)
                    return f'<{tag}{attrs}>'
                xml_str = re.sub(pattern, _clean_attrs, xml_str)

            # 3. Re-inserção padronizada (Schema Compliant)
            xml_str = xml_str.replace('<envEvento', f'<envEvento xmlns="{_NS_NFE}" versao="1.00"')
            if '<evento' in xml_str:
                xml_str = xml_str.replace('<evento', f'<evento xmlns="{_NS_NFE}" versao="1.00"')
            if '<detEvento' in xml_str:
                xml_str = xml_str.replace('<detEvento', '<detEvento versao="1.00"')
            if '<Signature' in xml_str:
                xml_str = xml_str.replace('<Signature', f'<Signature xmlns="{_NS_DSIG}"')

            # 4. Ajuste de idLote (evitar vazio)
            if '<idLote>' in xml_str:
                match_lote = re.search(r'<idLote>(.*?)</idLote>', xml_str)
                if match_lote:
                    val_lote = match_lote.group(1).strip()
                    if not val_lote: val_lote = "1"
                    xml_str = re.sub(r'<idLote>.*?</idLote>', f'<idLote>{val_lote}</idLote>', xml_str)

            xml_str = xml_str.replace(' xmlns=""', '').replace('>>', '>').replace('  ', ' ').strip()
            xml_final = xml_declaration + xml_str

        # Log para diagnóstico
        try:
            temp_name = 'last_enviNFe.xml' if '<enviNFe' in xml_raw else 'last_envEvento.xml'
            dbg_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), temp_name)
            with open(dbg_path, 'w', encoding='utf-8') as f: f.write(xml_final)
        except: pass

        # Envio POST
        result = _requests.post(
            url,
            xml_final,
            headers=self._post_header(),
            cert=chave_cert,
            verify=False,
            timeout=timeout,
        )
        result.encoding = "utf-8"

        # Log de resposta
        try:
            resp_path = os.path.join(os.environ.get('TEMP', 'c:/temp'), 'last_sefaz_response.xml')
            with open(resp_path, 'w', encoding='utf-8') as f: f.write(result.text)
        except: pass

        return result
    finally:
        certificado_a1.excluir()

ComunicacaoSefaz._post = _fixed_post
print("[PATCH] ComunicacaoSefaz._post aplicado (Definitivo / Correcao Namespaces)")
'''

# Procuramos o bloco _fixed_post existente
pattern = re.compile(r'def _fixed_post.*?ComunicacaoSefaz\._post = _fixed_post.*?print\(.*?\)', re.DOTALL)

if not pattern.search(text):
    # Tenta um padrão mais básico se o print variar
    pattern = re.compile(r'def _fixed_post.*?ComunicacaoSefaz\._post = _fixed_post', re.DOTALL)

if pattern.search(text):
    new_text = pattern.sub(lambda m: new_block.strip() + "\n", text)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_text)
    print("Arquivo corrigido com sucesso.")
else:
    print("Erro: Nao foi possivel localizar o bloco _fixed_post para substituição.")
