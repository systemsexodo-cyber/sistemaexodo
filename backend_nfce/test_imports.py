"""
Testar todas as importações usadas pelo nfce_handler
"""
import sys
import os
import traceback

modules_to_test = [
    'decimal',
    'base64',
    'os',
    're',
    'traceback',
    'datetime',
    'lxml.etree',
    'pynfe.processamento.comunicacao',
    'pynfe.entidades.certificado',
    'pynfe.entidades.cliente',
    'pynfe.entidades.emitente',
    'pynfe.entidades.notafiscal',
    'pynfe.entidades.transportadora',
    'pynfe.utils',
    'pynfe.utils.etree',
    'pynfe.processamento.serializacao',
    'requests',
    'json',
    'uuid',
    'signxml',
    'tempfile',
    'cryptography.hazmat.primitives.serialization',
]

print("=" * 70)
print("Testando importações")
print("=" * 70)

for mod in modules_to_test:
    try:
        __import__(mod)
        print(f"[OK] {mod}")
    except Exception as e:
        print(f"[ERRO] {mod}: {e}")
        traceback.print_exc()

print("\n" + "=" * 70)
print("Teste de importações concluído")
print("=" * 70)
