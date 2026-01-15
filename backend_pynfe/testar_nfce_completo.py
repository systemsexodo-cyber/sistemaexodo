"""
Script de teste para o sistema completo de NFC-e
"""

import json
import base64
from nfce_completo import NFCeCompleto

def testar_emissao():
    """Testa emissão de NFC-e"""
    
    print("=" * 60)
    print("TESTE: Sistema Completo de Emissão NFC-e")
    print("=" * 60)
    print()
    
    # Criar instância
    nfce = NFCeCompleto()
    
    # Dados de teste
    empresa_data = {
        'cnpj': '12345678000190',
        'razaoSocial': 'Empresa Teste LTDA',
        'nomeFantasia': 'Teste',
        'inscricaoEstadual': '123456789',
        'codigoIBGE': '3550308',  # São Paulo
        'uf': 'SP',
        'endereco': 'Rua Teste',
        'numero': '123',
        'bairro': 'Centro',
        'cidade': 'São Paulo',
        'cep': '01000-000',
        'telefone': '11999999999',
        'crt': 3,
        'serie_nfce': 1,
        'ambienteHomologacao': True,  # SEMPRE homologação para teste
        'certificado_base64': '',  # Preencher com certificado real
        'senhaCertificado': ''  # Preencher com senha real
    }
    
    produtos = [
        {
            'codigo': '001',
            'descricao': 'Produto Teste NFC-e',
            'ncm': '21069090',
            'cfop': '5102',
            'unidade': 'UN',
            'quantidade': 1.0,
            'valorUnitario': 10.00,
            'valorTotal': 10.00,
            'icms': {
                'origem': '0',
                'cst': '102',
                'aliquota': 0.0
            }
        }
    ]
    
    pagamentos = [
        {
            'tipo': '01',  # Dinheiro
            'valor': 10.00
        }
    ]
    
    consumidor = {
        'nome': 'CONSUMIDOR FINAL'
    }
    
    print("⚠️  IMPORTANTE: Configure o certificado antes de testar!")
    print("   - certificado_base64: Base64 do arquivo .pfx")
    print("   - senhaCertificado: Senha do certificado")
    print()
    
    # Verificar se certificado foi configurado
    if not empresa_data['certificado_base64']:
        print("❌ Certificado não configurado!")
        print()
        print("Para testar:")
        print("1. Obtenha um certificado digital A1 (.pfx)")
        print("2. Converta para base64:")
        print("   import base64")
        print("   with open('certificado.pfx', 'rb') as f:")
        print("       certificado_base64 = base64.b64encode(f.read()).decode('utf-8')")
        print("3. Configure no código acima")
        return False
    
    # Emitir NFC-e
    resultado = nfce.emitir(
        empresa_data=empresa_data,
        produtos=produtos,
        pagamentos=pagamentos,
        consumidor=consumidor,
        observacoes='NFC-e de teste - Sistema Completo',
        numero_nfce=1
    )
    
    print()
    print("=" * 60)
    if resultado.get('success'):
        print("✅ NFC-e EMITIDA COM SUCESSO!")
        print("=" * 60)
        print(f"Chave de acesso: {resultado.get('chave_acesso', 'N/A')}")
        print(f"Protocolo: {resultado.get('protocolo', 'N/A')}")
        print(f"Status: {resultado.get('status', 'N/A')}")
        return True
    else:
        print("❌ ERRO NA EMISSÃO")
        print("=" * 60)
        print(f"Erro: {resultado.get('error', 'N/A')}")
        print(f"Tipo: {resultado.get('error_type', 'N/A')}")
        if resultado.get('codigo_erro'):
            print(f"Código: {resultado.get('codigo_erro')}")
        return False

if __name__ == '__main__':
    testar_emissao()




















