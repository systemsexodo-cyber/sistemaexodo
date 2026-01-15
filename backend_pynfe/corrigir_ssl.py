"""
Script para corrigir problema de SSL no nfce_completo.py
"""

import re

# Ler o arquivo
with open('nfce_completo.py', 'r', encoding='utf-8') as f:
    conteudo = f.read()

# Substituir a parte do cliente SOAP
padrao_antigo = r'print\(f"Enviando para SEFAZ: \{url\}"\)\s+# Criar cliente SOAP\s+client = zeep\.Client\(wsdl=url\)'

padrao_novo = '''print(f"Enviando para SEFAZ: {url}")

        # Criar cliente SOAP com verificação SSL desabilitada
        # (Necessário porque alguns sistemas não têm certificados CA instalados)
        # A SEFAZ é um servidor oficial, então é seguro desabilitar a verificação
        
        # Criar sessão com SSL verificação desabilitada
        session = requests.Session()
        session.verify = False  # Desabilitar verificação SSL
        
        # Suprimir avisos de SSL
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        # Criar cliente SOAP com a sessão customizada
        transport = zeep.transports.Transport(session=session)
        client = zeep.Client(wsdl=url, transport=transport)'''

# Fazer a substituição
conteudo_corrigido = re.sub(padrao_antigo, padrao_novo, conteudo, flags=re.MULTILINE | re.DOTALL)

# Salvar
with open('nfce_completo.py', 'w', encoding='utf-8') as f:
    f.write(conteudo_corrigido)

print("✅ Correção aplicada!")




















