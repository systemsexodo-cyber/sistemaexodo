"""
Exemplo completo de uso do sistema manual de NFC-e
Demonstra como emitir NFC-e sem usar PyNFe ou ACBr
"""

from nfce_manual_completo import NFCeManualCompleto


def exemplo_completo():
    """Exemplo completo de emissão de NFC-e"""
    
    # 1. Criar instância
    nfce = NFCeManualCompleto()
    
    # 2. Carregar certificado (opção 1: base64)
    certificado_base64 = "BASE64_DO_CERTIFICADO_PFX_AQUI"  # Substituir
    senha_certificado = "senha123"  # Substituir
    
    if not nfce.carregar_certificado(certificado_base64, senha_certificado):
        print("❌ Erro ao carregar certificado")
        return
    
    # Opção 2: Carregar de arquivo
    # nfce.carregar_certificado_arquivo("certificado.pfx", "senha123")
    
    # 3. Dados da empresa
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
        'natureza_operacao': 'VENDA',
        'ambienteHomologacao': True,  # True para homologação, False para produção
    }
    
    # 4. Produtos
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
    
    # 5. Pagamentos
    pagamentos = [
        {
            'tipo': '01',  # 01=Dinheiro, 03=Cartão Crédito, 04=Cartão Débito, 99=Outros
            'valor': 40.00
        }
    ]
    
    # 6. Consumidor (opcional)
    consumidor = {
        'cpf': '12345678901',  # Opcional
        'nome': 'Consumidor Final'  # Opcional
    }
    
    # 7. Emitir NFC-e
    resultado = nfce.emitir(
        empresa_data=empresa_data,
        produtos=produtos,
        pagamentos=pagamentos,
        consumidor=consumidor,
        observacoes='Venda exemplo - Implementação manual',
        numero_nfce=1
    )
    
    # 8. Processar resultado
    print("\n" + "=" * 60)
    print("RESULTADO FINAL")
    print("=" * 60)
    
    if resultado.get('success'):
        print("✅ NFC-e AUTORIZADA!")
        print(f"   Chave de Acesso: {resultado.get('chave_acesso', 'N/A')}")
        print(f"   Protocolo: {resultado.get('protocolo', 'N/A')}")
        print(f"   Mensagem: {resultado.get('mensagem', 'N/A')}")
        if 'qrcode_url' in resultado:
            print(f"   QR Code URL: {resultado['qrcode_url']}")
    else:
        print("❌ NFC-e REJEITADA")
        print(f"   Erro: {resultado.get('error', 'Erro desconhecido')}")
        print(f"   Tipo: {resultado.get('error_type', 'N/A')}")
        if 'codigo_erro' in resultado:
            print(f"   Código: {resultado['codigo_erro']}")
    
    return resultado


if __name__ == '__main__':
    print("=" * 60)
    print("EXEMPLO - NFC-e IMPLEMENTAÇÃO MANUAL")
    print("=" * 60)
    print("\nEste exemplo demonstra como emitir NFC-e sem usar PyNFe ou ACBr.")
    print("Tudo é feito manualmente em Python puro.\n")
    
    try:
        resultado = exemplo_completo()
        
        if resultado and resultado.get('success'):
            print("\n✅ Exemplo executado com sucesso!")
        else:
            print("\n⚠️ Exemplo executado, mas NFC-e foi rejeitada.")
            print("   Verifique os dados (certificado, empresa, etc.)")
            
    except Exception as e:
        print(f"\n❌ Erro ao executar exemplo: {e}")
        import traceback
        traceback.print_exc()



















