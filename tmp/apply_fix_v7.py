
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

# 1. Ler o arquivo completo
with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# 2. Definir o novo bloco da subclass ComunicacaoSefaz
new_subclass_block = [
    "class ComunicacaoSefaz(OriginalComunicacaoSefaz):\n",
    "    def _post(self, url, xml, timeout=None):\n",
    "        \"\"\"Override do metodo _post para garantir a limpeza do XML e namespaces corretos em SP.\"\"\"\n",
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
    "            if \"<qrCode\" in xml_raw:\n",
    "                xml_raw = re.sub(\"<qrCode>(.*?)</qrCode>\", \n",
    "                                lambda x: x.group(0).replace(\"&lt;\", \"<\").replace(\"&gt;\", \">\").replace(\"&amp;\", \"\"), \n",
    "                                xml_raw)\n",
    "            \n",
    "            if \"ns0:\" in xml_raw or \"ns1:\" in xml_raw:\n",
    "                xml_raw = re.sub(r\"<(/?)ns[0-9]+:\", r\"<\\\\1\", xml_raw)\n",
    "            \n",
    "            for tag in [\"envEvento\", \"evento\", \"infEvento\"]:\n",
    "                if f'<{tag}' in xml_raw and 'xmlns=' not in xml_raw.split(f'<{tag}')[1].split('>')[0]:\n",
    "                    xml_raw = xml_raw.replace(f'<{tag}', f'<{tag} xmlns=\"http://www.portalfiscal.inf.br/nfe\"')\n",
    "            \n",
    "            if '<Signature ' in xml_raw and 'xmlns=' not in xml_raw.split('<Signature ')[1].split('>')[0]:\n",
    "                xml_raw = xml_raw.replace('<Signature ', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" ')\n",
    "            elif '<Signature>' in xml_raw:\n",
    "                xml_raw = xml_raw.replace('<Signature>', '<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\">')\n",
    "            \n",
    "            xml_raw = xml_raw.replace(' xmlns=\"\"', '')\n",
    "            xml_final = xml_declaration + xml_raw\n",
    "\n",
    "            try:\n",
    "                temp_dir = os.environ.get(\"TEMP\", \"C:/temp\")\n",
    "                with open(os.path.join(temp_dir, \"last_outgoing_soap.xml\"), \"w\", encoding=\"utf-8\") as f: f.write(xml_final)\n",
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
    "            if os.path.exists(chave): try: os.remove(chave) except: pass\n",
    "            if os.path.exists(cert): try: os.remove(cert) except: pass\n",
    "            try: certificado_a1.excluir() except: pass\n",
    "\n",
    "    def evento(self, modelo, xml, lote):\n",
    "        return self._post(self._get_url(modelo, 'EVENTOS'), xml)\n",
    "\n",
    "    def envio(self, modelo, xml):\n",
    "        return self._post(self._get_url(modelo, 'AUTORIZACAO'), xml)\n",
    "\n"
]

# 3. Encontrar onde comeca a ComunicacaoSefaz e onde termina o bloco _fixed_post
start = -1
end = -1
for i, line in enumerate(lines):
    if "class ComunicacaoSefaz(OriginalComunicacaoSefaz):" in line:
        start = i
    if "return self._fixed_post(self._get_url(modelo, 'AUTORIZACAO'), xml)" in line:
        end = i + 1
        break

if start != -1 and end != -1:
    lines = lines[:start] + new_subclass_block + lines[end:]
    
    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Correcao v7 aplicada.")
else:
    print(f"Nao foi possivel localizar o bloco: start={start}, end={end}")
    exit(1)
