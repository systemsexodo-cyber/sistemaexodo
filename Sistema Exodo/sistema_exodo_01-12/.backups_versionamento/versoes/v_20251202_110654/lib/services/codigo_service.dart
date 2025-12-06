/// Serviço para geração inteligente de códigos de produtos
/// - Segue sequência numérica
/// - Detecta e preenche furos (gaps)
/// - Formato: COD-1, COD-2, etc (sem zeros à esquerda)
class CodigoService {
  static const String _prefix = 'COD-';

  /// Gera o próximo código inteligente
  /// Analisa códigos existentes e:
  /// 1. Preenche furos (gaps) primeiro
  /// 2. Se não há furos, usa o próximo sequencial após o MAIOR código
  static String gerarProximoCodigo(List<String?> codigosExistentes) {
    // Filtrar códigos nulos e vazios
    final codigosValidos = codigosExistentes
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toList();

    if (codigosValidos.isEmpty) {
      return '${_prefix}1';
    }

    // Extrair números dos códigos existentes
    final numeros = <int>[];
    for (final codigo in codigosValidos) {
      final match = RegExp(r'COD-(\d+)').firstMatch(codigo);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!);
        if (numero != null) {
          numeros.add(numero);
        }
      }
    }

    if (numeros.isEmpty) {
      return '${_prefix}1';
    }

    numeros.sort();

    final maiorNumero = numeros.last;

    // Procurar pelo primeiro furo (gap) apenas ATÉ O MAIOR NÚMERO
    for (int i = 1; i < maiorNumero; i++) {
      if (!numeros.contains(i)) {
        // Encontrou um furo - preenche
        return '$_prefix$i';
      }
    }

    // Se não há furos, usa o PRÓXIMO número APÓS O MAIOR
    final proximoNumero = maiorNumero + 1;
    return '$_prefix$proximoNumero';
  }

  /// Gera o PRÓXIMO código sequencial APÓS O ÚLTIMO
  /// Pula todos os furos e vai diretamente para o próximo do maior
  static String gerarProximoUltimo(List<String?> codigosExistentes) {
    // Filtrar códigos nulos e vazios
    final codigosValidos = codigosExistentes
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toList();

    if (codigosValidos.isEmpty) {
      return '${_prefix}1';
    }

    // Extrair números dos códigos existentes
    final numeros = <int>[];
    for (final codigo in codigosValidos) {
      final match = RegExp(r'COD-(\d+)').firstMatch(codigo);
      if (match != null) {
        final numero = int.tryParse(match.group(1)!);
        if (numero != null) {
          numeros.add(numero);
        }
      }
    }

    if (numeros.isEmpty) {
      return '${_prefix}1';
    }

    numeros.sort();
    final maiorNumero = numeros.last;

    // Vai direto para o próximo do maior (sem preencher furos)
    final proximoNumero = maiorNumero + 1;
    return '$_prefix$proximoNumero';
  }

  /// Valida se um código segue o formato correto
  static bool isCodigoValido(String codigo) {
    return RegExp(r'^COD-\d+$').hasMatch(codigo);
  }

  /// Extrai o número do código
  static int? extrairNumero(String codigo) {
    final match = RegExp(r'COD-(\d+)').firstMatch(codigo);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
