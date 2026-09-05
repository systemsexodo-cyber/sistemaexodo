import 'package:intl/intl.dart';
import 'local_storage_service.dart';
import '../models/empresa.dart';

class SenhaPedidoService {
  static final LocalStorageService _storage = LocalStorageService();

  static const String keyUltimaDataSenha = 'exodo_senha_pedido_ultima_data';
  static const String keyUltimoNumeroSenha = 'exodo_senha_pedido_ultimo_numero';

  /// Gera a próxima senha com base nas configurações da empresa
  static Future<String?> gerarProximaSenha(Empresa? empresa) async {
    if (empresa == null) return null;
    
    final config = empresa.configuracoes ?? {};
    final bool habilitado = config['senhaPedidoHabilitado'] == true;
    if (!habilitado) return null;

    final String prefixo = config['senhaPedidoPrefixo']?.toString() ?? '';
    final String formato = config['senhaPedidoFormato']?.toString() ?? 'somente_numeros';
    final bool reiniciarDiario = config['senhaPedidoReiniciarDiario'] != false;

    // Obter data atual formatada (yyyy-MM-dd)
    final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Obter última data e número gerados
    final ultimaData = await _storage.carregar(keyUltimaDataSenha) as String? ?? '';
    int ultimoNumero = 0;
    
    final numVal = await _storage.carregar(keyUltimoNumeroSenha);
    if (numVal != null) {
      ultimoNumero = int.tryParse(numVal.toString()) ?? 0;
    }

    int novoNumero = ultimoNumero + 1;

    // Reiniciar diariamente se configurado
    if (reiniciarDiario && ultimaData != hoje) {
      novoNumero = 1;
    }

    // Salvar novos valores
    await _storage.salvar(keyUltimaDataSenha, hoje);
    await _storage.salvar(keyUltimoNumeroSenha, novoNumero);

    // Formatar número
    String numeroFormatado;
    if (formato == '2_digitos') {
      numeroFormatado = novoNumero.toString().padLeft(2, '0');
    } else if (formato == '3_digitos') {
      numeroFormatado = novoNumero.toString().padLeft(3, '0');
    } else {
      // somente_numeros
      numeroFormatado = novoNumero.toString();
    }

    return '$prefixo$numeroFormatado';
  }
}
