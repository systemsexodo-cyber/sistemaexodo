import sys
import os

# Add backend directory to path
sys.path.append(r'c:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_pynfe')

try:
    print("Testing imports...")
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    print("[OK] ComunicacaoSefaz imported")
    from pynfe.entidades.evento import EventoCancelarNota
    print("[OK] EventoCancelarNota imported")
    from pynfe.processamento.serializacao import SerializacaoXML
    print("[OK] SerializacaoXML imported")
    from pynfe.processamento.assinatura import AssinaturaA1
    print("[OK] AssinaturaA1 imported")
    from lxml import etree
    print("[OK] lxml.etree imported")
    
    e = EventoCancelarNota()
    print(f"[OK] EventoCancelarNota instance created.")
    
    # Check serializador
    try:
        from datetime import datetime
        e.chave = "35240312345678901234567890123456789012345678"
        e.protocolo = "1234567890"
        e.justificativa = "Justificativa de teste com mais de quinze caracteres"
        e.data_emissao = datetime.now()
        e.uf = "SP"
        e.cnpj = "12345678000199"
        
        serializador = SerializacaoXML(None, homologacao=True)
        xml = serializador.serializar_evento(e)
        print(f"[OK] Evento serialized to XML: {type(xml)}")
    except Exception as e_ser:
        print(f"[ERROR] Serialization failed: {e_ser}")
        import traceback
        traceback.print_exc()
    
except Exception as ex:
    print(f"[ERROR] Import test failed: {ex}")
    import traceback
    traceback.print_exc()
