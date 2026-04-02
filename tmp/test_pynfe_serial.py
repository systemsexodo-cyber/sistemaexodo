try:
    from pynfe.processamento.serializacao import SerializacaoXML
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.entidades.emitente import Emitente
    
    emitente = Emitente(cnpj='00000000000000', razao_social='Teste')
    nota = NotaFiscal(emitente=emitente, modelo=65)
    
    print("Testando instanciacao de SerializacaoXML()...")
    try:
        s = SerializacaoXML()
        print("SerializacaoXML() funcionou sem argumentos.")
    except Exception as e:
        print(f"SerializacaoXML() falhou: {e}")
        
    print("\nTestando instanciacao de SerializacaoXML(nota)...")
    try:
        s = SerializacaoXML(nota)
        print("SerializacaoXML(nota) funcionou.")
    except Exception as e:
        print(f"SerializacaoXML(nota) falhou: {e}")

except Exception as global_e:
    print(f"Erro global: {global_e}")
