
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

# Localizar a linha 68 (indice 67) e corrigir indentacao do finally e seus filhos
print(f"Corrigindo indentacao a partir da linha 68...")

# Reconstruir o bloco try/finally com indentacao correta (8 espacos para o try, 8 para o finally)
new_block = """        try:
            xml_declaration = '<?xml version="1.0" encoding="UTF-8"?>'
            xml_raw = _etree.tostring(xml, encoding="unicode").replace("\\n", "").replace("\\r", "")
            xml_raw = re.sub(r">\\s+<", "><", xml_raw)
            
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
                pass\n"""

with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Substituir todo o bloco try...finally
text = re.sub(r'        try:.*?pass\s+(?=    def evento)', new_block, text, flags=re.DOTALL)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Indentaﾃｧﾃ｣o corrigida.")
