#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Exemplo de como rodar/testar o PyNFe para emitir NFC-e

Uso:
    python exemplo_rodar_pynfe.py
"""

import os
import base64
from nfce_pynfe import NFCePyNFe, criar_servico_nfce_pynfe

# ============================================================================
# CONFIGURAÇÕES - SUBSTITUA COM SEUS DADOS REAIS
# ============================================================================

# Certificado Digital (PFX/P12) em Base64
# Para converter: base64.b64encode(open("certificado.pfx", "rb").read()).decode('utf-8')
CERTIFICADO_BASE64 = "SEU_CERTIFICADO_PFX_EM_BASE64_AQUI"
SENHA_CERTIFICADO = "SUA_SENHA_DO_CERTIFICADO"

# Dados da Empresa
EMPRESA_DATA = {
    'cnpj': '12345678000190',  # Apenas números
    'razao_social': 'EMPRESA TESTE LTDA',
    'nome_fantasia': 'TESTE',
    'inscricao_estadual': '123456789012',
    'uf': 'PR',  # ⚠️ IMPORTANTE: PyNFe funciona melhor para estados que NÃO são SP
    'codigoIBGE': '4118402',  # Código IBGE do município (ex: Paranavaí-PR)
    'cidade': 'Paranavai',
    'endereco': 'Rua Teste',
    'numero': '123',
    'bairro': 'Centro',
    'cep': '87704000',
    'telefone': '11999999999',
    'crt': '3',  # 1=Simples Nacional, 3=Regime Normal
    'ambiente_homologacao': True,  # True=Homologação, False=Produção
    'certificado_base64': CERTIFICADO_BASE64,
    'senhaCertificado': SENHA_CERTIFICADO,
    'serie_nfce': '1',  # Série da NFC-e
}

# Produtos
PRODUTOS = [
    {
        'codigo': 'PROD001',
        'codigoBarras': 'SEM GTIN',
        'descricao': 'Produto Teste 1',
        'ncm': '00000000',
        'cfop': '5102',
        'unidade': 'UN',
        'quantidade': 1.0,
        'valorUnitario': 10.00,
        'valorTotal': 10.00,
        'icms': {
            'origem': 0,
            'cst': '00',  # CST para regime normal
            'modalidade': '00',
            'aliquota': 18.0
        }
    },
    {
        'codigo': 'PROD002',
        'codigoBarras': 'SEM GTIN',
        'descricao': 'Produto Teste 2',
        'ncm': '00000000',
        'cfop': '5102',
        'unidade': 'UN',
        'quantidade': 2.0,
        'valorUnitario': 5.00,
        'valorTotal': 10.00,
        'icms': {
            'origem': 0,
            'cst': '00',
            'modalidade': '00',
            'aliquota': 18.0
        }
    }
]

# Pagamentos
PAGAMENTOS = [
    {
        'tipo': '01',  # 01=Dinheiro, 03=Cartão Crédito, 04=Cartão Débito, 99=Outros
        'valor': 20.00
    }
]

# Consumidor (opcional)
CONSUMIDOR_DATA = {
    'cpf': '00000000000',  # Opcional para NFC-e
    'nome': 'CONSUMIDOR FINAL'
}

OBSERVACOES = "Documento emitido por software proprio."

# ============================================================================
# FUNÇÃO PRINCIPAL
# ============================================================================

def main():
    """Função principal para testar emissão NFC-e com PyNFe"""
    
    print("=" * 70)
    print("TESTE DE EMISSÃO NFC-e COM PyNFe")
    print("=" * 70)
    
    # Verificar se certificado foi configurado
    if CERTIFICADO_BASE64 == "SEU_CERTIFICADO_PFX_EM_BASE64_AQUI":
        print("\n❌ ERRO: Configure o certificado digital primeiro!")
        print("\nPara converter seu certificado .pfx para base64:")
        print("  python -c \"import base64; print(base64.b64encode(open('certificado.pfx', 'rb').read()).decode('utf-8'))\"")
        return
    
    # Verificar se PyNFe está disponível
    try:
        nfce = criar_servico_nfce_pynfe()
        if nfce is None:
            print("\n❌ ERRO: PyNFe não está instalado!")
            print("\nPara instalar em modo desenvolvimento:")
            print("  cd pynfe_dev")
            print("  pip install -e .")
            return
    except Exception as e:
        print(f"\n❌ ERRO ao criar serviço PyNFe: {e}")
        return
    
    # Aviso sobre SP
    if EMPRESA_DATA.get('uf', '').upper() == 'SP':
        print("\n⚠️  AVISO: PyNFe não funciona bem para São Paulo (SP)")
        print("   SP não usa WSDL para NFC-e e usa SVRS")
        print("   Use a implementação manual (nfce_manual_completo.py) para SP")
        resposta = input("\nDeseja continuar mesmo assim? (s/N): ")
        if resposta.lower() != 's':
            return
    
    # Emitir NFC-e
    print("\n" + "=" * 70)
    print("INICIANDO EMISSÃO...")
    print("=" * 70)
    
    try:
        resultado = nfce.emitir(
            empresa_data=EMPRESA_DATA,
            produtos=PRODUTOS,
            pagamentos=PAGAMENTOS,
            consumidor=CONSUMIDOR_DATA,
            observacoes=OBSERVACOES,
            numero_nfce=1  # Número sequencial da NFC-e
        )
        
        # Exibir resultado
        print("\n" + "=" * 70)
        print("RESULTADO DA EMISSÃO")
        print("=" * 70)
        
        if resultado.get('success'):
            print("\n✅ NFC-e AUTORIZADA COM SUCESSO!")
            print(f"\n📋 Chave de Acesso: {resultado.get('chave_acesso')}")
            print(f"📄 Protocolo: {resultado.get('protocolo')}")
            print(f"💬 Mensagem: {resultado.get('mensagem')}")
            
            # Gerar QR Code (se tiver método)
            if hasattr(nfce, 'gerar_qrcode'):
                ambiente = EMPRESA_DATA.get('ambiente_homologacao', True)
                qrcode_url = nfce.gerar_qrcode(resultado.get('chave_acesso', ''), ambiente)
                print(f"📱 QR Code URL: {qrcode_url}")
            
        else:
            print("\n❌ NFC-e REJEITADA")
            print(f"\n🔴 Erro: {resultado.get('error')}")
            print(f"📊 Código de Erro SEFAZ: {resultado.get('codigo_erro', 'N/A')}")
            print(f"🏷️  Tipo de Erro: {resultado.get('error_type', 'N/A')}")
            
            if 'details' in resultado:
                print(f"\n📝 Detalhes técnicos:")
                print(resultado['details'])
            
            if 'resposta_sefaz' in resultado:
                print(f"\n📨 Resposta SEFAZ (primeiros 500 chars):")
                print(resultado['resposta_sefaz'])
        
        print("\n" + "=" * 70)
        
    except Exception as e:
        print(f"\n❌ ERRO INESPERADO: {e}")
        import traceback
        print("\n📝 Traceback completo:")
        print(traceback.format_exc())


# ============================================================================
# EXECUTAR
# ============================================================================

if __name__ == "__main__":
    main()

















