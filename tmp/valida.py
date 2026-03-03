import os
import lxml.etree as etree

schema_path = r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\tmp\schemas_tmp\enviNFe_v4.00.xsd'

print('Reading schema:', schema_path)
xsd_doc = etree.parse(schema_path)
schema = etree.XMLSchema(xsd_doc)

xml_file = r'C:\Users\USER\AppData\Local\Temp\last_enviNFe.xml'
with open(xml_file, 'rb') as f:
    xml_doc = etree.fromstring(f.read())
    
# Extract <enviNFe> since that's what the schema expects
env = xml_doc.find('.//enviNFe', namespaces={'': 'http://www.portalfiscal.inf.br/nfe'})
if env is None: env = xml_doc.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')

print('Validating...')
try:
    schema.assertValid(env)
    print('SUCCESS')
except etree.DocumentInvalid as e:
    print('ERROR:', e)
    for err in schema.error_log:
        print(err.message)
