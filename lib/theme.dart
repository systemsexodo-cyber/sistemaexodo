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
  }

  static ThemeData get lightTheme => getTheme();

  static ThemeData get darkTheme {
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
  }

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
  
  /// Obtém cores da empresa a partir de strings hex
  static Map<String, Color?> getCoresEmpresa(String? corPrimariaHex, String? corSecundariaHex) {
    return {
      'primaria': _hexToColor(corPrimariaHex),
      'secundaria': _hexToColor(corSecundariaHex),
    };
  }
}
