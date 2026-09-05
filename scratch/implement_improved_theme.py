import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\theme.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Atualizar o getTheme geral para garantir alto contraste nos cards, campos de texto e fontes ---
target_get_theme = """  static ThemeData getTheme({Color? corPrimaria, Color? corSecundaria, Color? corFundo, Brightness brightness = Brightness.dark}) {
    final primary = corPrimaria ?? const Color(0xFF2196F3);
    final secondary = corSecundaria ?? const Color(0xFF1565C0);
    final background = corFundo ?? (brightness == Brightness.dark ? const Color(0xFF10151B) : Colors.white);
    
    final isDark = brightness == Brightness.dark;
    
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: background,
      onSurface: isDark ? Colors.white : Colors.black87,
      background: background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: background,
        elevation: 6,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF23272A) : Colors.grey.shade100,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
        bodyColor: isDark ? Colors.white : Colors.black87,
        displayColor: isDark ? Colors.white : Colors.black87,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
    );
  }"""

# Melhorando GetTheme:
# - Cards no Dark Mode usam uma cor de superfície sólida e bem escura com boa leitura
# - Letras brancas puras no Dark Mode
# - Bordas visíveis
replacement_get_theme = """  static ThemeData getTheme({Color? corPrimaria, Color? corSecundaria, Color? corFundo, Brightness brightness = Brightness.dark}) {
    final primary = corPrimaria ?? const Color(0xFF2196F3);
    final secondary = corSecundaria ?? const Color(0xFF1565C0);
    final background = corFundo ?? (brightness == Brightness.dark ? const Color(0xFF0F1319) : Colors.white);
    
    final isDark = brightness == Brightness.dark;
    
    // Cor de card escuro para alto contraste
    final cardBg = isDark ? const Color(0xFF1A1F26) : Colors.white;
    
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: cardBg,
      onSurface: isDark ? Colors.white : Colors.black87,
      background: background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
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
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF15191E) : Colors.grey.shade100,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black38),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
        bodyColor: isDark ? Colors.white : Colors.black87,
        displayColor: isDark ? Colors.white : Colors.black87,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
    );
  }"""

if target_get_theme in content:
    content = content.replace(target_get_theme, replacement_get_theme)
    print("GET_THEME_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_get_theme.replace("\r\n", "\n")
    normalized_replacement = replacement_get_theme.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("GET_THEME_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_GET_THEME")


# --- 2. Atualizar o darkTheme para herdar o getTheme com cores otimizadas ---
target_dark_theme = """  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF42A5F5),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withAlpha((0.06 * 255).toInt()),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white.withAlpha((0.04 * 255).toInt()),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2196F3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }"""

replacement_dark_theme = """  static ThemeData get darkTheme => getTheme(
        corPrimaria: const Color(0xFF2196F3),
        corSecundaria: const Color(0xFF1565C0),
        corFundo: const Color(0xFF0F1319),
        brightness: Brightness.dark,
      );"""

if target_dark_theme in content:
    content = content.replace(target_dark_theme, replacement_dark_theme)
    print("DARK_THEME_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_dark_theme.replace("\r\n", "\n")
    normalized_replacement = replacement_dark_theme.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("DARK_THEME_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_DARK_THEME")


# --- 3. Atualizar a lógica do appBackground para garantir fundos escuros de alto contraste e sem poluição visual ---
target_background = """        // Usar cores da empresa ou cores padrão
        final primariaFinal = primaria ?? const Color(0xFF0D47A1);
        final secundariaFinal = secundaria ?? const Color(0xFF1976D2);
        
        // Criar variações mais escuras para o gradiente
        Color darken(Color color, double amount) {
          assert(amount >= 0 && amount <= 1);
          final hsl = HSLColor.fromColor(color);
          final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
          return hslDark.toColor();
        }
        
        final cor1 = darken(primariaFinal, 0.3);
        final cor2 = primariaFinal;
        final cor3 = secundariaFinal;

        return SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  fundo ?? cor1,
                  cor2,
                  cor3,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),"""

# Se o tema for escuro, o gradiente vai do fundo escuro daquele tema (ex: 0xFF0F0E17, 0xFF010A1A, etc.)
# até uma versão extremamente escura da cor primária e secundária (90% de darken!), mantendo a legibilidade 100% perfeita.
replacement_background = """        // Usar cores da empresa ou cores padrão
        final primariaFinal = primaria ?? const Color(0xFF0D47A1);
        final secundariaFinal = secundaria ?? const Color(0xFF1976D2);
        
        final isDark = themeService.getThemeConfig(primaria, secundaria)['brightness'] == Brightness.dark;
        
        // Criar variações escuras para o gradiente de fundo
        Color darken(Color color, double amount) {
          assert(amount >= 0 && amount <= 1);
          final hsl = HSLColor.fromColor(color);
          final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
          return hslDark.toColor();
        }
        
        // Se for tema escuro, garantimos um fundo super escuro (grafite/preto) com apenas um sutil reflexo da cor primaria
        final corFundoFinal = fundo ?? (isDark ? const Color(0xFF0D0F13) : const Color(0xFFF8F9FA));
        final cor1 = isDark ? corFundoFinal : const Color(0xFFF8F9FA);
        final cor2 = isDark ? darken(primariaFinal, 0.45) : const Color(0xFFF1F5F9);
        final cor3 = isDark ? darken(secundariaFinal, 0.50) : const Color(0xFFE2E8F0);

        return SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cor1,
                  cor2,
                  cor3,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.6, 1.0],
              ),
            ),"""

if target_background in content:
    content = content.replace(target_background, replacement_background)
    print("APP_BACKGROUND_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_background.replace("\r\n", "\n")
    normalized_replacement = replacement_background.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("APP_BACKGROUND_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_APP_BACKGROUND")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
