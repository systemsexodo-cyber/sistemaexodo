import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\theme.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """        // Se for tema escuro, garantimos um fundo super escuro (grafite/preto) com apenas um sutil reflexo da cor primaria
        final corFundoFinal = fundo ?? (isDark ? const Color(0xFF0D0F13) : const Color(0xFFF8F9FA));
        final cor1 = isDark ? corFundoFinal : const Color(0xFFF8F9FA);
        final cor2 = isDark ? darken(primariaFinal, 0.45) : const Color(0xFFF1F5F9);
        final cor3 = isDark ? darken(secundariaFinal, 0.50) : const Color(0xFFE2E8F0);"""

replacement = """        // Se for tema escuro, o fundo herda a cor de fundo rica daquele tema, 
        // e as outras pontas do gradiente ganham a cor primária/secundária real atenuada sutilmente (22-26%),
        // mantendo a identidade e variedade de cores viva em cada tema!
        final corFundoFinal = fundo ?? (isDark ? const Color(0xFF0D0F13) : const Color(0xFFF8F9FA));
        final cor1 = corFundoFinal;
        final cor2 = isDark ? darken(primariaFinal, 0.22) : const Color(0xFFF1F5F9);
        final cor3 = isDark ? darken(secundariaFinal, 0.26) : const Color(0xFFE2E8F0);"""

if target in content:
    content = content.replace(target, replacement)
    print("RIQUEZA_CORES_TEMA_ATUALIZADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("RIQUEZA_CORES_TEMA_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_RIQUEZA_CORES_TEMA")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
