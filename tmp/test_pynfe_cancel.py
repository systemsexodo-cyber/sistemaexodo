from pynfe.entidades.evento import EventoCancelarNota
from pynfe.processamento.serializacao import SerializacaoXML
from datetime import datetime
from lxml import etree

def test_cancel():
    e = EventoCancelarNota()
    # Chave original do Charles para teste
    chave = "35260304829400000165650010000001191047801712"
    e.chave = chave
    e.protocolo = "123456789012345"
    e.justificativa = "Cancelamento por erro de emissao ou devolucao de mercadoria"
    e.data_emissao = datetime(2026, 3, 12, 7, 0, 0)
    e.uf = "SP"
    e.cnpj = "04829400000165"
    
    serializador = SerializacaoXML(None, homologacao=True)
    xml_element = serializador.serializar_evento(e)
    
    xml_string = etree.tostring(xml_element, encoding='unicode')
    print("--- XML GERADO ---")
    print(xml_string)
    
    if chave in xml_string:
        print("\n[OK] A chave de acesso está correta no XML.")
    else:
        print("\n[ERRO] A chave de acesso foi alterada no XML!")
        # Tentar achar o que tem no lugar da chave (provavelmente na tag chNFe)
        if 'chNFe' in xml_string:
            import re
            match = re.search(r'<chNFe>(.*?)</chNFe>', xml_string)
            if match:
                print(f"Chave encontrada no XML: {match.group(1)}")

if __name__ == "__main__":
    test_cancel()
