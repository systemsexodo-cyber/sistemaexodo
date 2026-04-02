
from pynfe.processamento.comunicacao import ComunicacaoSefaz

con = ComunicacaoSefaz(uf='SP', certificado='dummy', certificado_senha='dummy')

for mod in ['nfe', 'nfce']:
    print(f"\n--- Testing for modelo: {mod} ---")
    keys_to_test = ['EVENTOS', 'autorizacao', 'consulta', 'status', 'eventos', 'recepcao', 'recepcao_evento']
    for key in keys_to_test:
        try:
            url = con._get_url(modelo=mod, consulta=key)
            print(f"Key '{key}': {url}")
        except Exception as e:
            # print(f"Key '{key}': Error -> {e}")
            pass
