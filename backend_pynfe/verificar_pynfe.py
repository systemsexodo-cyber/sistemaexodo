#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Verificar se PyNFe está instalado"""

try:
    import pynfe
    print("✅ PyNFe está instalado!")
    if hasattr(pynfe, '__version__'):
        print(f"Versão: {pynfe.__version__}")
    else:
        print("Versão: desconhecida")
    exit(0)
except ImportError as e:
    print("❌ PyNFe NÃO está instalado")
    print(f"Erro: {e}")
    exit(1)


