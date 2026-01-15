#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Script para testar validação de certificado via backend"""

import sys
import base64
import json
import requests

# URL do backend
BACKEND_URL = 'http://localhost:5000'

def testar_validacao_certificado(certificado_base64, senha):
    """Testa validação de certificado"""
    
    print("=" * 60)
    print("TESTE: Validação de Certificado")
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
        print(f"   Inicie o servidor: cd backend_pynfe && .\\iniciar_simples.bat")
        return False
    except Exception as e:
        print(f"   ❌ Erro ao conectar: {e}")
        return False
    
    print()
    
    # Preparar dados
    print("2. Preparando dados do certificado...")
    request_data = {
        'certificado_base64': certificado_base64,
        'senha': senha
    }
    
    print(f"   Certificado (base64): {certificado_base64[:50]}...")
    print(f"   Senha: {'*' * len(senha)}")
    print()
    
    # Enviar requisição
    print("3. Enviando requisição para validar certificado...")
    try:
        response = requests.post(
            f'{BACKEND_URL}/api/certificado/validar',
            json=request_data,
            headers={'Content-Type': 'application/json'},
            timeout=30
        )
        
        print(f"   Status HTTP: {response.status_code}")
        print()
        
        # Processar resposta
        if response.status_code == 200:
            data = response.json()
            
            if data.get('success'):
                print("   ✅ CERTIFICADO VÁLIDO!")
                print()
                print("   Detalhes:")
                print(f"   - Válido até: {data.get('valido_ate', 'N/A')}")
                print(f"   - Emitido para: {data.get('emitido_para', 'N/A')}")
                print(f"   - Emitido por: {data.get('emitido_por', 'N/A')}")
                return True
            else:
                print("   ❌ CERTIFICADO INVÁLIDO")
                print(f"   Erro: {data.get('error', 'Erro desconhecido')}")
                return False
        else:
            error_data = response.json()
            print("   ❌ ERRO NA VALIDAÇÃO")
            print(f"   Status: {response.status_code}")
            print(f"   Erro: {error_data.get('error', 'Erro desconhecido')}")
            
            if 'details' in error_data:
                print()
                print("   Detalhes técnicos:")
                print(error_data['details'])
            
            return False
            
    except requests.exceptions.Timeout:
        print("   ❌ Timeout ao validar certificado")
        return False
    except Exception as e:
        print(f"   ❌ Erro ao validar: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Função principal"""
    
    print()
    print("=" * 60)
    print("TESTE DE VALIDAÇÃO DE CERTIFICADO")
    print("=" * 60)
    print()
    
    # Verificar argumentos
    if len(sys.argv) < 3:
        print("Uso: python testar_certificado.py <certificado_base64> <senha>")
        print()
        print("Exemplo:")
        print("  python testar_certificado.py MIIKpAIBAz... 123456")
        print()
        print("Ou use um arquivo .pfx/.p12:")
        print("  python testar_certificado.py arquivo.pfx senha")
        print()
        
        # Tentar ler de arquivo se fornecido
        if len(sys.argv) == 2:
            arquivo = sys.argv[1]
            print(f"Tentando ler certificado de: {arquivo}")
            try:
                with open(arquivo, 'rb') as f:
                    certificado_bytes = f.read()
                    certificado_base64 = base64.b64encode(certificado_bytes).decode('utf-8')
                    senha = input("Digite a senha do certificado: ")
                    testar_validacao_certificado(certificado_base64, senha)
            except FileNotFoundError:
                print(f"❌ Arquivo não encontrado: {arquivo}")
            except Exception as e:
                print(f"❌ Erro ao ler arquivo: {e}")
        return
    
    certificado_base64 = sys.argv[1]
    senha = sys.argv[2]
    
    # Se for caminho de arquivo, ler o arquivo
    if certificado_base64.endswith('.pfx') or certificado_base64.endswith('.p12'):
        try:
            with open(certificado_base64, 'rb') as f:
                certificado_bytes = f.read()
                certificado_base64 = base64.b64encode(certificado_bytes).decode('utf-8')
        except Exception as e:
            print(f"❌ Erro ao ler arquivo: {e}")
            return
    
    # Testar
    sucesso = testar_validacao_certificado(certificado_base64, senha)
    
    print()
    print("=" * 60)
    if sucesso:
        print("✅ TESTE CONCLUÍDO COM SUCESSO!")
    else:
        print("❌ TESTE FALHOU")
    print("=" * 60)
    print()

if __name__ == '__main__':
    main()

