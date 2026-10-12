# -*- coding: utf-8 -*-
"""Confere se o SincronizadorNuvem.exe levou os modulos que ele precisa.

Por que existe: um build sem `requests` e compilado SEM ERRO e so falha no PC
da loja, com um "Unhandled exception in script / No module named 'requests'" que
derruba a sincronizacao inteira. O erro nao aparece em nenhum log deste PC.

Em PyInstaller 6 o Pacote Python puro (requests, psycopg2, os proprios modulos
do sistema) fica dentro do arquivo PYZ embutido no .exe, e NAO na pasta
_internal - por isso conferir um arquivo em _internal nao serve.

Uso:  python verificar_sincronizador.py [caminho_do_exe]
Saia 0 quando tudo estiver la; 1 com a lista do que falta.
"""
import os
import sys
import tempfile

# Modulos sem os quais o executavel nao faz o trabalho dele.
MODULOS_OBRIGATORIOS = (
    'requests',            # API do Supabase (foi o que faltou no cliente)
    'psycopg2',            # banco local
    'dotenv',              # leitura do .env
    'sincronizador_lan',   # sincronizacao entre os PCs da mesma loja
    'sincronizar_local_supabase',  # o nucleo do sincronizador
    'setup_sync_local',
    'pystray',             # bandeja
    'PIL',                 # icone da bandeja
)

EXE_PADRAO = os.path.join('dist', 'SincronizadorNuvem',
                          'SincronizadorNuvem.exe')


def modulos_no_pyz(caminho_do_exe):
    """Nomes de modulo embutidos no PYZ do executavel PyInstaller."""
    from PyInstaller.archive.readers import CArchiveReader, ZlibArchiveReader

    ca = CArchiveReader(caminho_do_exe)
    if 'PYZ.pyz' not in ca.toc:
        raise RuntimeError('o executavel nao tem arquivo PYZ: %s' % caminho_do_exe)
    pyz = ca.extract('PYZ.pyz')

    direto = os.path.dirname(os.path.abspath(caminho_do_exe))
    arquivo = os.path.join(tempfile.mkdtemp(prefix='exodo_pyz_'), 'pyz.pyz')
    try:
        with open(arquivo, 'wb') as f:
            f.write(pyz)
        leitor = ZlibArchiveReader(arquivo)
        return set(getattr(leitor, 'toc', {}) or {})
    finally:
        try:
            os.remove(arquivo)
        except OSError:
            pass
        try:
            os.rmdir(os.path.dirname(arquivo))
        except OSError:
            pass


def main(argv):
    caminho = argv[1] if len(argv) > 1 else EXE_PADRAO
    if not os.path.exists(caminho):
        print('ERRO: executavel nao encontrado: %s' % caminho)
        return 2

    try:
        modulos = modulos_no_pyz(caminho)
    except Exception as e:
        print('ERRO: nao consegui ler os modulos de %s (%s)' % (caminho, e))
        return 2

    # Um modulo pode estar embutido como pacote (requests) ou como pacote com
    # sufixo (requests.__version__ tambem vira entrada). Basta existir o nome.
    faltando = [m for m in MODULOS_OBRIGATORIOS if m not in modulos]
    if faltando:
        print('ERRO: faltam modulos no %s:' % caminho)
        for m in faltando:
            print('   - %s' % m)
        print('Reinstale as dependencias (pip install requests) e compile de novo.')
        return 1

    print('OK: %d modulos embutidos; requests e os modulos do sistema presentes.'
          % len(modulos))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
