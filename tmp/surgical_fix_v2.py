
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# --- 1. IDENTIFICAR BLOCOS ---
start_imports = 0
end_monkeypatch_post = -1

for i, line in enumerate(lines):
    if "ComunicacaoSefaz._post = _fixed_post" in line:
        end_monkeypatch_post = i + 1
        break

if end_monkeypatch_post == -1:
    print("Nao consegui localizar o bloco de monkeypatch antigo.")
    exit(1)

# --- 2. CONSTRUIR O NOVO BLOCO ---
# Vamos manter os imports iniciais (ate a linha 16 aprox)
# E substituir tudo do _fixed_post antigo pelo nosso novo sistema de subclass
new_content = lines[:17] # Mantem os monkeypatches de NotaFiscalProduto

# Adicionar a classe customizada que herda da Original
new_content.append("\nclass ComunicacaoSefaz(OriginalComunicacaoSefaz):\n")
new_content.append("    def _fixed_post(self, url, xml, timeout=None):\n")
new_content.append("        from pynfe.utils import etree as _etree\n")
new_content.append("        from pynfe.entidades.certificado import CertificadoA1 as _CertA1\n")
new_content.append("        import re, os, requests as _requests\n")
new_content.append("        \n")
new_content.append("        certificado_a1 = _CertA1(self.certificate if hasattr(self, 'certificate') else self.certificado)\n")
new_content.append("        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)\n")
new_content.append("        chave_cert = (cert, chave)\n")
new_content.append("        \n")
new_content.append("        try:\n")
new_content.append("            xml_declaration = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>'\n")
new_content.append("            xml_raw = _etree.tostring(xml, encoding=\"unicode\").replace(\"\\n\", \"\").replace(\"\\r\", \"\")\n")
new_content.append("            xml_raw = re.sub(r\">\\s+<\", \"><\", xml_raw)\n")
new_content.append("            \n")
new_content.append("            if \"<enviNFe\" in xml_raw:\n")
new_content.append("                xml_str = re.sub(\"<qrCode>(.*?)</qrCode>\", lambda x: x.group(0).replace(\"&lt;\", \"<\").replace(\"&gt;\", \">\").replace(\"&amp;\", \"\"), xml_raw)\n")
new_content.append("                xml_final = xml_declaration + xml_str\n")
new_content.append("            else:\n")
new_content.append("                xml_str = xml_raw\n")
new_content.append("                if \"ns0:\" in xml_str or \"ns1:\" in xml_str:\n")
new_content.append("                    xml_str = re.sub(r\"<(/?)ns[0-9]+:\", r\"<\\\\1\", xml_str)\n")
new_content.append("                \n")
new_content.append("                for tag in [\"envEvento\", \"evento\"]:\n")
new_content.append("                    if f'<{tag}' in xml_str and 'xmlns=' not in xml_str.split(f'<{tag}')[1].split('>')[0]:\n")
new_content.append("                        xml_str = xml_str.replace(f'<{tag}', f'<{tag} xmlns=\"http://www.portalfiscal.inf.br/nfe\"')\n")
new_content.append("                \n")
new_content.append("                if '<Signature ' in xml_str and 'xmlns=' not in xml_str.split('<Signature ')[1].split('>')[0]:\n")
new_content.append("                    xml_str = xml_str.replace('<Signature ', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" ')\n")
new_content.append("                elif '<Signature>' in xml_str:\n")
new_content.append("                    xml_str = xml_str.replace('<Signature>', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\">')\n")
new_content.append("                \n")
new_content.append("                xml_str = xml_str.replace(' xmlns=\"\"', '')\n")
new_content.append("                xml_final = xml_declaration + xml_str\n")
new_content.append("\n")
new_content.append("            try:\n")
new_content.append("                temp_dir = os.environ.get(\"TEMP\", \"C:/temp\")\n")
new_content.append("                filename = \"last_enviNFe.xml\" if \"<enviNFe\" in xml_raw else \"last_envEvento.xml\"\n")
new_content.append("                with open(os.path.join(temp_dir, filename), \"w\", encoding=\"utf-8\") as f: f.write(xml_final)\n")
new_content.append("            except: pass\n")
new_content.append("\n")
new_content.append("            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)\n")
new_content.append("            res.encoding = \"utf-8\"\n")
new_content.append("            \n")
new_content.append("            try:\n")
new_content.append("                with open(os.path.join(os.environ.get(\"TEMP\", \"C:/temp\"), \"last_sefaz_response.xml\"), \"w\", encoding=\"utf-8\") as f: f.write(res.text)\n")
new_content.append("            except: pass\n")
new_content.append("            \n")
new_content.append("            return res\n")
new_content.append("        finally:\n")
new_content.append("            if os.path.exists(chave): try: os.remove(chave) except: pass\n")
new_content.append("            if os.path.exists(cert): try: os.remove(cert) except: pass\n")
new_content.append("            try: certificado_a1.excluir() except: pass\n")
new_content.append("\n")
new_content.append("    def evento(self, modelo, xml, lote):\n")
new_content.append("        return self._fixed_post(self._url(modelo, 'recepcao_evento'), xml)\n")
new_content.append("\n")
new_content.append("    def envio(self, modelo, xml):\n")
new_content.append("        return self._fixed_post(self._url(modelo, 'autorizacao'), xml)\n")

# Adicionar o resto do arquivo (pulando o bloco antigo de monkeypatch)
new_content.extend(lines[end_monkeypatch_post+1:])

final_text = "".join(new_content)

# Garantir que emitir_nfce_pynfe NAO tente importar ComunicacaoSefaz localmente (que causaria confusao)
final_text = final_text.replace("from pynfe.processamento.comunicacao import ComunicacaoSefaz", "# Usando ComunicacaoSefaz global")

with open(path, 'w', encoding='utf-8') as f:
    f.write(final_text)

print("Reparo cirurgico concluido.")
