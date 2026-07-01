"""
Script para debugar o erro de tempfile
"""
import sys
import os
import traceback

print("=" * 60)
print("DEBUG: Testando importação do nfce_handler")
print("=" * 60)

try:
    from nfce_handler import emitir_nfce_pynfe
    print("[OK] Importação bem-sucedida!")
except Exception as e:
    print(f"[ERRO] Falha na importação: {e}")
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 60)
print("DEBUG: Verificando disponibilidade do módulo tempfile")
print("=" * 60)

try:
    import tempfile
    print(f"[OK] tempfile importado!")
    print(f"  - gettempdir: {hasattr(tempfile, 'gettempdir')}")
    print(f"  - NamedTemporaryFile: {hasattr(tempfile, 'NamedTemporaryFile')}")
    print(f"  - gettempdir(): {tempfile.gettempdir()}")
except Exception as e:
    print(f"[ERRO] Falha com tempfile: {e}")
    traceback.print_exc()

print("\n" + "=" * 60)
print("DEBUG: Verificando módulo pynfe")
print("=" * 60)

try:
    from pynfe.entidades.certificado import CertificadoA1
    print("[OK] CertificadoA1 importado!")
    
    # Verificar se o método separar_arquivo existe
    if hasattr(CertificadoA1, 'separar_arquivo'):
        print("[OK] Método separar_arquivo existe!")
        import inspect
        source = inspect.getsource(CertificadoA1.separar_arquivo)
        if 'tempfile' in source:
            print("[AVISO] O método ainda usa 'tempfile'!")
        else:
            print("[OK] O método não usa mais 'tempfile'")
    else:
        print("[ERRO] Método separar_arquivo NÃO existe!")
except Exception as e:
    print(f"[ERRO] Falha com pynfe: {e}")
    traceback.print_exc()

print("\n" + "=" * 60)
print("Teste concluído!")
print("=" * 60)
