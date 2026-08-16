import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';

class AppTheme {
  /// Converte hex string para Color
  static Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final hexCode = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexCode', radix: 16));
    } catch (e) {
      return null;
    }
  }

  static ThemeData getTheme({Color? corPrimaria, Color? corSecundaria, Color? corFundo, Brightness brightness = Brightness.dark}) {
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
          side: BorderSide(
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
  }

  static ThemeData get lightTheme => getTheme();

  static ThemeData get darkTheme => getTheme(
        corPrimaria: const Color(0xFF2196F3),
        corSecundaria: const Color(0xFF1565C0),
        corFundo: const Color(0xFF0F1319),
        brightness: Brightness.dark,
      );

  // Widget that provides a glossy blue gradient background and places
  // the application's scaffold on top so all screens share the background.
  static Widget appBackground({
    required Widget child,
    Color? corPrimaria,
    Color? corSecundaria,
    Color? corFundo,
  }) {
    return Consumer2<AuthService, ThemeService>(
      builder: (context, authService, themeService, _) {
        // Obter cores da empresa atual se não foram fornecidas
        Color? primaria = corPrimaria;
        Color? secundaria = corSecundaria;
        Color? fundo = corFundo;
        
        if (primaria == null || secundaria == null) {
          final empresa = authService.empresaAtual;
          final coresEmpresa = getCoresEmpresa(
            empresa?.corPrimaria,
            empresa?.corSecundaria,
          );
          
          final config = themeService.getThemeConfig(
            coresEmpresa['primaria'],
            coresEmpresa['secundaria'],
          );
          
          primaria ??= config['primaria'] as Color?;
          secundaria ??= config['secundaria'] as Color?;
          fundo ??= config['fundo'] as Color?;
        }
        
        // Usar cores da empresa ou cores padrão
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
        
        // Se for tema escuro, o fundo herda a cor de fundo rica daquele tema, 
        // e as outras pontas do gradiente ganham a cor primária/secundária real atenuada sutilmente (22-26%),
        // mantendo a identidade e variedade de cores viva em cada tema!
        final corFundoFinal = fundo ?? (isDark ? const Color(0xFF0D0F13) : const Color(0xFFF8F9FA));
        final cor1 = corFundoFinal;
        final cor2 = isDark ? darken(primariaFinal, 0.22) : const Color(0xFFF1F5F9);
        final cor3 = isDark ? darken(secundariaFinal, 0.26) : const Color(0xFFE2E8F0);

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
            ),
            child: Stack(
              children: [
                // Fênix suave ao fundo (watermark) - Lado Direito Inferior
                  Positioned(
                    right: -150,
                    bottom: -100,
                    child: Opacity(
                      opacity: 0.008, // Quase invisível
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Image.asset(
                          'assets/images/phoenix.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -50,
                    top: 100,
                    child: Opacity(
                      opacity: 0.004, // Ainda mais discreta
                      child: Transform.rotate(
                        angle: 0.4,
                        child: Image.asset(
                          'assets/images/phoenix.png',
                          width: 400,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                Scaffold(
                  backgroundColor: Colors.transparent,
                  body: SafeArea(
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  static Map<String, Color?> getCoresEmpresa(String? corPrimariaHex, String? corSecundariaHex) {
    return {
      'primaria': _hexToColor(corPrimariaHex),
      'secundaria': _hexToColor(corSecundariaHex),
    };
  }

  static InputDecoration inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: Colors.white70) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
    );
  }
}


class ExodoTheme {
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color surfaceColor = Color(0xFF1E1E2E);
  static const Color backgroundColor = Color(0xFF0F1319);
}
