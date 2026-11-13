/// Horário de funcionamento da loja online, com um horário próprio por dia.
///
/// Fica em `empresa.configuracoes['ecommerce']['horariosFuncionamento']`, no
/// formato:
/// ```json
/// {
///   "seg": {"aberto": true, "abre": "08:00", "fecha": "18:00"},
///   "dom": {"aberto": false, "abre": "08:00", "fecha": "12:00"}
/// }
/// ```
/// O texto livre antigo (`horarioFuncionamento`) continua existindo apenas para
/// exibição; quem decide se a loja aceita pedido é este mapa.
class HorarioDiaLoja {
  const HorarioDiaLoja({
    this.aberto = true,
    this.abre = '08:00',
    this.fecha = '18:00',
  });

  final bool aberto;
  final String abre;
  final String fecha;

  Map<String, dynamic> toMap() => {
        'aberto': aberto,
        'abre': abre,
        'fecha': fecha,
      };

  factory HorarioDiaLoja.fromMap(dynamic valor) {
    if (valor is! Map) return const HorarioDiaLoja();
    return HorarioDiaLoja(
      aberto: valor['aberto'] as bool? ?? true,
      abre: _horaValida(valor['abre'] as String?, '08:00'),
      fecha: _horaValida(valor['fecha'] as String?, '18:00'),
    );
  }

  HorarioDiaLoja copyWith({bool? aberto, String? abre, String? fecha}) {
    return HorarioDiaLoja(
      aberto: aberto ?? this.aberto,
      abre: abre ?? this.abre,
      fecha: fecha ?? this.fecha,
    );
  }

  /// Texto curto para o resumo: "08:00 às 18:00" ou "Fechado".
  String get resumo => aberto ? '$abre às $fecha' : 'Fechado';

  static String _horaValida(String? valor, String padrao) {
    if (valor == null) return padrao;
    final minutos = HorarioLojaService.minutosDe(valor);
    if (minutos == null) return padrao;
    return valor;
  }
}

/// Resultado do cálculo "a loja está aberta agora?".
class StatusLoja {
  const StatusLoja({
    required this.aberta,
    this.configurado = true,
    this.fechaAs,
    this.proximaAbertura,
  });

  final bool aberta;

  /// false quando o lojista ainda não configurou horários por dia — nesse caso
  /// a loja continua aberta, para não travar quem nunca usou o recurso.
  final bool configurado;

  /// Quando está aberta: "18:00".
  final String? fechaAs;

  /// Quando está fechada: "Abre amanhã às 08:00" (pode ser null se não houver
  /// nenhum dia aberto).
  final String? proximaAbertura;

  String get rotulo {
    if (!configurado) return 'Loja aberta';
    return aberta ? 'Aberta agora' : 'Loja fechada';
  }

  String get detalhe {
    if (!configurado) return '';
    if (aberta) return fechaAs == null ? '' : 'Aberta até $fechaAs';
    return proximaAbertura ?? 'Sem horário de abertura configurado';
  }
}

class HorarioLojaService {
  HorarioLojaService._();

  /// Chaves na ordem de exibição (segunda a domingo).
  static const List<String> chavesDias = [
    'seg',
    'ter',
    'qua',
    'qui',
    'sex',
    'sab',
    'dom',
  ];

  static const Map<String, String> nomesDias = {
    'seg': 'Segunda',
    'ter': 'Terça',
    'qua': 'Quarta',
    'qui': 'Quinta',
    'sex': 'Sexta',
    'sab': 'Sábado',
    'dom': 'Domingo',
  };

  /// Segunda a sexta 08:00–18:00, sábado 08:00–12:00, domingo fechado.
  static Map<String, HorarioDiaLoja> padrao() => {
        'seg': const HorarioDiaLoja(),
        'ter': const HorarioDiaLoja(),
        'qua': const HorarioDiaLoja(),
        'qui': const HorarioDiaLoja(),
        'sex': const HorarioDiaLoja(),
        'sab': const HorarioDiaLoja(abre: '08:00', fecha: '12:00'),
        'dom': const HorarioDiaLoja(aberto: false, abre: '08:00', fecha: '12:00'),
      };

  /// Lê o mapa salvo. Vazio = nunca configurado.
  static Map<String, HorarioDiaLoja> doConfig(Map<String, dynamic>? ecommerce) {
    final bruto = ecommerce?['horariosFuncionamento'];
    if (bruto is! Map) return const {};
    final lido = <String, HorarioDiaLoja>{};
    for (final chave in chavesDias) {
      if (bruto[chave] is Map) {
        lido[chave] = HorarioDiaLoja.fromMap(bruto[chave]);
      }
    }
    if (lido.isEmpty) return const {};
    return {...padrao(), ...lido};
  }

  static Map<String, dynamic> paraConfig(Map<String, HorarioDiaLoja> horarios) {
    return {
      for (final chave in chavesDias)
        chave: (horarios[chave] ?? const HorarioDiaLoja()).toMap(),
    };
  }

  /// Minutos desde a meia-noite. Aceita "8:00" e "08:00".
  static int? minutosDe(String? hora) {
    if (hora == null) return null;
    final partes = hora.trim().split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  /// A loja está aberta em [agora]? Considera janelas que atravessam a
  /// meia-noite (ex.: 18:00 às 02:00).
  static StatusLoja status({
    Map<String, dynamic>? ecommerce,
    DateTime? agora,
  }) {
    final horarios = doConfig(ecommerce);
    if (horarios.isEmpty) {
      return const StatusLoja(aberta: true, configurado: false);
    }

    final now = agora ?? DateTime.now();
    final minutosAgora = now.hour * 60 + now.minute;
    final indiceHoje = now.weekday - 1; // 1=segunda .. 7=domingo

    // Janela de ontem que ainda está valendo depois da meia-noite.
    final indiceOntem = (indiceHoje + 6) % 7;
    final ontem = horarios[chavesDias[indiceOntem]]!;
    if (ontem.aberto && _atravessaMeiaNoite(ontem)) {
      final fechaOntem = minutosDe(ontem.fecha)!;
      if (minutosAgora < fechaOntem) {
        return StatusLoja(aberta: true, fechaAs: ontem.fecha);
      }
    }

    final hoje = horarios[chavesDias[indiceHoje]]!;
    if (hoje.aberto) {
      final abre = minutosDe(hoje.abre)!;
      final fecha = minutosDe(hoje.fecha)!;
      if (_atravessaMeiaNoite(hoje)) {
        if (minutosAgora >= abre) {
          return StatusLoja(aberta: true, fechaAs: hoje.fecha);
        }
      } else if (minutosAgora >= abre && minutosAgora < fecha) {
        return StatusLoja(aberta: true, fechaAs: hoje.fecha);
      }
    }

    // Fechada: descobre a próxima abertura (até 7 dias à frente).
    for (var adiante = 0; adiante < 8; adiante++) {
      final indice = (indiceHoje + adiante) % 7;
      final dia = horarios[chavesDias[indice]]!;
      if (!dia.aberto) continue;
      final abre = minutosDe(dia.abre)!;
      if (adiante == 0 && minutosAgora >= abre) continue;

      final quando = switch (adiante) {
        0 => 'hoje',
        1 => 'amanhã',
        _ => nomesDias[chavesDias[indice]]!.toLowerCase(),
      };
      return StatusLoja(
        aberta: false,
        proximaAbertura: 'Abre $quando às ${dia.abre}',
      );
    }

    return const StatusLoja(
      aberta: false,
      proximaAbertura: 'Sem horário de abertura configurado',
    );
  }

  /// Resumo de uma linha, usado em tooltips/avisos.
  static String resumoSemanal(Map<String, HorarioDiaLoja> horarios) {
    return chavesDias
        .map((c) => '${nomesDias[c]}: ${(horarios[c] ?? const HorarioDiaLoja()).resumo}')
        .join('\n');
  }

  static bool _atravessaMeiaNoite(HorarioDiaLoja dia) {
    final abre = minutosDe(dia.abre);
    final fecha = minutosDe(dia.fecha);
    if (abre == null || fecha == null) return false;
    return fecha <= abre;
  }
}
