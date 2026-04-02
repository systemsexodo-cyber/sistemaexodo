
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# Localizar pontos de corte
start_subclass = -1
end_subclass = -1

for i, line in enumerate(lines):
    if "class ComunicacaoSefaz" in line:
        start_subclass = i
    if start_subclass != -1 and "def evento(self" in line:
        # Encontrar o proximo metodo ou final da classe
        pass
    if "class MockFonteDados" in line:
        end_subclass = i
        break

if start_subclass == -1 or end_subclass == -1:
    print(f"Nao localizei os blocos: start={start_subclass}, end={end_subclass}")
    exit(1)

# Novo bloco limpo
new_subclass = [
    "class ComunicacaoSefaz(OriginalComunicacaoSefaz):\n",
    "    def _fixed_post(self, url, xml, timeout=None):\n",
    "        from pynfe.utils import etree as _etree\n",
    "        from pynfe.entidades.certificado import CertificadoA1 as _CertA1\n",
    "        import re, os, requests as _requests\n",
    "        \n",
    "        certificado_a1 = _CertA1(self.certificate if hasattr(self, 'certificate') else self.certificado)\n",
    "        chave, cert = certificado_a1.separar_arquivo(self.certificado_senha, caminho=True)\n",
    "        chave_cert = (cert, chave)\n",
    "        \n",
    "        try:\n",
    "            xml_declaration = '<?xml version=\"1.0\" encoding=\"UTF-8\"?>'\n",
    "            xml_raw = _etree.tostring(xml, encoding=\"unicode\").replace(\"\\n\", \"\").replace(\"\\r\", \"\")\n",
    "            xml_raw = re.sub(r\">\\s+<\", \"><\", xml_raw)\n",
    "            \n",
    "            if \"<enviNFe\" in xml_raw:\n",
    "                xml_str = re.sub(\"<qrCode>(.*?)</qrCode>\", lambda x: x.group(0).replace(\"&lt;\", \"<\").replace(\"&gt;\", \">\").replace(\"&amp;\", \"\"), xml_raw)\n",
    "                xml_final = xml_declaration + xml_str\n",
    "            else:\n",
    "                xml_str = xml_raw\n",
    "                if \"ns0:\" in xml_str or \"ns1:\" in xml_str:\n",
    "                    xml_str = re.sub(r\"<(/?)ns[0-9]+:\", r\"<\\\\1\", xml_str)\n",
    "                \n",
    "                for tag in [\"envEvento\", \"evento\"]:\n",
    "                    if f'<{tag}' in xml_str and 'xmlns=' not in xml_str.split(f'<{tag}')[1].split('>')[0]:\n",
    "                        xml_str = xml_str.replace(f'<{tag}', f'<{tag} xmlns=\"http://www.portalfiscal.inf.br/nfe\"')\n",
    "                \n",
    "                if '<Signature ' in xml_str and 'xmlns=' not in xml_str.split('<Signature ')[1].split('>')[0]:\n",
    "                    xml_str = xml_str.replace('<Signature ', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" ')\n",
    "                elif '<Signature>' in xml_str:\n",
    "                    xml_str = xml_str.replace('<Signature>', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\">')\n",
    "                \n",
    "                xml_str = xml_str.replace(' xmlns=\"\"', '')\n",
    "                xml_final = xml_declaration + xml_str\n",
    "\n",
    "            try:\n",
    "                temp_dir = os.environ.get(\"TEMP\", \"C:/temp\")\n",
    "                filename = \"last_enviNFe.xml\" if \"<enviNFe\" in xml_raw else \"last_envEvento.xml\"\n",
    "                with open(os.path.join(temp_dir, filename), \"w\", encoding=\"utf-8\") as f: f.write(xml_final)\n",
    "            except: pass\n",
    "\n",
    "            res = _requests.post(url, xml_final, headers=self._post_header(), cert=chave_cert, verify=False, timeout=timeout)\n",
    "            res.encoding = \"utf-8\"\n",
    "            \n",
    "            try:\n",
    "                with open(os.path.join(os.environ.get(\"TEMP\", \"C:/temp\"), \"last_sefaz_response.xml\"), \"w\", encoding=\"utf-8\") as f: f.write(res.text)\n",
    "            except: pass\n",
    "            \n",
    "            return res\n",
    "        finally:\n",
    "            if os.path.exists(chave):\n",
    "                try: os.remove(chave)\n",
    "                except: pass\n",
    "            if os.path.exists(cert):\n",
    "                try: os.remove(cert)\n",
    "                except: pass\n",
    "            try:\n",
    "                certificado_a1.excluir()\n",
    "            except:\n",
    "                pass\n",
    "\n",
    "    def evento(self, modelo, xml, lote):\n",
    "        return self._fixed_post(self._url(modelo, 'recepcao_evento'), xml)\n",
    "\n",
    "    def envio(self, modelo, xml):\n",
    "        return self._fixed_post(self._url(modelo, 'autorizacao'), xml)\n",
    "\n",
    "\n"
]

final_lines = lines[:start_subclass] + new_subclass + lines[end_subclass:]

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(final_lines)

print("Arquivo remontado com sucesso.")
