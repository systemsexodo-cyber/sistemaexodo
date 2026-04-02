import sys
import traceback

try:
    with open('test_out.txt', 'w') as f:
        f.write('START\n')
        
    import xmlschema
    from lxml import etree
    import os
    
    with open('test_out.txt', 'a') as f:
        f.write('Módulos importados\n')
    
    xml_path = r'C:\Users\USER\AppData\Local\Temp\last_enviNFe.xml'
    xml_doc = etree.parse(xml_path)
    env = xml_doc.getroot()
    if env.tag.endswith('Envelope'):
        env = env.xpath('.//*[local-name()="enviNFe"]')[0]
        
    with open('test_out.txt', 'a') as f:
        f.write('Célula XML extraída\n')
        
    schema_path = r'C:\Users\USER\AppData\Roaming\Python\Python312\site-packages\pynfe\utils\schemas\PL_009_V4\enviNFe_v4.00.xsd'
    xsd_doc = etree.parse(schema_path)
    schema = etree.XMLSchema(xsd_doc)
    
    with open('test_out.txt', 'a') as f:
        f.write('XSD Carregado\n')
        
    try:
        schema.assertValid(env)
        with open('test_out.txt', 'a') as f:
            f.write('VALIDO\n')
    except etree.DocumentInvalid as e:
        with open('test_out.txt', 'a') as f:
            f.write('INVALIDO!\n')
            for err in schema.error_log:
                f.write(err.message + '\n')
except Exception as main_e:
    with open('test_out_err.txt', 'w') as f:
        f.write(str(main_e) + '\n')
        f.write(traceback.format_exc())
