from lxml import etree

nfe_xml = b'''<NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe Id="NFe35260304829400000165650010725614491434283045" versao="4.00"></infNFe><Signature xmlns="http://www.w3.org/2000/09/xmldsig#"><SignedInfo></SignedInfo></Signature></NFe>'''

nfe = etree.fromstring(nfe_xml)
signature_tag = None

for child in list(nfe):
    tag_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
    if tag_name == 'Signature':
        signature_tag = child
        nfe.remove(child)

info = etree.Element('infNFeSupl')
nfe.insert(1, info)
if signature_tag is not None:
    nfe.append(signature_tag)

print(etree.tostring(nfe).decode('utf-8'))
