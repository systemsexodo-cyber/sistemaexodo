/// Serviço para geração de números de pedido sequenciais
class PedidoService {
  /// Gera o próximo número de pedido no formato PED-0001, PED-0002, etc.
  /// Preenche lacunas se houver números faltando na sequência.
  static String gerarProximoNumeroPedido(List<String> numerosExistentes) {
    // Extrai apenas os números dos códigos existentes
    final numeros = <int>[];

    for (final numero in numerosExistentes) {
      if (numero.isEmpty) continue;

      // Tenta extrair o número do formato PED-XXXX
      final match = RegExp(r'PED-(\d+)').firstMatch(numero);
      if (match != null) {
        final num = int.tryParse(match.group(1)!);
        if (num != null) {
          numeros.add(num);
        }
      } else {
        // Tenta converter diretamente se for apenas número
        final num = int.tryParse(numero.replaceAll(RegExp(r'[^0-9]'), ''));
        if (num != null) {
          numeros.add(num);
        }
      }
    }

    if (numeros.isEmpty) {
      return 'PED-0001';
    }

    // Ordena os números
    numeros.sort();

    // Procura a primeira lacuna na sequência
    for (int i = 1; i <= numeros.last + 1; i++) {
      if (!numeros.contains(i)) {
        return 'PED-${i.toString().padLeft(4, '0')}';
      }
    }

    // Se não houver lacunas, usa o próximo número
    return 'PED-${(numeros.last + 1).toString().padLeft(4, '0')}';
  }

  /// Verifica se um número de pedido já existe
  static bool numeroExiste(String numero, List<String> numerosExistentes) {
    final numeroNormalizado = numero.toUpperCase().trim();
    return numerosExistentes.any(
      (n) => n.toUpperCase().trim() == numeroNormalizado,
    );
  }

  /// Extrai o número de um código de pedido (ex: PED-0001 -> 1)
  static int? extrairNumero(String codigo) {
    final match = RegExp(r'PED-(\d+)').firstMatch(codigo);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return int.tryParse(codigo.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  /// Formata um número para o padrão de pedido
  static String formatarNumero(int numero) {
    return 'PED-${numero.toString().padLeft(4, '0')}';
  }
}
