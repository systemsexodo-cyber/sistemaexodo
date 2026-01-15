#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Verificação completa do PyNFe"""

import sys

print("=" * 50)
print("VERIFICAÇÃO COMPLETA DO PyNFe")
print("=" * 50)
print()

# 1. Verificar import básico
print("1. Testando import básico...")
try:
    import pynfe
    print(f"   ✅ PyNFe importado com sucesso!")
    print(f"   📍 Localização: {pynfe.__file__}")
    if hasattr(pynfe, '__version__'):
        print(f"   📦 Versão: {pynfe.__version__}")
except ImportError as e:
    print(f"   ❌ PyNFe NÃO está instalado!")
    print(f"   Erro: {e}")
    sys.exit(1)

print()

# 2. Verificar módulos específicos
print("2. Testando módulos específicos...")
modulos = [
    'pynfe.processamento.comunicacao',
    'pynfe.processamento.serializacao',
    'pynfe.processamento.assinatura',
    'pynfe.entidades.emitente',
    'pynfe.entidades.cliente',
    'pynfe.entidades.produto',
    'pynfe.entidades.notafiscal',
    'pynfe.entidades.pagamento',
]

todos_ok = True
for modulo in modulos:
    try:
        __import__(modulo)
        print(f"   ✅ {modulo}")
    except ImportError as e:
        print(f"   ❌ {modulo} - Erro: {e}")
        todos_ok = False

print()

# 3. Resultado final
if todos_ok:
    print("=" * 50)
    print("✅ PyNFe ESTÁ INSTALADO E FUNCIONANDO!")
    print("=" * 50)
    print()
    print("O servidor deve detectar o PyNFe corretamente.")
    print("Se ainda aparecer erro, REINICIE o servidor.")
else:
    print("=" * 50)
    print("⚠️ PyNFe está instalado mas há módulos faltando")
    print("=" * 50)
    print()
    print("Tente reinstalar:")
    print("  pip install --force-reinstall git+https://github.com/TadaSoftware/PyNFe.git")


