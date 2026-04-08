import 'package:flutter/material.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

enum AppThemeType {
  purple, // Midnight Purple (Default)
  ocean,  // Ocean Deep
  emerald, // Emerald Forest
  snow,   // Snow White (Light/Minimalist)
  sand,   // Sandstone (Light/Cream)
  diamond, // Diamond Blue (Deep Night)
  custom, // Empresa Default
}

class ThemeService extends ChangeNotifier {
  static const String _keyTheme = 'app_theme_type';
  final LocalStorageService _storage = LocalStorageService();
  
  AppThemeType _currentTheme = AppThemeType.purple;
  AppThemeType get currentTheme => _currentTheme;

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final themeStr = await _storage.carregar(_keyTheme);
    if (themeStr != null && themeStr is String) {
      _currentTheme = AppThemeType.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => AppThemeType.purple,
      );
      notifyListeners();
    }
  }

  Future<void> setTheme(AppThemeType type) async {
    _currentTheme = type;
    await _storage.salvar(_keyTheme, type.name);
    notifyListeners();
  }

  // Get colors and configuration based on theme type
  Map<String, dynamic> getThemeConfig(Color? empresaPrimaria, Color? empresaSecundaria) {
    switch (_currentTheme) {
      case AppThemeType.purple:
        return {
          'primaria': const Color(0xFF6200EE),
          'secundaria': const Color(0xFF9575CD),
          'fundo': const Color(0xFF0F0E17),
          'brightness': Brightness.dark,
        };
      case AppThemeType.ocean:
        return {
          'primaria': const Color(0xFF00BFA5),
          'secundaria': const Color(0xFF01579B),
          'fundo': const Color(0xFF010B13),
          'brightness': Brightness.dark,
        };
      case AppThemeType.emerald:
        return {
          'primaria': const Color(0xFF43A047),
          'secundaria': const Color(0xFFC0CA33),
          'fundo': const Color(0xFF0A140B),
          'brightness': Brightness.dark,
        };
      case AppThemeType.snow:
        return {
          'primaria': const Color(0xFF2196F3),
          'secundaria': const Color(0xFF64B5F6),
          'fundo': const Color(0xFFF8F9FA),
          'brightness': Brightness.light,
        };
      case AppThemeType.sand:
        return {
          'primaria': const Color(0xFF795548),
          'secundaria': const Color(0xFFA1887F),
          'fundo': const Color(0xFFF5F5F0),
          'brightness': Brightness.light,
        };
      case AppThemeType.diamond:
        return {
          'primaria': const Color(0xFF1976D2),
          'secundaria': const Color(0xFF0D47A1),
          'fundo': const Color(0xFF010A1A),
          'brightness': Brightness.dark,
        };
      case AppThemeType.custom:
        return {
          'primaria': empresaPrimaria ?? const Color(0xFF2196F3),
          'secundaria': empresaSecundaria ?? const Color(0xFF1565C0),
          'fundo': const Color(0xFF10151B),
          'brightness': Brightness.dark,
        };
    }
  }

  String getThemeName(AppThemeType type) {
    switch (type) {
      case AppThemeType.purple: return 'Midnight Purple';
      case AppThemeType.ocean: return 'Ocean Deep';
      case AppThemeType.emerald: return 'Emerald Forest';
      case AppThemeType.snow: return 'Snow White';
      case AppThemeType.sand: return 'Sandstone';
      case AppThemeType.diamond: return 'Diamond Blue';
      case AppThemeType.custom: return 'Empresa Default';
    }
  }

  IconData getThemeIcon(AppThemeType type) {
    switch (type) {
      case AppThemeType.purple: return Icons.auto_awesome;
      case AppThemeType.ocean: return Icons.waves;
      case AppThemeType.emerald: return Icons.forest;
      case AppThemeType.snow: return Icons.ac_unit_rounded;
      case AppThemeType.sand: return Icons.grain_rounded;
      case AppThemeType.diamond: return Icons.diamond_rounded;
      case AppThemeType.custom: return Icons.business;
    }
  }
}
