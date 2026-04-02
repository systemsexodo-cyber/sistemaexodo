
import inspect
from pynfe.processamento.comunicacao import ComunicacaoSefaz

sig = inspect.signature(ComunicacaoSefaz.evento)
print(f"Signature: {sig}")
