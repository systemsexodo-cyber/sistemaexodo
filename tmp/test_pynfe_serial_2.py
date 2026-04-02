from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.emitente import Emitente

emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
nota = NotaFiscal(emitente=emitente, modelo=65)

print("\nTestando exportar()...")
try:
    s = SerializacaoXML(nota)
    xml = s.exportar()
    print("exportar() (sem args) funcionou.")
except Exception as e:
    print(f"exportar() (sem args) falhou: {e}")

try:
    s = SerializacaoXML(nota)
    xml = s.exportar(nota)
    print("exportar(nota) (com args) funcionou.")
except Exception as e:
    print(f"exportar(nota) (com args) falhou: {e}")
