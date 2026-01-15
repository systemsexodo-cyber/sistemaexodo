#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Script para testar e debugar erros na emissão de NFC-e"""

import sys
import traceback
import json

# Adicionar o diretório atual ao path
sys.path.insert(0, '.')

print("=" * 50)
print("TESTE DE EMISSÃO NFC-e - DEBUG")
print("=" * 50)
print()

try:
    # Testar imports
    print("1. Testando imports...")
    from services.nfce_service import NFCeService, PYNFE_DISPONIVEL
    from services.certificado_service import CertificadoService
    
    if not PYNFE_DISPONIVEL:
        print("   ❌ PyNFe não está disponível!")
        sys.exit(1)
    
    print("   ✅ Imports OK")
    print()
    
    # Testar criação do serviço
    print("2. Criando serviços...")
    nfce_service = NFCeService()
    print("   ✅ NFCeService criado")
    print()
    
    # Dados de teste mínimos
    print("3. Preparando dados de teste...")
    dados_teste = {
        'empresa': {
            'cnpj': '12345678000190',
            'razao_social': 'Empresa Teste',
            'inscricao_estadual': '123456789',
            'certificado_base64': 'dGVzdGU=',  # "teste" em base64
            'senha_certificado': '123456',
            'csc': 'TESTE',
            'csc_id_token': '1',
            'serie': '1',
            'ambiente_homologacao': True,
            'uf': 'SP'
        },
        'produtos': [
            {
                'codigo': '001',
                'descricao': 'Produto Teste',
                'ncm': '12345678',
                'cfop': '5102',
                'unidade': 'UN',
                'quantidade': 1.0,
                'valor_unitario': 10.0,
                'valor_total': 10.0,
                'icms': {
                    'cst': '00',
                    'aliquota': 18.0
                }
            }
        ],
        'pagamentos': [
            {
                'tipo': '01',
                'valor': 10.0
            }
        ],
        'consumidor': {
            'nome': 'Consumidor Teste'
        }
    }
    print("   ✅ Dados de teste preparados")
    print()
    
    # Tentar emitir (vai falhar no certificado, mas vamos ver o erro completo)
    print("4. Tentando emitir NFC-e...")
    print("   (Vai falhar no certificado, mas vamos ver o erro completo)")
    print()
    
    resultado = nfce_service.emitir_nfce(dados_teste)
    
    print("   ✅ Emissão concluída!")
    print(json.dumps(resultado, indent=2, default=str))
    
except Exception as e:
    print()
    print("=" * 50)
    print("❌ ERRO CAPTURADO")
    print("=" * 50)
    print(f"Tipo: {type(e).__name__}")
    print(f"Mensagem: {str(e)}")
    print()
    print("Traceback completo:")
    print("-" * 50)
    traceback.print_exc()
    print("-" * 50)
    sys.exit(1)


