"""
Script para testar se o app.py pode ser importado e iniciado
"""

import sys
import os

print("=" * 60)
print("Testando app.py")
print("=" * 60)

try:
    print("\n[1/3] Verificando imports básicos...")
    import flask
    print("✅ Flask OK")
    
    from flask_cors import CORS
    print("✅ Flask-CORS OK")
    
    print("\n[2/3] Tentando importar app...")
    import app
    print("✅ app.py importado com sucesso!")
    
    print("\n[3/3] Verificando se app Flask foi criado...")
    if hasattr(app, 'app'):
        print("✅ Flask app criado")
        print(f"✅ App name: {app.app.name}")
    else:
        print("⚠️ Flask app não encontrado no módulo app")
    
    print("\n" + "=" * 60)
    print("✅ TUDO OK! O app.py pode ser executado.")
    print("=" * 60)
    print("\nPara iniciar o servidor, execute:")
    print("  python app.py")
    print("\nOu use o script:")
    print("  start_local.bat")
    
except SyntaxError as e:
    print(f"\n❌ ERRO DE SINTAXE: {e}")
    print(f"   Arquivo: {e.filename}")
    print(f"   Linha: {e.lineno}")
    print(f"   Texto: {e.text}")
    sys.exit(1)
    
except ImportError as e:
    print(f"\n❌ ERRO DE IMPORTAÇÃO: {e}")
    print("\nInstale as dependências:")
    print("  pip install flask flask-cors python-dotenv")
    sys.exit(1)
    
except Exception as e:
    print(f"\n❌ ERRO: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)





