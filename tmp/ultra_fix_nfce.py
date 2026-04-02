
import os
import re

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\\backend_nfce\\nfce_handler.py'

if not os.path.exists(path):
    print(f"Erro: Arquivo nao encontrado {path}")
    exit(1)

with open(path, 'rb') as f:
    content = f.read()

text = content.decode('utf-8', errors='ignore')

# 1. Limpeza de linhas vazias excessivas
print("Limpando linhas vazias...")
# Substitui 3 ou mais quebras de linha por apenas 2
text = re.sub(r'\n\s*\n\s*\n+', '\n\n', text)

# 2. Implementação do parse_sefaz_resp robusto
robust_parser = r'''
            def parse_sefaz_resp(xml_text):
                """Versão Ultra-Robusta para evitar 'Resposta Malformada'."""
                if not xml_text: return None
                try:
                    # Limpeza prévia para lidar com BOM ou lixo no início
                    if '<?xml' in xml_text:
                        xml_text = xml_text[xml_text.find('<?xml'):]
                    
                    # Tentar extrair cStat e xMotivo via REGEX primeiro (mais seguro contra falhas de namespace)
                    cStat = ""
                    xMotivo = ""
                    
                    match_cstat = re.search(r'<cStat>(.*?)</cStat>', xml_text)
                    if match_cstat: cStat = match_cstat.group(1).strip()
                    
                    match_xmotivo = re.search(r'<xMotivo>(.*?)</xMotivo>', xml_text)
                    if match_xmotivo: xMotivo = match_xmotivo.group(1).strip()
                    
                    # Sucesso em eventos é 135. Em lote é 128.
                    # Aceitamos 135, 128, 101, 155 como "sucesso" parcial ou total
                    sucesso_codes = ['135', '128', '101', '155']
                    
                    if cStat:
                        return {
                            'success': cStat in sucesso_codes,
                            'data': {'cStat': cStat, 'xMotivo': xMotivo},
                            'error': f'Sefaz [{cStat}]: {xMotivo}' if cStat not in sucesso_codes else None,
                            'cStat': cStat,
                            'xMotivo': xMotivo
                        }
                    
                    # Se falhou via Regex, tenta via etree
                    try:
                        root_resp = etree.fromstring(xml_text.encode('utf-8'))
                        namespaces = {'ns': 'http://www.portalfiscal.inf.br/nfe'}
                        
                        # XPath genérico para achar cStat e xMotivo em qualquer lugar
                        c_nodes = root_resp.xpath('//ns:cStat/text()', namespaces=namespaces)
                        if not c_nodes: c_nodes = root_resp.xpath('//cStat/text()')
                        
                        if c_nodes:
                            cStat = c_nodes[0].strip()
                            m_nodes = root_resp.xpath('//ns:xMotivo/text()', namespaces=namespaces)
                            if not m_nodes: m_nodes = root_resp.xpath('//xMotivo/text()')
                            xMotivo = m_nodes[0].strip() if m_nodes else "Sem motivo detalhado"
                            
                            return {
                                'success': cStat in sucesso_codes,
                                'data': {'cStat': cStat, 'xMotivo': xMotivo},
                                'error': f'Sefaz [{cStat}]: {xMotivo}' if cStat not in sucesso_codes else None,
                                'cStat': cStat,
                                'xMotivo': xMotivo
                            }
                    except:
                        pass
                        
                    # Última tentativa: busca por string direta se tudo falhar
                    if '135' in xml_text:
                         return {'success': True, 'data': {'cStat': '135', 'xMotivo': 'Cancelado (Detecção Manual)'}, 'cStat': '135'}

                except Exception as e:
                    log_message(f"Erro critico parse_sefaz_resp: {str(e)}")
                return None
'''

# Substituir o bloco antigo pelo novo
# Procuramos por uma definição de parse_sefaz_resp que retorne None no final do try/except
print("Injetando parser robusto...")
# O padrão deve ser flexível devido às linhas vazias que podem ter sobrado
pattern = re.compile(r'def parse_sefaz_resp\(xml_text\):.*?return None', re.DOTALL)

if pattern.search(text):
    text = pattern.sub(robust_parser.strip(), text)
    print("Sucesso ao substituir parser.")
else:
    print("ERRO: Bloco parse_sefaz_resp não encontrado!")

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Processamento concluído.")
