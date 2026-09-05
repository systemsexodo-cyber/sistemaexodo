import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\theme.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target = """      cardTheme: CardThemeData(
        color: cardBg,
        elevation: isDark ? 8 : 4,
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),"""

replacement = """      cardTheme: CardThemeData(
        color: cardBg,
        elevation: isDark ? 8 : 4,
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),"""

if target in content:
    content = content.replace(target, replacement)
    print("BORDA_CARD_CORRIGIDA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target.replace("\r\n", "\n")
    normalized_replacement = replacement.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("BORDA_CARD_NORMALIZADA")
    else:
        print("FALHA_AO_CORRIGIR_BORDA_CARD")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
