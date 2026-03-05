import os
from lxml import etree

xml_path = "logs/empresas/04.829.400/0001-65/lote_enviNFe_manual_20251219_195548.xml"
xsd_path = "schemes/enviNFe_v4.00.xsd"

try:
    with open(xml_path, 'r', encoding='utf-8') as f:
        xml_content = f.read()
    parsed_xml = etree.fromstring(xml_content.encode('utf-8'))
except Exception as e:
    print(f"XML Error: {e}")
    exit(1)

try:
    xmlschema_doc = etree.parse(xsd_path)
    xmlschema = etree.XMLSchema(xmlschema_doc)
except Exception as e:
    print(f"XSD Error: {e}")
    exit(1)

try:
    envi_nfe_block = parsed_xml.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')
    if envi_nfe_block is None:
        print("Could not find enviNFe")
        exit(1)
    xmlschema.assertValid(envi_nfe_block)
    print("XML is valid!")
except etree.DocumentInvalid as e:
    print(f"Schema Validation Error: {e}")
    for error in xmlschema.error_log:
        print(f" - {error.message} (Line: {error.line}, Column: {error.column})")
