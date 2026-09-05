"""
Teste local do XML de cancelamento - verifica se a Signature está no lugar correto
sem precisar enviar à SEFAZ.
"""
import os
from lxml import etree

xml_path = os.path.join(os.environ.get("TEMP", "C:/temp"), "last_cancelamento.xml")

if not os.path.exists(xml_path):
    print("❌ Arquivo last_cancelamento.xml não encontrado no TEMP.")
    exit(1)

with open(xml_path, "r", encoding="utf-8") as f:
    xml_content = f.read()

print("=" * 60)
print("ANÁLISE DO XML DE CANCELAMENTO")
print("=" * 60)

root = etree.fromstring(xml_content.encode("utf-8"))
NS = "http://www.portalfiscal.inf.br/nfe"
NS_DSIG = "http://www.w3.org/2000/09/xmldsig#"

# Estrutura esperada:
# envEvento
#   idLote
#   evento
#     infEvento
#     Signature   ← deve estar AQUI

print(f"\nTag raiz: {root.tag}")

filhos_env = [c.tag.split('}')[-1] for c in root]
print(f"Filhos de envEvento: {filhos_env}")

# Verificar se Signature está no lugar errado
sig_no_env = root.find(f"{{{NS_DSIG}}}Signature")
if sig_no_env is not None:
    print("\n❌ PROBLEMA: <Signature> está como filho de <envEvento> (ERRADO!)")
    print("   O XSD exige que a Signature seja filha de <evento>")
else:
    print("\n✅ Signature NÃO está no nível errado (envEvento)")

# Verificar se Signature está no lugar certo
evento_el = root.find(f"{{{NS}}}evento")
if evento_el is not None:
    filhos_evento = [c.tag.split('}')[-1] for c in evento_el]
    print(f"Filhos de <evento>: {filhos_evento}")
    
    sig_no_evento = evento_el.find(f"{{{NS_DSIG}}}Signature")
    if sig_no_evento is not None:
        print("✅ <Signature> está dentro de <evento> (CORRETO!)")
    else:
        print("❌ <Signature> NÃO encontrada dentro de <evento>")
else:
    print("❌ Elemento <evento> não encontrado!")

# Verificar campos chave
inf_evento = root.find(f".//{{{NS}}}infEvento")
if inf_evento is not None:
    print("\nCampos de infEvento:")
    for child in inf_evento:
        tag = child.tag.split('}')[-1]
        if tag != "detEvento":
            print(f"  <{tag}>: {child.text}")
        else:
            print(f"  <detEvento versao='{child.get('versao')}'>:")
            for sub in child:
                stag = sub.tag.split('}')[-1]
                valor = sub.text[:50] if sub.text else ""
                print(f"    <{stag}>: {valor}")

print("\n" + "=" * 60)
print(f"Id do infEvento: {inf_evento.get('Id') if inf_evento is not None else 'N/A'}")
chave = root.findtext(f".//{{{NS}}}chNFe")
print(f"chNFe (44 dígitos): {chave} (len={len(chave) if chave else 0})")
print("=" * 60)
