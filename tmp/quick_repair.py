
import os

path = r'C:\Users\USER\.gemini\antigravity\sistema_exodo_01-12\backend_nfce\nfce_handler.py'

with open(path, 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

# 1. Restaurar a classe ComunicacaoSefaz
print("Restaurando classe ComunicacaoSefaz...")
if 'class ComunicacaoSefaz' not in text:
    # Insere antes de _fixed_post
    text = text.replace('def _fixed_post(', 'class ComunicacaoSefaz(ComunicacaoSefaz):\n    def _fixed_post(')
    # Nota: O nome da classe base OriginalComunicacaoSefaz deve ser importado
    if 'from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz' not in text:
        text = "from pynfe.processamento.comunicacao import ComunicacaoSefaz as OriginalComunicacaoSefaz\n" + text
        text = text.replace('class ComunicacaoSefaz(ComunicacaoSefaz):', 'class ComunicacaoSefaz(OriginalComunicacaoSefaz):')

# 2. Corrigir indentação do _fixed_post (e garantir que o corpo esteja indentado)
# Se o split falhou e deixou a função sem indentação correta em relação ao NOVO header da classe
# Na verdade, se eu inseri o class line antes, o def já tem alguns espaços.

# 3. Corrigir o SyntaxError do return no final
print("Corrigindo return em cancelar_nfce_pynfe...")
bad_return = "\nreturn {'success': False, 'error': f'Erro interno: {str(e)}', 'traceback': traceback.format_exc()}"
good_return = "\n        return {'success': False, 'error': f'Erro interno: {str(e)}', 'traceback': traceback.format_exc()}"
if bad_return in text:
    text = text.replace(bad_return, good_return)

# 4. Corrigir o finally vazio em _fixed_post
print("Corrigindo finally em _fixed_post...")
if 'finally:\n        pass' in text:
    text = text.replace('finally:\n        pass', 'finally:\n            certificado_a1.excluir()')

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)
print("Correcoes aplicadas.")
