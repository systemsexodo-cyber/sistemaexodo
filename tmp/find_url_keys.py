
from pynfe.processamento.comunicacao import ComunicacaoSefaz
import pynfe.processamento.comunicacao as comunicacao

# Tentar encontrar onde as URLs estao guardadas
print("Checking for URL constants in pynfe.processamento.comunicacao...")
for name in dir(comunicacao):
    if 'URL' in name:
        print(f"{name}: {getattr(comunicacao, name)}")

con = ComunicacaoSefaz(uf='SP', certificado='dummy', certificado_senha='dummy')
print("\nTesting _get_url with different keys for NFCe (modelo 65):")
keys_to_test = ['EVENTOS', 'recepcao_evento', 'recepcao', 'autorizacao', 'RETORNO']
for key in keys_to_test:
    try:
        url = con._get_url(modelo='65', consulta=key)
        print(f"Key '{key}': {url}")
    except Exception as e:
        print(f"Key '{key}': Error -> {e}")
