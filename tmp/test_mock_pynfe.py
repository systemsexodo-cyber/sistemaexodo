from pynfe.processamento.serializacao import SerializacaoXML
from pynfe.entidades.notafiscal import NotaFiscal
from pynfe.entidades.emitente import Emitente

class MockFonteDados:
    def __init__(self, nota):
        self.nota = nota
    def obter_lista(self, _classe=None, **kwargs):
        return [self.nota]
    def limpar_dados(self):
        pass

emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
nota = NotaFiscal(emitente=emitente, modelo=65)

print("\nTestando MockFonteDados com SerializacaoXML...")
try:
    mock = MockFonteDados(nota)
    s = SerializacaoXML(mock)
    print("Instanciacao funcionou.")
    xml = s.exportar(retorna_string=True)
    print("exportar() funcionou!")
    print(f"XML (primeiros 100 chars): {xml[:100]}")
except Exception as e:
    print(f"Falha: {e}")
