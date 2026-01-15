import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciar numeração sequencial de NFC-e
class NumeroNFCeService {
  static const String _keyNumeroAtual = 'nfce_numero_atual';
  static const String _keySerie = 'nfce_serie';
  static const String _keyEmpresaId = 'nfce_empresa_id';

  /// Obtém o próximo número da NFC-e para uma empresa
  static Future<String> obterProximoNumero(String empresaId, {String serie = '1'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Verificar se é a mesma empresa
      final empresaIdSalva = prefs.getString(_keyEmpresaId);
      final serieSalva = prefs.getString(_keySerie);
      
      // Se mudou empresa ou série, resetar contador
      if (empresaIdSalva != empresaId || serieSalva != serie) {
        await prefs.setString(_keyEmpresaId, empresaId);
        await prefs.setString(_keySerie, serie);
        await prefs.setInt(_keyNumeroAtual, 1);
        return '1';
      }

      // Obter número atual
      final numeroAtual = prefs.getInt(_keyNumeroAtual) ?? 1;
      
      // Incrementar e salvar
      final proximoNumero = numeroAtual + 1;
      await prefs.setInt(_keyNumeroAtual, proximoNumero);

      return proximoNumero.toString();
    } catch (e) {
      throw Exception('Erro ao obter próximo número da NFC-e: $e');
    }
  }

  /// Define o número atual da NFC-e (útil para sincronização)
  static Future<void> definirNumeroAtual(
    String empresaId,
    String serie,
    int numero,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEmpresaId, empresaId);
      await prefs.setString(_keySerie, serie);
      await prefs.setInt(_keyNumeroAtual, numero);
    } catch (e) {
      throw Exception('Erro ao definir número atual da NFC-e: $e');
    }
  }

  /// Obtém o número atual sem incrementar
  static Future<int> obterNumeroAtual(String empresaId, String serie) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final empresaIdSalva = prefs.getString(_keyEmpresaId);
      final serieSalva = prefs.getString(_keySerie);

      if (empresaIdSalva == empresaId && serieSalva == serie) {
        return prefs.getInt(_keyNumeroAtual) ?? 1;
      }

      return 1;
    } catch (e) {
      return 1;
    }
  }

  /// Reseta a numeração (útil para testes)
  static Future<void> resetarNumero(String empresaId, String serie) async {
    await definirNumeroAtual(empresaId, serie, 1);
  }
}

