import os
import lxml.etree as etree

out = open(r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\tmp\valout.txt', 'w')

try:
    schema_path = r'c:\Users\USER\AppData\Roaming\Python\Python312\site-packages\pynfe\utils\schemas\PL_009_V4\enviNFe_v4.00.xsd'
    if not os.path.exists(schema_path):
        out.write('NO SCHEMA\\n')
    else:
        out.write(f'SCHEMA OK: {schema_path}\\n')
        xsd_doc = etree.parse(schema_path)
        schema = etree.XMLSchema(xsd_doc)

        xml_file = r'C:\Users\USER\AppData\Local\Temp\last_enviNFe.xml'
        with open(xml_file, 'rb') as f:
            xml_doc = etree.fromstring(f.read())
            
        env = xml_doc.find('.//enviNFe', namespaces={'': 'http://www.portalfiscal.inf.br/nfe'})
        if env is None: env = xml_doc.find('.//{http://www.portalfiscal.inf.br/nfe}enviNFe')

        out.write('Validating...\\n')
        try:
            schema.assertValid(env)
            out.write('SUCCESS\\n')
        except etree.DocumentInvalid as e:
            out.write(f'ERROR: {e}\\n')
            for err in schema.error_log:
                out.write(f'{err.message}\\n')
except Exception as ex:
    out.write(f'EXCEPTION: {ex}\\n')
finally:
    out.close()
