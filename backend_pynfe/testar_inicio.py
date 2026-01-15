#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Testar se o servidor pode iniciar"""

import sys
import traceback

print("=" * 50)
print("TESTE DE INICIALIZACAO DO SERVIDOR")
print("=" * 50)
print()

# Testar imports básicos
print("1. Testando imports básicos...")
try:
    from flask import Flask
    from flask_cors import CORS
    print("   ✅ Flask e CORS OK")
except Exception as e:
    print(f"   ❌ Erro ao importar Flask: {e}")
    sys.exit(1)

# Testar import do app
print()
print("2. Testando import do app.py...")
try:
    import app
    print("   ✅ app.py importado com sucesso")
except Exception as e:
    print(f"   ❌ Erro ao importar app.py: {e}")
    print()
    print("Detalhes do erro:")
    traceback.print_exc()
    sys.exit(1)

# Testar import dos serviços
print()
print("3. Testando import dos serviços...")
try:
    from services.nfce_service import NFCeService
    print("   ✅ NFCeService OK")
except ImportError as e:
    print(f"   ⚠️ NFCeService não disponível: {e}")
    print("   (Servidor pode rodar sem ele)")

try:
    from services.certificado_service import CertificadoService
    print("   ✅ CertificadoService OK")
except ImportError as e:
    print(f"   ⚠️ CertificadoService não disponível: {e}")
    print("   (Servidor pode rodar sem ele)")

# Testar criação do app Flask
print()
print("4. Testando criação do app Flask...")
try:
    test_app = Flask(__name__)
    CORS(test_app)
    print("   ✅ App Flask criado com sucesso")
except Exception as e:
    print(f"   ❌ Erro ao criar app Flask: {e}")
    sys.exit(1)

print()
print("=" * 50)
print("✅ TODOS OS TESTES PASSARAM!")
print("=" * 50)
print()
print("O servidor deve conseguir iniciar.")
print("Execute: python app.py")
print()


