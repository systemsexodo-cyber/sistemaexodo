"""
Diagnóstico do XML NFC-e - analisa o enviNFe e verifica conformidade com schema 4.00
"""
import sys, os, re
from lxml import etree

# Ler o enviNFe completo (com SOAP)
xml_file = r'C:/Users/USER/AppData/Local/Temp/last_enviNFe.xml'
with open(xml_file, 'rb') as f:
    content = f.read()

ns_nfe = 'http://www.portalfiscal.inf.br/nfe'
soap_ns = 'http://www.w3.org/2003/05/soap-envelope'

root = etree.fromstring(content)
body = root.find(f'{{{soap_ns}}}Body')
# SOAP body > nfeDadosMsg > enviNFe
dados_msg = body[0]
envi_nfe_elem = dados_msg[0]  # enviNFe
nfe_elem = envi_nfe_elem.find(f'{{{ns_nfe}}}NFe')
inf_nfe = nfe_elem.find(f'{{{ns_nfe}}}infNFe')
inf_supl = nfe_elem.find(f'{{{ns_nfe}}}infNFeSupl')

print("="*60)
print("DIAGNÓSTICO XML NFC-e 4.00")
print("="*60)

# 1. Verificar infNFeSupl
print("\n[1] infNFeSupl:")
if inf_supl is not None:
    qr = inf_supl.find(f'{{{ns_nfe}}}qrCode')
    urlChave = inf_supl.find(f'{{{ns_nfe}}}urlChave')
    print(f"  qrCode: {'OK' if qr is not None else 'FALTANDO'}")
    if qr is not None:
        print(f"  qrCode text[:80]: {str(qr.text)[:80]}")
    print(f"  urlChave: {'OK' if urlChave is not None else 'FALTANDO'}")
    # Ordem dentro de NFe
    nfe_children = list(nfe_elem)
    for i, c in enumerate(nfe_children):
        print(f"  Posição [{i}] NFe -> {c.tag.split('}')[-1]}")
else:
    print("  ERRO: infNFeSupl AUSENTE!")

# 2. Verificar campos de valores numéricos
print("\n[2] Verificação de campos numéricos (xsd:decimal com limites):")

def check_decimal(tag_name, text, max_dec=2, max_int=13):
    """Verifica se o valor decimal está dentro dos limites do schema"""
    if text is None:
        return f"  {tag_name}: NULL"
    parts = text.split('.')
    int_part = parts[0].lstrip('-')
    dec_part = parts[1] if len(parts) > 1 else ''
    ok = len(dec_part) <= max_dec and len(int_part) <= max_int
    return f"  {tag_name}: '{text}' ({'OK' if ok else 'ERRO - excede limite'})"

ide = inf_nfe.find(f'{{{ns_nfe}}}ide')
print(f"  cUF: {ide.find(f'{{{ns_nfe}}}cUF').text}")
print(f"  mod: {ide.find(f'{{{ns_nfe}}}mod').text}")
print(f"  tpImp: {ide.find(f'{{{ns_nfe}}}tpImp').text}")
print(f"  tpEmis: {ide.find(f'{{{ns_nfe}}}tpEmis').text}")
print(f"  indPres: {ide.find(f'{{{ns_nfe}}}indPres').text}")

# 3. Verificar itens
print("\n[3] Itens (det):")
dets = inf_nfe.findall(f'{{{ns_nfe}}}det')
for det in dets:
    nItem = det.get('nItem')
    prod = det.find(f'{{{ns_nfe}}}prod')
    print(f"  Item {nItem}:")
    
    # Campos obrigatórios
    for tag in ['cProd', 'cEAN', 'xProd', 'NCM', 'CFOP', 'uCom', 'qCom', 'vUnCom', 'vProd', 'cEANTrib', 'uTrib', 'qTrib', 'vUnTrib', 'indTot']:
        el = prod.find(f'{{{ns_nfe}}}{tag}')
        if el is not None:
            val = el.text
            # Verificar comprimento de campos decimais
            if tag in ['qCom', 'qTrib']:
                # qCom = 15 dígitos total, 4 decimais max
                parts = val.split('.') if val else ['']
                dec = parts[1] if len(parts)>1 else ''
                ok = "OK" if len(dec) <= 4 else f"ERRO: {len(dec)} decimais (max 4)"
                print(f"    {tag}: '{val}' - {ok}")
            elif tag in ['vUnCom', 'vUnTrib']:
                # vUnCom = 21 dígitos, 10 decimais
                parts = val.split('.') if val else ['']
                dec = parts[1] if len(parts)>1 else ''
                ok = "OK" if len(dec) <= 10 else f"ERRO: {len(dec)} decimais (max 10)"
                print(f"    {tag}: '{val}' - {ok}")
            elif tag in ['vProd']:
                # vProd = 15 dígitos total, 2 decimais
                parts = val.split('.') if val else ['']
                dec = parts[1] if len(parts)>1 else ''
                ok = "OK" if len(dec) <= 2 else f"ERRO: {len(dec)} decimais (max 2)"
                print(f"    {tag}: '{val}' - {ok}")
            else:
                print(f"    {tag}: '{val}'")
        else:
            print(f"    {tag}: AUSENTE")
    
    # Verificar impostos
    imposto = det.find(f'{{{ns_nfe}}}imposto')
    if imposto is not None:
        print("    imposto: OK")
        for sub in imposto:
            print(f"      {sub.tag.split('}')[-1]}: OK")
    else:
        print("    imposto: AUSENTE!")

# 4. Verificar total
print("\n[4] ICMSTot:")
total = inf_nfe.find(f'{{{ns_nfe}}}total')
icms_tot = total.find(f'{{{ns_nfe}}}ICMSTot') if total is not None else None
if icms_tot is not None:
    campos_obrig = ['vBC', 'vICMS', 'vICMSDeson', 'vFCP', 'vBCST', 'vST', 'vFCPST', 'vFCPSTRet', 'vProd', 'vFrete', 'vSeg', 'vDesc', 'vII', 'vIPI', 'vIPIDevol', 'vPIS', 'vCOFINS', 'vOutro', 'vNF']
    for campo in campos_obrig:
        el = icms_tot.find(f'{{{ns_nfe}}}{campo}')
        print(f"  {campo}: {'OK: ' + el.text if el is not None else 'AUSENTE!'}")

# 5. Verificar transp
print("\n[5] transp:")
transp = inf_nfe.find(f'{{{ns_nfe}}}transp')
if transp is not None:
    mod_frete = transp.find(f'{{{ns_nfe}}}modFrete')
    print(f"  modFrete: {mod_frete.text if mod_frete is not None else 'AUSENTE!'}")
else:
    print("  AUSENTE!")

# 6. Verificar pag
print("\n[6] pag:")
pag = inf_nfe.find(f'{{{ns_nfe}}}pag')
if pag is not None:
    for child in pag:
        tag = child.tag.split('}')[-1]
        if tag == 'detPag':
            print(f"  detPag:")
            for sc in child:
                print(f"    {sc.tag.split('}')[-1]}: {sc.text}")
        else:
            print(f"  {tag}: {child.text}")
else:
    print("  AUSENTE!")

# 7. Verificar xNome (limite de 60 chars, só chars permitidos)
print("\n[7] xNome emitente:")
emit = inf_nfe.find(f'{{{ns_nfe}}}emit')
xnome = emit.find(f'{{{ns_nfe}}}xNome')
if xnome is not None:
    val = xnome.text or ''
    print(f"  Valor: '{val}'")
    print(f"  Comprimento: {len(val)} chars (max 60)")
    # Verificar caracteres inválidos para NF-e (só permite: [a-zA-Z0-9 .,;:/?~!@#$%&*()-_+=|\\[{}/^`<>\"])
    chars_invalidos = re.findall(r'[^\w\s\.,;:/?~!@#\$%&\*\(\)\-_\+=\|\\\[\{\}/\^`<>\'\"áéíóúãõâêîôûàèìòùüçÁÉÍÓÚÃÕÂÊÎÔÛÀÈÌÒÙÜÇ]', val)
    if chars_invalidos:
        print(f"  CHARS INVÁLIDOS: {chars_invalidos}")
    else:
        print("  Caracteres: OK")

print("\n[8] Ordem geral dos elementos infNFe (sequência NFC-e 4.00):")
ordem_esperada = ['ide', 'emit', 'dest', 'det', 'total', 'transp', 'cobr', 'pag', 'infAdic', 'exporta', 'compra', 'cana', 'infRespTec']
tags_presentes = [c.tag.split('}')[-1] for c in inf_nfe]
print(f"  Tags no XML: {tags_presentes}")
print(f"  Expected ok? Verificar se segue a sequência do schema")

print("\n"+"="*60)
print("FIM DO DIAGNÓSTICO")
print("="*60)
