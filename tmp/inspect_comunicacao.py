
from pynfe.processamento.comunicacao import ComunicacaoSefaz
import inspect

con = ComunicacaoSefaz(uf='SP')
print("Methods in ComunicacaoSefaz:")
for name, member in inspect.getmembers(con):
    if not name.startswith('__'):
        print(f"{name}: {member}")
