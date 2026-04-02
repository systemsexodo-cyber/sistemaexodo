
from pynfe.processamento.comunicacao import ComunicacaoSefaz
import inspect

lines = inspect.getsourcelines(ComunicacaoSefaz.autorizacao)[0]
for i, line in enumerate(lines[:50]): # First 50 lines should show the URL logic
    print(f"{i+1}: {line}", end="")
