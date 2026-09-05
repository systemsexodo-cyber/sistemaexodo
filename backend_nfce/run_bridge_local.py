#!/usr/bin/env python3
"""
Script para executar o Bridge NFC-e localmente (modo desenvolvimento)
Não requer build - executa diretamente o código fonte Python
"""

import os
import sys
import subprocess
import argparse

# Adicionar caminhos necessários
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

def check_dependencies():
    """Verifica se as dependências estão instaladas"""
    required = ['uvicorn', 'fastapi', 'pynfe', 'requests', 'firebase_admin']
    missing = []
    
    for pkg in required:
        try:
            __import__(pkg.replace('-', '_'))
        except ImportError:
            missing.append(pkg)
    
    if missing:
        print(f"[ERRO] Dependências faltando: {', '.join(missing)}")
        print("\n[INFO] Instalando...")
        subprocess.check_call([sys.executable, '-m', 'pip', 'install'] + missing)
        print("[OK] Dependências instaladas!")
    else:
        print("[OK] Todas as dependências estão instaladas")

def run_bridge(port=8000, host='0.0.0.0', reload=False):
    """Executa o bridge em modo desenvolvimento"""
    print("-" * 50)
    print("           BRIDGE NFC-e - MODO DESENVOLVIMENTO")
    print("-" * 50)
    print(f"  URL: http://{host}:{port}")
    print(f"  Reload: {'Ativo' if reload else 'Inativo'}")
    print("-" * 50)
    
    try:
        import uvicorn
        uvicorn.run(
            "main:app",
            host=host,
            port=port,
            reload=reload,
            log_level="info"
        )
    except Exception as e:
        print(f"[ERRO] Erro ao iniciar bridge: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Bridge NFC-e - Modo Local')
    parser.add_argument('--port', '-p', type=int, default=8000, help='Porta (padrão: 8000)')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='Host (padrão: 0.0.0.0)')
    parser.add_argument('--reload', '-r', action='store_true', help='Ativar auto-reload')
    parser.add_argument('--check', '-c', action='store_true', help='Apenas verificar dependências')
    
    args = parser.parse_args()
    
    print("[TOOLS] Bridge NFC-e - Inicializador Local")
    print("=" * 50)
    
    # Verificar dependências
    check_dependencies()
    
    if args.check:
        print("\n[OK] Verificação completa!")
        return
    
    # Executar bridge
    print("\n[START] Iniciando Bridge...\n")
    run_bridge(port=args.port, host=args.host, reload=args.reload)

if __name__ == '__main__':
    main()
