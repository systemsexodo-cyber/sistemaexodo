
from pynfe.processamento.comunicacao import ComunicacaoSefaz
import inspect

print("Methods in ComunicacaoSefaz class:")
for name, member in inspect.getmembers(ComunicacaoSefaz):
    if not name.startswith('__'):
        print(f"{name}: {member}")
