"""
Exemplo de uso do ACBrLib para emissão de NFC-e
Demonstra como usar ACBrLib ou fallback SOAP manual
"""

from nfce_acbrlib import criar_servico_nfce


def exemplo_emissao_nfce():
    """Exemplo completo de emissão de NFC-e"""
    
    # 1. Criar serviço (tenta ACBrLib, usa fallback se não disponível)
    print("Criando serviço NFC-e...")
    nfce = criar_servico_nfce(usar_acbrlib=True)
    
    # 2. Dados da empresa
    empresa_data = {
        'cnpj': '12345678000190',
        'razao_social': 'Minha Empresa LTDA',
        'nome_fantasia': 'Minha Empresa',
        'uf': 'SP',
        'inscricao_estadual': '123456789012',
        'crt': '3',  # 1=Simples, 2=Simples Excesso, 3=Regime Normal
        'codigo_municipio_ibge': '3550308',  # São Paulo
        'endereco': 'Rua Exemplo',
        'numero': '123',
        'bairro': 'Centro',
        'cidade': 'São Paulo',
        'cep': '01000000',
        'telefone': '11999999999',
        'serie_nfce': '1',
        'certificado_base64': 'BASE64_DO_CERTIFICADO_PFX',  # Substituir
        'senhaCertificado': 'senha123',  # Substituir
        'ambienteHomologacao': True,  # True para homologação, False para produção
    }
    
    # 3. Produtos
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
        },
        {
            'codigo': '002',
            'descricao': 'Produto Exemplo 2',
            'ncm': '21069090',
            'cfop': '5102',
            'unidade': 'UN',
            'quantidade': 2.0,
            'valor_unitario': 15.00,
            'valor_total': 30.00,
            'codigo_barras': '7891234567891',
            'icms': {
                'origem': '0',
                'cst': '102',
                'aliquota': 18.0
            }
        }
    ]
    
    # 4. Pagamentos
    pagamentos = [
        {
            'tipo': '01',  # 01=Dinheiro, 03=Cartão Crédito, 04=Cartão Débito, 99=Outros
            'valor': 40.00
        }
    ]
    
    # 5. Consumidor (opcional)
    consumidor = {
        'cpf': '12345678901',  # Opcional
        'nome': 'Consumidor Final'  # Opcional
    }
    
    # 6. Emitir NFC-e
    print("\n" + "=" * 60)
    print("EMITINDO NFC-e")
    print("=" * 60)
    
    resultado = nfce.emitir(
        empresa_data=empresa_data,
        produtos=produtos,
        pagamentos=pagamentos,
        consumidor=consumidor,
        observacoes='Venda exemplo',
        numero_nfce=1
    )
    
    # 7. Processar resultado
    print("\n" + "=" * 60)
    print("RESULTADO")
    print("=" * 60)
    
    if resultado.get('success'):
        print("✅ NFC-e AUTORIZADA!")
        print(f"   Chave de Acesso: {resultado.get('chave_acesso', 'N/A')}")
        print(f"   Protocolo: {resultado.get('protocolo', 'N/A')}")
        print(f"   Mensagem: {resultado.get('mensagem', 'N/A')}")
    else:
        print("❌ NFC-e REJEITADA")
        print(f"   Erro: {resultado.get('error', 'Erro desconhecido')}")
        print(f"   Tipo: {resultado.get('error_type', 'N/A')}")
        if 'codigo_erro' in resultado:
            print(f"   Código: {resultado['codigo_erro']}")
    
    return resultado


if __name__ == '__main__':
    print("=" * 60)
    print("EXEMPLO DE USO - ACBrLib NFC-e")
    print("=" * 60)
    print("\nEste exemplo demonstra como usar ACBrLib para emitir NFC-e.")
    print("Se ACBrLib não estiver instalado, usará fallback SOAP manual.\n")
    
    try:
        resultado = exemplo_emissao_nfce()
        
        if resultado.get('success'):
            print("\n✅ Exemplo executado com sucesso!")
        else:
            print("\n⚠️ Exemplo executado, mas NFC-e foi rejeitada.")
            print("   Verifique os dados (certificado, empresa, etc.)")
            
    except Exception as e:
        print(f"\n❌ Erro ao executar exemplo: {e}")
        import traceback
        traceback.print_exc()



















