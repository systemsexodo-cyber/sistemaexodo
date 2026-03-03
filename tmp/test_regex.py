import re
xml_str = '<enviNFe version="4.00"><NFe xmlns="http://www.portalfiscal.inf.br/nfe"><infNFe>test</infNFe></NFe></enviNFe>'
tag = 'NFe'
# Regex replaces "<tag xmlns=..." with "<tag"
# But it doesn't match the final ">"
result = re.sub(rf'<{tag}\s+xmlns=["\'][^"\']*["\']', f'<{tag}', xml_str)
print(f"Result: {result}")
