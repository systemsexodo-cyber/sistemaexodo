try:
    from pynfe.processamento.serializacao import SerializacaoXML
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.entidades.emitente import Emitente
    
    emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
    nota = NotaFiscal(emitente=emitente, modelo=65)
    
    s = SerializacaoXML(nota)
    print("Metodos de SerializacaoXML(nota):")
    print(dir(s))
    
    # Tentar exportar
    print("\nTentando s.exportar(nota):")
    try:
        xml = s.exportar(nota)
        print("Sucesso!")
    except Exception as e:
        print(f"Falha: {e}")

except Exception as e:
    print(f"Erro: {e}")
