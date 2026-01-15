#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Script de teste para emitir NFC-e usando PyNFe em modo desenvolvimento
Execute: python testar_emissao_nfce.py
"""

import os
import sys
from pathlib import Path

# Adicionar diretório atual ao path
sys.path.insert(0, str(Path(__file__).parent))

print("=" * 70)
print("TESTE DE EMISSÃO NFC-e - PyNFe (Modo Desenvolvimento)")
print("=" * 70)

# Verificar se PyNFe está instalado
try:
    import pynfe
    print(f"[OK] PyNFe versao {pynfe.__version__} encontrado")
    print(f"   Localizacao: {pynfe.__file__}")
except ImportError:
    print("[ERRO] PyNFe nao esta instalado!")
    print("\nPara instalar em modo desenvolvimento:")
    print("  cd pynfe_dev")
    print("  pip install -e .")
    sys.exit(1)

# Verificar se nfce_pynfe está disponível
try:
    from nfce_pynfe import NFCePyNFe, criar_servico_nfce_pynfe
    print("[OK] Modulo nfce_pynfe importado com sucesso")
except ImportError as e:
    print(f"[ERRO] Erro ao importar nfce_pynfe: {e}")
    sys.exit(1)

# ============================================================================
# CONFIGURAÇÕES - AJUSTE AQUI
# ============================================================================

print("\n" + "=" * 70)
print("CONFIGURAÇÃO")
print("=" * 70)

# Certificado
CERTIFICADO_PATH = input("\n[CERTIFICADO] Caminho do certificado .pfx (ou Enter para usar base64): ").strip()

if CERTIFICADO_PATH:
    # Converter certificado para base64
    try:
        import base64
        with open(CERTIFICADO_PATH, 'rb') as f:
            cert_bytes = f.read()
        CERTIFICADO_BASE64 = base64.b64encode(cert_bytes).decode('utf-8')
        print(f"[OK] Certificado convertido: {len(CERTIFICADO_BASE64)} caracteres")
    except Exception as e:
        print(f"[ERRO] Erro ao ler certificado: {e}")
        sys.exit(1)
else:
    CERTIFICADO_BASE64 = input("[CERTIFICADO] Cole o certificado em Base64: ").strip()
    if not CERTIFICADO_BASE64:
        print("[ERRO] Certificado nao fornecido!")
        sys.exit(1)

SENHA_CERTIFICADO = input("[SENHA] Senha do certificado: ").strip()
if not SENHA_CERTIFICADO:
    print("[ERRO] Senha nao fornecida!")
    sys.exit(1)

# Dados da Empresa
print("\n[EMPRESA] Dados da Empresa:")
CNPJ = input("   CNPJ (apenas numeros): ").strip().replace('.', '').replace('/', '').replace('-', '')
if not CNPJ:
    CNPJ = "12345678000190"  # Padrao para teste
    print(f"   Usando CNPJ padrao: {CNPJ}")

RAZAO_SOCIAL = input("   Razao Social: ").strip()
if not RAZAO_SOCIAL:
    RAZAO_SOCIAL = "EMPRESA TESTE LTDA"
    print(f"   Usando: {RAZAO_SOCIAL}")

UF = input("   UF (ex: PR, RS, SC - NAO use SP): ").strip().upper()
if not UF:
    UF = "PR"
    print(f"   Usando: {UF}")

if UF == "SP":
    print("\n[AVISO] PyNFe nao funciona bem para SP!")
    print("   Use a implementacao manual (nfce_manual_completo.py) para SP")
    resposta = input("   Continuar mesmo assim? (s/N): ")
    if resposta.lower() != 's':
        sys.exit(0)

CODIGO_IBGE = input("   Código IBGE do município (ou Enter para padrão): ").strip()
if not CODIGO_IBGE:
    CODIGO_IBGE = "4118402"  # Paranavaí-PR
    print(f"   Usando: {CODIGO_IBGE}")

AMBIENTE = input("   Ambiente (1=Homologação, 2=Produção) [1]: ").strip()
AMBIENTE_HOMOLOGACAO = AMBIENTE != "2"

# ============================================================================
# DADOS FIXOS PARA TESTE
# ============================================================================

EMPRESA_DATA = {
    'cnpj': CNPJ,
    'razao_social': RAZAO_SOCIAL,
    'nome_fantasia': RAZAO_SOCIAL,
    'inscricao_estadual': '123456789012',
    'uf': UF,
    'codigoIBGE': CODIGO_IBGE,
    'cidade': 'Teste',
    'endereco': 'Rua Teste',
    'numero': '123',
    'bairro': 'Centro',
    'cep': '00000000',
    'telefone': '11999999999',
    'crt': '3',  # 1=Simples Nacional, 3=Regime Normal
    'ambiente_homologacao': AMBIENTE_HOMOLOGACAO,
    'certificado_base64': CERTIFICADO_BASE64,
    'senhaCertificado': SENHA_CERTIFICADO,
    'serie_nfce': '1',
}

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
            'cst': '00',
            'modalidade': '00',
            'aliquota': 18.0
        }
    }
]

PAGAMENTOS = [
    {
        'tipo': '01',  # 01=Dinheiro
        'valor': 10.00
    }
]

# ============================================================================
# EXECUTAR TESTE
# ============================================================================

print("\n" + "=" * 70)
print("INICIANDO EMISSÃO NFC-e")
print("=" * 70)

try:
    # Criar serviço
    nfce = criar_servico_nfce_pynfe()
    if nfce is None:
        print("❌ Não foi possível criar serviço PyNFe")
        sys.exit(1)
    
    # Emitir
    resultado = nfce.emitir(
        empresa_data=EMPRESA_DATA,
        produtos=PRODUTOS,
        pagamentos=PAGAMENTOS,
        consumidor=None,
        observacoes="Teste de emissão NFC-e com PyNFe",
        numero_nfce=1
    )
    
    # Exibir resultado
    print("\n" + "=" * 70)
    print("RESULTADO")
    print("=" * 70)
    
    if resultado.get('success'):
        print("\n[SUCESSO] NFC-e AUTORIZADA COM SUCESSO!")
        print(f"\nChave de Acesso: {resultado.get('chave_acesso')}")
        print(f"Protocolo: {resultado.get('protocolo')}")
        print(f"Mensagem: {resultado.get('mensagem')}")
        
        # Salvar XML se disponível
        if 'xml' in resultado:
            xml_file = "nfce_autorizada.xml"
            with open(xml_file, 'w', encoding='utf-8') as f:
                f.write(resultado['xml'])
            print(f"XML salvo em: {xml_file}")
        
    else:
        print("\n[ERRO] NFC-e REJEITADA")
        print(f"\nErro: {resultado.get('error')}")
        print(f"Codigo de Erro: {resultado.get('codigo_erro', 'N/A')}")
        print(f"Tipo: {resultado.get('error_type', 'N/A')}")
        
        if 'details' in resultado:
            print(f"\nDetalhes:")
            print(resultado['details'][:500])  # Primeiros 500 chars
        
        if 'resposta_sefaz' in resultado:
            print(f"\nResposta SEFAZ:")
            print(resultado['resposta_sefaz'][:500])
    
    print("\n" + "=" * 70)
    
except KeyboardInterrupt:
    print("\n\n[AVISO] Teste interrompido pelo usuario")
    sys.exit(0)
except Exception as e:
    print(f"\n[ERRO] ERRO INESPERADO: {e}")
    import traceback
    print("\nTraceback:")
    print(traceback.format_exc())
    sys.exit(1)
