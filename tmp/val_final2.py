import urllib.request, zipfile, io, os
from lxml import etree
import sys

with open(r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\tmp\validation_result.txt', 'w', encoding='utf-8') as out:
    try:
        schema_url = 'http://www.nfe.fazenda.gov.br/portal/exibirArquivo.aspx?conteudo=z12Rdoj/6M8='
        out.write('Downloading schemas from SEFAZ...\n')
        r = urllib.request.urlopen(schema_url, timeout=10)
        z = zipfile.ZipFile(io.BytesIO(r.read()))
        os.makedirs('schemas_sefaz', exist_ok=True)
        z.extractall('schemas_sefaz')

        xsd_path = os.path.join('schemas_sefaz', 'enviNFe_v4.00.xsd')
        out.write(f'Parsing Schema: {xsd_path}\n')

        xsd_doc = etree.parse(xsd_path)
        schema = etree.XMLSchema(xsd_doc)

        xml_path = r'C:\Users\USER\AppData\Local\Temp\last_enviNFe.xml'
        out.write(f'Loading XML: {xml_path}\n')
        xml_doc = etree.parse(xml_path)
        env = xml_doc.getroot()

        if env.tag.endswith('Envelope'):
            env = env.xpath('.//*[local-name()="enviNFe"]')[0]

        out.write('Validating against SEFAZ XSD...\n')
        try:
            schema.assertValid(env)
            out.write('VALIDO 100%\n')
        except etree.DocumentInvalid as e:
            out.write('INVALIDO!\n')
            for err in schema.error_log:
                out.write(str(err.message) + '\n')
    except Exception as e:
        out.write(f'ERROR TYPE: {type(e)}\nERROR: {str(e)}\n')
