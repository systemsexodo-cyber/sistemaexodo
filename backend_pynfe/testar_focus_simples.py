#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Script para testar emissão de NFC-e usando Focus NFe API
MUITO MAIS SIMPLES que as tentativas anteriores!
"""

import requests
import json
import os
from dotenv import load_dotenv

load_dotenv()

# Configurações
BACKEND_URL = 'http://localhost:5000'
FOCUS_TOKEN = os.getenv('FOCUSNFE_TOKEN', '')

def testar_emissao():
    """Testa emissão de NFC-e via Focus NFe API"""
    
    print("=" * 60)
    print("TESTE: Emissão NFC-e - Focus NFe API (SIMPLES)")
    print("=" * 60)
    print()
    
    # Verificar se backend está rodando
    print("1. Verificando se backend está rodando...")
    try:
        response = requests.get(f'{BACKEND_URL}/health', timeout=5)
        if response.status_code == 200:
            print("   ✅ Backend está rodando")
        else:
            print(f"   ❌ Backend retornou status {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print("   ❌ Backend não está rodando!")
        print(f"   Inicie o servidor: python app_simples_focus.py")
        return False
    except Exception as e:
        print(f"   ❌ Erro ao conectar: {e}")
        return False
    
    print()
    
    # Verificar token
    if not FOCUS_TOKEN:
        print("⚠️  AVISO: Token Focus NFe não configurado!")
        print("   Configure no arquivo .env: FOCUSNFE_TOKEN=seu_token")
        print("   Ou obtenha em: https://focusnfe.com.br")
        print()
        resposta = input("Deseja continuar mesmo assim? (s/n): ")
        if resposta.lower() != 's':
            return False
    
    # Dados de teste
    print("2. Preparando dados da NFC-e de teste...")
    
    request_data = {
        'empresa': {
            'cnpj': '12345678000190',  # CNPJ de teste
            'razao_social': 'Empresa Teste LTDA',
            'nome_fantasia': 'Teste',
            'inscricao_estadual': '123456789',
            'codigo_municipio_ibge': '3550308',  # São Paulo
            'uf': 'SP',
            'endereco': {
                'logradouro': 'Rua Teste',
                'numero': '123',
                'bairro': 'Centro',
                'cidade': 'São Paulo',
                'cep': '01000-000'
            },
            'telefone': '11999999999',
            'ambiente_homologacao': True  # SEMPRE homologação para teste
        },
        'produtos': [
            {
                'codigo': '001',
                'descricao': 'Produto Teste NFC-e',
                'ncm': '21069090',
                'cfop': '5102',
                'unidade': 'UN',
                'quantidade': 1.0,
                'valor_unitario': 10.00,
                'valor_total': 10.00,
                'icms': {
                    'origem': '0',
                    'cst': '102',  # Simples Nacional sem tributação
                    'aliquota': 0.0
                }
            }
        ],
        'pagamentos': [
            {
                'tipo': '01',  # Dinheiro
                'valor': 10.00
            }
        ],
        'consumidor': {
            'nome': 'CONSUMIDOR FINAL'
        },
        'observacoes': 'NFC-e de teste - Focus NFe API'
    }
    
    print(f"   CNPJ: {request_data['empresa']['cnpj']}")
    print(f"   Ambiente: HOMOLOGAÇÃO")
    print(f"   Produtos: {len(request_data['produtos'])}")
    print(f"   Valor total: R$ {request_data['produtos'][0]['valor_total']:.2f}")
    print()
    
    # Enviar requisição
    print("3. Enviando requisição para emitir NFC-e...")
    try:
        response = requests.post(
            f'{BACKEND_URL}/api/nfce/emitir',
            json=request_data,
            headers={'Content-Type': 'application/json'},
            timeout=120
        )
        
        print(f"   Status HTTP: {response.status_code}")
        print()
        
        # Processar resposta
        if response.status_code == 200:
            data = response.json()
            
            if data.get('success'):
                print("   ✅ NFC-e PROCESSADA!")
                print()
                print("   Detalhes:")
                print(f"   - Status: {data.get('status', 'N/A')}")
                print(f"   - Chave de acesso: {data.get('chave_acesso', 'N/A')}")
                print(f"   - Número: {data.get('numero', 'N/A')}")
                print(f"   - Série: {data.get('serie', 'N/A')}")
                
                if data.get('status') == 'autorizada':
                    print(f"   - Protocolo: {data.get('protocolo', 'N/A')}")
                    print(f"   - QR Code: {data.get('qr_code', 'N/A')[:50]}...")
                    print()
                    print("   ✅ NFC-e AUTORIZADA PELA SEFAZ!")
                    return True
                else:
                    print(f"   - Erro: {data.get('error', 'N/A')}")
                    print()
                    print("   ⚠️ NFC-e REJEITADA")
                    return False
            else:
                print("   ❌ ERRO NA EMISSÃO")
                error_msg = data.get('error', 'Erro desconhecido')
                error_type = data.get('error_type', 'Unknown')
                
                print(f"   Tipo: {error_type}")
                print(f"   Erro: {error_msg}")
                
                if 'details' in data:
                    print()
                    print("   Detalhes técnicos:")
                    print(data['details'])
                
                return False
        else:
            error_data = response.json()
            print("   ❌ ERRO HTTP")
            print(f"   Status: {response.status_code}")
            print(f"   Erro: {error_data.get('error', 'Erro desconhecido')}")
            
            if 'details' in error_data:
                print()
                print("   Detalhes técnicos:")
                print(error_data['details'])
            
            return False
            
    except requests.exceptions.Timeout:
        print("   ❌ Timeout ao emitir NFC-e")
        return False
    except Exception as e:
        print(f"   ❌ Erro ao emitir: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Função principal"""
    
    print()
    print("=" * 60)
    print("TESTE DE EMISSÃO NFC-e - Focus NFe API")
    print("=" * 60)
    print()
    print("Esta é a forma MAIS SIMPLES de emitir NFC-e!")
    print("A Focus NFe API faz tudo para você:")
    print("  - Gera o XML")
    print("  - Assina com certificado")
    print("  - Envia para SEFAZ")
    print("  - Retorna o resultado")
    print()
    print("Você só precisa:")
    print("  1. Ter um token da Focus NFe (gratuito para testes)")
    print("  2. Enviar os dados em JSON")
    print("  3. Receber a NFC-e autorizada!")
    print()
    print("=" * 60)
    print()
    
    sucesso = testar_emissao()
    
    print()
    print("=" * 60)
    if sucesso:
        print("✅ TESTE CONCLUÍDO COM SUCESSO!")
    else:
        print("❌ TESTE FALHOU")
        print()
        print("DICAS:")
        print("  1. Verifique se o backend está rodando")
        print("  2. Configure o token Focus NFe no arquivo .env")
        print("  3. Obtenha um token em: https://focusnfe.com.br")
    print("=" * 60)
    print()

if __name__ == '__main__':
    main()




















