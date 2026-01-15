"""
Exemplo de uso do PyNFe para emissão de NFC-e
"""

from nfce_pynfe import criar_servico_nfce_pynfe


def exemplo_pynfe():
    """Exemplo de emissão usando PyNFe"""
    
    # Verificar se PyNFe está disponível
    nfce = criar_servico_nfce_pynfe()
    
    if not nfce:
        print("❌ PyNFe não está disponível")
        print("   Instale em modo desenvolvimento:")
        print("   cd pynfe_dev && pip install -e .")
        return
    
    print("✅ PyNFe disponível")
    
    # Dados da empresa
    empresa_data = {
        'cnpj': '12345678000190',
        'razao_social': 'Minha Empresa LTDA',
        'nome_fantasia': 'Minha Empresa',
        'uf': 'PR',  # PyNFe funciona melhor para estados que não são SP
        'inscricao_estadual': '123456789012',
        'crt': '3',
        'codigo_municipio_ibge': '4118402',  # Paranavaí - PR
        'endereco': 'Rua Exemplo',
        'numero': '123',
        'bairro': 'Centro',
        'cidade': 'Paranavaí',
        'cep': '87704000',
        'telefone': '44999999999',
        'serie_nfce': '1',
        'certificado_base64': 'BASE64_DO_CERTIFICADO',  # Substituir
        'senhaCertificado': 'senha123',  # Substituir
        'ambienteHomologacao': True,
    }
    
    # Produtos
    produtos = [
        {
            'codigo': '001',
            'descricao': 'Produto Exemplo 1',
            'ncm': '21069090',
            'cfop': '5102',
            'unidade': 'UN',
            'quantidade': 1.0,
            'valor_unitario': 10.00,
            'valor_total': 10.00,
            'codigo_barras': '7891234567890',
            'icms': {
                'origem': '0',
                'cst': '102',
                'aliquota': 18.0
            }
        }
    ]
    
    # Pagamentos
    pagamentos = [
        {'tipo': '01', 'valor': 10.00}  # Dinheiro
    ]
    
    # Emitir
    resultado = nfce.emitir(
        empresa_data=empresa_data,
        produtos=produtos,
        pagamentos=pagamentos,
        numero_nfce=1
    )
    
    # Processar resultado
    if resultado.get('success'):
        print(f"\n✅ NFC-e autorizada: {resultado.get('chave_acesso')}")
    else:
        print(f"\n❌ Erro: {resultado.get('error')}")


if __name__ == '__main__':
    exemplo_pynfe()

