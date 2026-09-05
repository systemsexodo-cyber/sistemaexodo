import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

/// Serviço para gerenciar numeração sequencial de NFC-e
/// 
/// Desktop: Salva no PostgreSQL via DatabaseService
/// Web: Mantém SharedPreferences (não há PostgreSQL no browser)
class NumeroNFCeService {
  static const String _prefixKey = 'nfce_numero_';

  /// Obtém o próximo número da NFC-e para uma empresa
  static Future<String> obterProximoNumero(String empresaId, {String serie = '1'}) async {
    try {
      if (kIsWeb) {
        return await _obterProximoNumeroWeb(empresaId, serie);
      }

      // Desktop: usar PostgreSQL
      final chave = '$_prefixKey${empresaId}_$serie';
      final db = DatabaseService();
      
      final valor = await db.carregarConfig(chave);
      int numeroAtual = 1;
      if (valor != null) {
        if (valor is int) {
          numeroAtual = valor;
        } else if (valor is String) {
          numeroAtual = int.tryParse(valor) ?? 1;
        }
      }
      
      final proximoNumero = numeroAtual + 1;
      await db.salvarConfig(chave, proximoNumero);
      debugPrint('>>> [NFCeNumero] ✅ $numeroAtual -> $proximoNumero (PG, empresa: $empresaId)');

      return proximoNumero.toString();
    } catch (e) {
      debugPrint('>>> [NFCeNumero] ❌ Erro: $e');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  /// Web: SharedPreferences (comportamento original)
  static Future<String> _obterProximoNumeroWeb(String empresaId, String serie) async {
    final prefs = await SharedPreferences.getInstance();
    final empresaIdSalva = prefs.getString('nfce_empresa_id');
    final serieSalva = prefs.getString('nfce_serie');
    
    if (empresaIdSalva != empresaId || serieSalva != serie) {
      await prefs.setString('nfce_empresa_id', empresaId);
      await prefs.setString('nfce_serie', serie);
      await prefs.setInt('nfce_numero_atual', 1);
      return '1';
    }

    final numeroAtual = prefs.getInt('nfce_numero_atual') ?? 1;
    final proximoNumero = numeroAtual + 1;
    await prefs.setInt('nfce_numero_atual', proximoNumero);
    return proximoNumero.toString();
  }

  /// Define o número atual da NFC-e (útil para sincronização)
  static Future<void> definirNumeroAtual(
    String empresaId,
    String serie,
    int numero,
  ) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nfce_empresa_id', empresaId);
        await prefs.setString('nfce_serie', serie);
        await prefs.setInt('nfce_numero_atual', numero);
        return;
      }

      final chave = '$_prefixKey${empresaId}_$serie';
      await DatabaseService().salvarConfig(chave, numero);
      debugPrint('>>> [NFCeNumero] ✅ Número definido: $numero (PG, empresa: $empresaId)');
    } catch (e) {
      debugPrint('>>> [NFCeNumero] ❌ Erro ao definir: $e');
    }
  }

  /// Obtém o número atual sem incrementar
  static Future<int> obterNumeroAtual(String empresaId, String serie) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final empresaIdSalva = prefs.getString('nfce_empresa_id');
        final serieSalva = prefs.getString('nfce_serie');
        if (empresaIdSalva == empresaId && serieSalva == serie) {
          return prefs.getInt('nfce_numero_atual') ?? 1;
        }
        return 1;
      }

      final chave = '$_prefixKey${empresaId}_$serie';
      final valor = await DatabaseService().carregarConfig(chave);
      if (valor != null) {
        if (valor is int) return valor;
        if (valor is String) return int.tryParse(valor) ?? 1;
      }
      return 1;
    } catch (e) {
      debugPrint('>>> [NFCeNumero] ❌ Erro ao ler: $e');
      return 1;
    }
  }

  /// Reseta a numeração (útil para testes)
  static Future<void> resetarNumero(String empresaId, String serie) async {
    await definirNumeroAtual(empresaId, serie, 1);
  }
}
