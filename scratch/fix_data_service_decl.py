import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\services\data_service.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Restaurar a variável privada _caixaAberto ao lado de responsavelAtivo
target = """  // Controle de caixa
  String? responsavelAtivo;
  bool get caixaAberto => aberturaCaixaAtual != null;"""

replacement = """  // Controle de caixa
  String? responsavelAtivo;
  bool _caixaAberto = false; // Mantida para compatibilidade interna e escrita
  bool get caixaAberto => aberturaCaixaAtual != null; // Getter dinâmico por operador"""

if target in content:
    content = content.replace(target, replacement)
    print("DECLARACAO_RESTAURADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DECLARACAO_NORMALIZADA")
    else:
        print("FALHA_AO_RESTAURAR_DECLARACAO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
