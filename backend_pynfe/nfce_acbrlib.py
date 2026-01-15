"""
NFC-e usando ACBrLib - Implementação completa
Wrapper Python para ACBrLib com integração completa

Este módulo usa ACBrLib para emitir NFC-e, especialmente para SP
que não funciona com PyNFe.

Requisitos:
1. Baixar ACBrLib: https://projetoacbr.com.br/forum/viewtopic.php?f=111&t=70146
2. Instalar DLL (Windows) ou .so (Linux)
3. Configurar caminho da biblioteca
"""

import os
import sys
import json
from typing import Dict, Any, Optional
from acbrlib_wrapper import criar_instancia_acbr, ACBrLibNFCeFallback


class NFCeACBrLib:
    """
    Classe para emissão de NFC-e usando ACBrLib
    Funciona especialmente bem para SP (que não tem WSDL)
    """
    
    def __init__(self, caminho_acbrlib: Optional[str] = None):
        """
        Inicializa NFC-e com ACBrLib
        
        Args:
            caminho_acbrlib: Caminho para ACBrLib (opcional)
        """
        self.acbr = criar_instancia_acbr(caminho_acbrlib)
        self.usando_acbr = not isinstance(self.acbr, ACBrLibNFCeFallback)
        
        if self.usando_acbr:
            print("✅ Usando ACBrLib para emissão de NFC-e")
        else:
            print("⚠️ ACBrLib não disponível - usando SOAP manual")
    
    def emitir(
        self,
        empresa_data: Dict[str, Any],
        produtos: List[Dict[str, Any]],
        pagamentos: List[Dict[str, Any]],
        consumidor: Optional[Dict[str, Any]] = None,
        observacoes: str = '',
        numero_nfce: int = 1
    ) -> Dict[str, Any]:
        """
        Emite NFC-e usando ACBrLib
        
        Args:
            empresa_data: Dados da empresa
            produtos: Lista de produtos
            pagamentos: Lista de pagamentos
            consumidor: Dados do consumidor (opcional)
            observacoes: Observações
            numero_nfce: Número da NFC-e
        
        Returns:
            Dicionário com resultado da emissão
        """
        print("=" * 60)
        print("EMISSÃO NFC-e - ACBrLib")
        print("=" * 60)
        
        # Verificar se ACBrLib está disponível
        if not self.usando_acbr:
            print("⚠️ ACBrLib não disponível - usando fallback SOAP manual")
            return self.acbr.emitir_nfce(
                empresa_data=empresa_data,
                produtos=produtos,
                pagamentos=pagamentos,
                consumidor=consumidor,
                observacoes=observacoes,
                numero_nfce=numero_nfce
            )
        
        # Usar ACBrLib
        try:
            resultado = self.acbr.emitir_nfce(
                empresa_data=empresa_data,
                produtos=produtos,
                pagamentos=pagamentos,
                consumidor=consumidor,
                observacoes=observacoes,
                numero_nfce=numero_nfce,
                ambiente_homologacao=empresa_data.get('ambienteHomologacao', empresa_data.get('ambiente_homologacao', True))
            )
            
            print("\n" + "=" * 60)
            if resultado.get('success'):
                print("✅ NFC-e AUTORIZADA!")
            else:
                print("❌ NFC-e REJEITADA")
            print("=" * 60)
            
            return resultado
            
        except Exception as e:
            import traceback
            return {
                'success': False,
                'error': f'Erro ao emitir NFC-e via ACBrLib: {str(e)}',
                'error_type': 'ACBrLibError',
                'details': traceback.format_exc()
            }


def criar_servico_nfce(usar_acbrlib: bool = True, caminho_acbrlib: Optional[str] = None):
    """
    Factory para criar serviço de NFC-e
    
    Args:
        usar_acbrlib: Se True, tenta usar ACBrLib primeiro
        caminho_acbrlib: Caminho para ACBrLib
    
    Returns:
        Instância de NFCeACBrLib ou NFCeCompleto
    """
    if usar_acbrlib:
        try:
            return NFCeACBrLib(caminho_acbrlib)
        except Exception as e:
            print(f"⚠️ Erro ao inicializar ACBrLib: {e}")
            print("   Usando implementação SOAP manual")
            from nfce_completo import NFCeCompleto
            return NFCeCompleto()
    else:
        from nfce_completo import NFCeCompleto
        return NFCeCompleto()


# Exemplo de uso
if __name__ == '__main__':
    # Testar criação do serviço
    print("Testando criação de serviço NFC-e...")
    
    # Tentar com ACBrLib primeiro
    servico = criar_servico_nfce(usar_acbrlib=True)
    
    if isinstance(servico, NFCeACBrLib) and servico.usando_acbr:
        print("✅ Serviço criado com ACBrLib")
    else:
        print("✅ Serviço criado com SOAP manual (fallback)")



















