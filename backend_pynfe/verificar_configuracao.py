#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Script para verificar se está tudo configurado para emitir NFC-e
Execute: python verificar_configuracao.py
"""

import sys
import os
from pathlib import Path

print("=" * 70)
print("VERIFICACAO DE CONFIGURACAO - EMISSAO NFC-e")
print("=" * 70)

erros = []
avisos = []
sucessos = []

# ============================================================================
# 1. VERIFICAR PYTHON
# ============================================================================
print("\n[1/8] Verificando Python...")
try:
    versao = sys.version_info
    print(f"   Python {versao.major}.{versao.minor}.{versao.micro}")
    if versao.major >= 3 and versao.minor >= 8:
        sucessos.append("Python versao adequada")
    else:
        avisos.append(f"Python {versao.major}.{versao.minor} - recomendado 3.8+")
except Exception as e:
    erros.append(f"Erro ao verificar Python: {e}")

# ============================================================================
# 2. VERIFICAR PyNFe
# ============================================================================
print("\n[2/8] Verificando PyNFe...")
try:
    import pynfe
    versao = pynfe.__version__
    localizacao = pynfe.__file__
    print(f"   PyNFe versao: {versao}")
    print(f"   Localizacao: {localizacao}")
    
    # Verificar se está em modo desenvolvimento
    if 'pynfe_dev' in localizacao:
        sucessos.append("PyNFe instalado em modo desenvolvimento (editavel)")
    else:
        avisos.append("PyNFe nao esta em modo desenvolvimento")
    
    # Verificar módulos principais
    from pynfe.entidades.notafiscal import NotaFiscal
    from pynfe.entidades.emitente import Emitente
    from pynfe.entidades.cliente import Cliente
    from pynfe.processamento.assinatura import AssinaturaA1
    from pynfe.processamento.serializacao import SerializacaoXML
    from pynfe.processamento.comunicacao import ComunicacaoSefaz
    sucessos.append("Modulos principais do PyNFe importados com sucesso")
    
except ImportError as e:
    erros.append(f"PyNFe nao instalado: {e}")
    print("   [ERRO] PyNFe nao encontrado!")
    print("   Solucao: cd pynfe_dev && pip install -e .")

# ============================================================================
# 3. VERIFICAR nfce_pynfe
# ============================================================================
print("\n[3/8] Verificando modulo nfce_pynfe...")
try:
    from nfce_pynfe import NFCePyNFe, criar_servico_nfce_pynfe
    print("   [OK] Modulo nfce_pynfe encontrado")
    sucessos.append("Modulo nfce_pynfe disponivel")
    
    # Tentar criar instância
    try:
        nfce = criar_servico_nfce_pynfe()
        if nfce:
            sucessos.append("Servico NFCePyNFe pode ser instanciado")
        else:
            avisos.append("Servico NFCePyNFe retornou None")
    except Exception as e:
        erros.append(f"Erro ao criar servico: {e}")
        
except ImportError as e:
    erros.append(f"Modulo nfce_pynfe nao encontrado: {e}")
    print("   [ERRO] Arquivo nfce_pynfe.py nao encontrado!")

# ============================================================================
# 4. VERIFICAR DEPENDENCIAS
# ============================================================================
print("\n[4/8] Verificando dependencias...")
dependencias = {
    'lxml': 'lxml',
    'signxml': 'signxml',
    'requests': 'requests',
    'cryptography': 'cryptography',
    'pyOpenSSL': 'OpenSSL',
    'urllib3': 'urllib3',
    'decimal': 'decimal',
}

for nome_modulo, nome_import in dependencias.items():
    try:
        __import__(nome_import)
        sucessos.append(f"{nome_modulo} instalado")
    except ImportError:
        erros.append(f"{nome_modulo} nao instalado")
        print(f"   [ERRO] {nome_modulo} nao encontrado")

# ============================================================================
# 5. VERIFICAR IMPLEMENTACAO MANUAL (fallback)
# ============================================================================
print("\n[5/8] Verificando implementacao manual (fallback)...")
try:
    from nfce_manual_completo import NFCeManualCompleto
    print("   [OK] Implementacao manual disponivel")
    sucessos.append("Implementacao manual disponivel (para SP)")
except ImportError:
    avisos.append("Implementacao manual nao encontrada (necessaria para SP)")

# ============================================================================
# 6. VERIFICAR app.py (API Flask)
# ============================================================================
print("\n[6/8] Verificando app.py (API Flask)...")
app_path = Path(__file__).parent / "app.py"
if app_path.exists():
    print("   [OK] app.py encontrado")
    sucessos.append("app.py disponivel")
    
    # Verificar se tem Flask
    try:
        import flask
        sucessos.append("Flask instalado")
    except ImportError:
        erros.append("Flask nao instalado")
else:
    erros.append("app.py nao encontrado")

# ============================================================================
# 7. VERIFICAR ESTRUTURA DE DIRETORIOS
# ============================================================================
print("\n[7/8] Verificando estrutura de diretorios...")
diretorios_necessarios = [
    "pynfe_dev",
    "pynfe_dev/pynfe",
]

for dir_path in diretorios_necessarios:
    dir_full = Path(__file__).parent / dir_path
    if dir_full.exists():
        sucessos.append(f"Diretorio {dir_path} existe")
    else:
        avisos.append(f"Diretorio {dir_path} nao encontrado")

# ============================================================================
# 8. VERIFICAR ARQUIVOS DE CONFIGURACAO
# ============================================================================
print("\n[8/8] Verificando arquivos de configuracao...")
arquivos_uteis = [
    "requirements.txt",
    "requirements_manual.txt",
    "converter_certificado.py",
    "exemplo_rodar_pynfe.py",
]

for arquivo in arquivos_uteis:
    arquivo_path = Path(__file__).parent / arquivo
    if arquivo_path.exists():
        sucessos.append(f"Arquivo {arquivo} existe")
    else:
        avisos.append(f"Arquivo {arquivo} nao encontrado (opcional)")

# ============================================================================
# RESUMO
# ============================================================================
print("\n" + "=" * 70)
print("RESUMO DA VERIFICACAO")
print("=" * 70)

print(f"\n[SUCESSOS] {len(sucessos)} itens OK:")
for item in sucessos:
    print(f"  + {item}")

if avisos:
    print(f"\n[AVISOS] {len(avisos)} itens de atencao:")
    for item in avisos:
        print(f"  ! {item}")

if erros:
    print(f"\n[ERROS] {len(erros)} problemas encontrados:")
    for item in erros:
        print(f"  X {item}")

print("\n" + "=" * 70)

# ============================================================================
# STATUS FINAL
# ============================================================================
if erros:
    print("\n[STATUS] NAO PRONTO - Corrija os erros acima")
    print("\nComandos uteis:")
    print("  cd pynfe_dev")
    print("  pip install -e .")
    print("  pip install lxml signxml requests cryptography pyOpenSSL urllib3")
    sys.exit(1)
elif avisos:
    print("\n[STATUS] QUASE PRONTO - Alguns avisos, mas pode funcionar")
    print("\nRecomendacoes:")
    for aviso in avisos:
        print(f"  - {aviso}")
    sys.exit(0)
else:
    print("\n[STATUS] TUDO PRONTO! Pode emitir NFC-e")
    print("\nProximos passos:")
    print("  1. Configure o certificado digital")
    print("  2. Execute: python exemplo_rodar_pynfe.py")
    print("  3. Ou inicie a API: python app.py")
    sys.exit(0)

















