import urllib.request, zipfile, io, os
from lxml import etree

schema_url = 'http://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=z12Rdoj/6M8='

print('Downloading schemas from SEFAZ...')
r = urllib.request.urlopen(schema_url, timeout=10)
z = zipfile.ZipFile(io.BytesIO(r.read()))
os.makedirs('schemas_sefaz', exist_ok=True)
z.extractall('schemas_sefaz')

xsd_path = os.path.join('schemas_sefaz', 'enviNFe_v4.00.xsd')
print('Parsing Schema:', xsd_path)

xsd_doc = etree.parse(xsd_path)
schema = etree.XMLSchema(xsd_doc)

xml_path = r'C:\Users\USER\AppData\Local\Temp\last_enviNFe.xml'
print('Loading XML:', xml_path)
xml_doc = etree.parse(xml_path)
env = xml_doc.getroot()

if env.tag.endswith('Envelope'):
    env = env.xpath('.//*[local-name()="enviNFe"]')[0]

print('Validating against SEFAZ XSD...')
try:
    schema.assertValid(env)
    print('VALIDO 100%')
except etree.DocumentInvalid as e:
    print('INVALIDO!')
    for err in schema.error_log:
        print(err.message)
