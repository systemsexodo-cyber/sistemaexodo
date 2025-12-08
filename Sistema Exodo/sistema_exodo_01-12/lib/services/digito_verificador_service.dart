/// Serviço para cálculo do dígito verificador da chave de acesso NFC-e
class DigitoVerificadorService {
  /// Calcula o dígito verificador da chave de acesso (43 dígitos)
  /// Algoritmo: Módulo 11 com pesos de 2 a 9
  static String calcularDigitoVerificador(String chave43Digitos) {
    if (chave43Digitos.length != 43) {
      throw Exception('Chave deve ter exatamente 43 dígitos');
    }

    // Pesos para cálculo (da direita para esquerda, repetindo de 2 a 9)
    final pesos = [2, 3, 4, 5, 6, 7, 8, 9];
    int soma = 0;

    // Percorrer chave da direita para esquerda
    for (int i = chave43Digitos.length - 1, pesoIndex = 0; i >= 0; i--, pesoIndex++) {
      final digito = int.parse(chave43Digitos[i]);
      final peso = pesos[pesoIndex % pesos.length];
      soma += digito * peso;
    }

    // Calcular resto da divisão por 11
    final resto = soma % 11;

    // Calcular dígito verificador
    int digitoVerificador;
    if (resto == 0 || resto == 1) {
      digitoVerificador = 0;
    } else {
      digitoVerificador = 11 - resto;
    }

    return digitoVerificador.toString();
  }

  /// Valida se o dígito verificador está correto
  static bool validarDigitoVerificador(String chaveCompleta) {
    if (chaveCompleta.length != 44) {
      return false;
    }

    final chave43Digitos = chaveCompleta.substring(0, 43);
    final digitoInformado = chaveCompleta.substring(43, 44);
    final digitoCalculado = calcularDigitoVerificador(chave43Digitos);

    return digitoInformado == digitoCalculado;
  }
}

