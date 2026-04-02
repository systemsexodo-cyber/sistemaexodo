
from pynfe.processamento.comunicacao import ComunicacaoSefaz
import inspect

lines = inspect.getsourcelines(ComunicacaoSefaz.autorizacao)[0]
for i, line in enumerate(lines[:20]): 
    print(f"{i+1}: {line}", end="")
