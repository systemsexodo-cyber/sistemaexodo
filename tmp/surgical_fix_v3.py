
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# --- 1. ALIAS NO IMPORT (Linha 9) ---
print("Modificando import na linha 9...")
lines[8] = "from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz\n"

# --- 2. DEFINIR O NOVO BLOCO DE CABECALHO (Classe Subclass) ---
subclass_code = """
class ComunicacaoSefaz(OriginalComunicacaoSefaz):
    def _fixed_post(self, url, xml, timeout=None):
        from pynfe.utils import etree as _etree
        from pynfe.entidades.certificado import CertificadoA1 as _CertA1
        import re, os, requests as _requests
        
        certificado_a1 = _CertA1(self.certificate if hasattr(self, 'certificate') else self.certificado)
        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)
        chave_cert = (cert, chave)
        
        try:
            xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
            xml_raw = _etree.tostring(xml, encoding="unicode").replace("\\n", "").replace("\\r", "")
            xml_raw = re.sub(r">\\\\s+<", "><", xml_raw)
            
            if "<enviNFe" in xml_raw:
                xml_str = re.sub("<qrCode>(.*?)</qrCode>", lambda x: x.group(0).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", ""), xml_raw)
                xml_final = xml_declaration + xml_str
            else:
                xml_str = xml_raw
                if "ns0:" in xml_str or "ns1:" in xml_str:
                    xml_str = re.sub(r"<(/?)ns[0-9]+:", r"<\\\\1", xml_str)
                
                for tag in ["envEvento", "evento"]:
                    if f'<{tag}' in xml_str and 'xmlns=' not in xml_str.split(f'<{tag}')[1].split('>')[0]:
                        xml_str = xml_str.replace(f'<{tag}', f'<{tag} xmlns="http://www.portalfiscal.inf.br/nfe"')
                
                if '<Signature ' in xml_str and 'xmlns=' not in xml_str.split('<Signature ')[1].split('>')[0]:
                    xml_str = xml_str.replace('<Signature ', '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#" ')
                elif '<Signature>' in xml_str:
                    xml_str = xml_str.replace('<Signature>', '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">')
                
                xml_str = xml_str.replace(' xmlns=""', '')
                xml_final = xml_declaration + xml_str

            try:
                temp_dir = os.environ.get("TEMP", "C:/temp")
                filename = "last_enviNFe.xml" if "<enviNFe" in xml_raw else "last_envEvento.xml"
                with open(os.path.join(temp_dir, filename), "w", encoding="utf-8") as f: f.write(xml_final)
            except: pass

            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)
            res.encoding = "utf-8"
            
            try:
                with open(os.path.join(os.environ.get("TEMP", "C:/temp"), "last_sefaz_response.xml"), "w", encoding="utf-8") as f: f.write(res.text)
            except: pass
            
            return res
        finally:
            if os.path.exists(chave):
                try: os.remove(chave)
                except: pass
            if os.path.exists(cert):
                try: os.remove(cert)
                except: pass
            try:
                certificado_a1.excluir()
            except:
                pass

    def evento(self, modelo, xml, lote):
        return self._fixed_post(self._url(modelo, 'recepcao_evento'), xml)

    def envio(self, modelo, xml):
        return self._fixed_post(self._url(modelo, 'autorizacao'), xml)
"""

# --- 3. RE-IMPLEMENTAR cancelar_nfce_pynfe ---
new_cancel_func = """def cancelar_nfce_pynfe(req_dict):
    \"\"\"Cancela uma NFC-e usando lxml para garantir conformidade de Schema.\"\"\"
    from lxml import etree
    from lxml.builder import ElementMaker
    from datetime import datetime
    import base64, tempfile, os, re, traceback

    try:
        empresa_data = req_dict.get("empresa", {})
        chave_acesso = req_dict.get("chave_acesso")
        justificativa = req_dict.get("justificativa", "Cancelamento por erro de emissao ou devolucao")
        protocolo = req_dict.get("protocolo")
        
        if not chave_acesso or not empresa_data.get("certificado_base64"):
            return {"success": False, "error": "Chave de acesso ou certificado ausentes.", "mensagem": "Dados insuficientes"}

        cert_data = base64.b64decode(empresa_data.get("certificado_base64"))
        senha_cert = empresa_data.get("senha_certificado")
        uf = empresa_data.get("uf", "SP")
        is_homolog = (empresa_data.get("ambiente") == 2)
        tp_amb = "2" if is_homolog else "1"
        cnpj = re.sub(r"[^0-9]", "", empresa_data.get("cnpj", ""))
        dh_evento = datetime.now().strftime("%Y-%m-%dT%H:%M:%S-03:00")

        # Criar XML usando ElementMaker para garantir ordem e namespaces
        E = ElementMaker(namespace="http://www.portalfiscal.inf.br/nfe", nsmap={None: "http://www.portalfiscal.inf.br/nfe"})
        
        det_evento = E.detEvento(
            E.descEvento("Cancelamento"),
            E.nProt(str(protocolo)),
            E.xJust(justificativa),
            versao="1.00"
        )
        
        inf_evento = E.infEvento(
            E.cOrgao("35"),
            E.tpAmb(tp_amb),
            E.CNPJ(cnpj),
            E.chNFe(chave_acesso),
            E.dhEvento(dh_evento),
            E.tpEvento("110111"),
            E.nSeqEvento("1"),
            E.verEvento("1.00"),
            det_evento,
            Id=f"ID110111{chave_acesso}01"
        )
        
        evento = E.evento(inf_evento, versao="1.00")
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pfx") as tmp:
            tmp.write(cert_data)
            caminho_cert = tmp.name
            
        try:
            con = ComunicacaoSefaz(uf=uf, certificado=caminho_cert, certificado_senha=senha_cert, homologacao=is_homolog)
            resp = con.evento("nfce", evento, 1)
            
            r_text = resp.text if resp else ""
            if not r_text:
                return {"success": False, "error": "Sem resposta da SEFAZ", "mensagem": "Conexao interrompida"}

            cstat = re.search(r"<cStat>(.*?)</cStat>", r_text)
            cstat = cstat.group(1) if cstat else ""
            xmotivo = re.search(r"<xMotivo>(.*?)</xMotivo>", r_text)
            xmotivo = xmotivo.group(1) if xmotivo else "Erro desconhecido na resposta"
            
            success = cstat in ["135", "128", "101", "155"]
            return {
                "success": success, 
                "cStat": cstat, 
                "xMotivo": xmotivo, 
                "mensagem": xmotivo,
                "error": None if success else xmotivo,
                "data": {"cStat": cstat, "xMotivo": xmotivo}
            }
        finally:
            if os.path.exists(caminho_cert): os.remove(caminho_cert)
    except Exception as e:
        return {"success": False, "error": str(e), "mensagem": f"Erro interno: {str(e)}", "traceback": traceback.format_exc()}
"""

# --- 4. REALIZAR SUBSTITUICOES ---

# Inserir a classe logo apos o import aliased
lines.insert(9, subclass_code + "\n")

# Localizar o inicio da funcao de cancelamento (ajustado por causa da insercao anterior)
text = "".join(lines)
text = re.sub(r'def cancelar_nfce_pynfe\(req_dict\):.*?(?=\n\ndef|\Z)', new_cancel_func, text, flags=re.DOTALL)

# Remover qualquer import local de ComunicacaoSefaz dentro das funcoes para usar a nossa global
text = text.replace("    from pynfe.processamento.comunicacao import ComunicacaoSefaz", "    # Usando ComunicacaoSefaz global")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Fix cirurgico aplicado.")
