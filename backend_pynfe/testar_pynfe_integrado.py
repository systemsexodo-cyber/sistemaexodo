"""
Script para testar se o PyNFe está integrado corretamente
"""

import sys
import os

# Adicionar caminho do PyNFe
pynfe_path = os.path.abspath(os.path.join('..', '..', 'PyNFe'))
if pynfe_path not in sys.path:
    sys.path.insert(0, pynfe_path)
    print(f"✅ Caminho PyNFe adicionado: {pynfe_path}")

print("=" * 60)
print("TESTE DE INTEGRAÇÃO PyNFe")
print("=" * 60)

# Testar importações
try:
    from pynfe.entidades.cliente import Cliente
    from pynfe.entidades.emitente import Emitente
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.entidades.fonte_dados import _fonte_dados
    from pynfe.processamento.assinatura import AssinaturaA1
    from pynfe.processamento.serializacao import SerializacaoXML
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    from pynfe.utils.flags import CODIGO_BRASIL
    print("✅ Todas as importações do PyNFe funcionaram!")
except ImportError as e:
    print(f"❌ Erro ao importar PyNFe: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Testar criação de instância do serviço
try:
    from nfce_pynfe_completo import criar_servico_nfce_pynfe_completo
    nfce_service = criar_servico_nfce_pynfe_completo()
    if nfce_service:
        print("✅ Serviço NFC-e criado com sucesso!")
        print(f"   Tipo: {type(nfce_service).__name__}")
    else:
        print("❌ Serviço NFC-e não foi criado (PyNFe não disponível)")
        sys.exit(1)
except Exception as e:
    print(f"❌ Erro ao criar serviço NFC-e: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("=" * 60)
print("✅ INTEGRAÇÃO COMPLETA - PyNFe está funcionando!")
print("=" * 60)





