/// Leitura amigável da telemetria de sincronização (`sync_status` na nuvem).
///
/// Cada computador cliente publica ali, a cada ciclo e a cada heartbeat, quando
/// sincronizou pela última vez, quando deu o último sinal de vida
/// (`online_data`), quantos itens ficaram na fila e qual foi o último erro.
///
/// O registro cru não responde o que o suporte precisa saber: "essa máquina está
/// há quantos dias sem dar sinal?" e "esse erro ainda vale ou já foi resolvido?".
/// Esta classe transforma o registro nessas respostas, sem depender de UI.
///
/// Todos os cálculos de tempo recebem `agora` por parâmetro para ficarem
/// testáveis (e para que a tela inteira use o mesmo instante de referência).
class StatusSync {
  final String empresaId;
  final String pcName;

  /// `true` quando o cliente se declarou online no último contato. Um cliente
  /// que caiu continua com `true` para sempre — por isso nunca confie só nisso,
  /// use [tempoSemContato].
  final bool onlineFlag;

  final DateTime? ultimaSincronizacao;
  final DateTime? onlineData;
  final DateTime? updatedAt;

  final String ultimoErro;
  final DateTime? ultimoErroData;

  final int filaPendente;
  final String versaoApp;

  const StatusSync({
    required this.empresaId,
    this.pcName = '',
    this.onlineFlag = false,
    this.ultimaSincronizacao,
    this.onlineData,
    this.updatedAt,
    this.ultimoErro = '',
    this.ultimoErroData,
    this.filaPendente = 0,
    this.versaoApp = '',
  });

  factory StatusSync.fromMap(String empresaId, Map<String, dynamic> map) {
    return StatusSync(
      empresaId: empresaId.isNotEmpty
          ? empresaId
          : (map['empresa_id']?.toString() ?? ''),
      pcName: map['pc_name']?.toString() ?? '',
      onlineFlag: map['online'] == true,
      ultimaSincronizacao: _data(map['ultima_sincronizacao']),
      onlineData: _data(map['online_data']),
      updatedAt: _data(map['updated_at']),
      ultimoErro: map['ultimo_erro']?.toString() ?? '',
      ultimoErroData: _data(map['ultimo_erro_data']),
      filaPendente: _inteiro(map['fila_pendente']),
      versaoApp: map['versao_app']?.toString() ?? '',
    );
  }

  static DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor.toUtc();
    final texto = valor.toString().trim();
    if (texto.isEmpty) return null;
    return DateTime.tryParse(texto)?.toUtc();
  }

  static int _inteiro(dynamic valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }

  /// Momento do último contato conhecido com a nuvem: o mais recente entre o
  /// heartbeat, a última sincronização e a última gravação da linha.
  ///
  /// É isso que diz se o cliente está vivo — não a flag `online`, que fica
  /// "true" congelada quando a máquina desliga.
  DateTime? get ultimoContato {
    DateTime? maisRecente;
    for (final candidato in [onlineData, ultimaSincronizacao, updatedAt]) {
      if (candidato == null) continue;
      if (maisRecente == null || candidato.isAfter(maisRecente)) {
        maisRecente = candidato;
      }
    }
    return maisRecente;
  }

  /// Há quanto tempo o cliente não dá sinal. `null` = nunca sincronizou.
  Duration? tempoSemContato(DateTime agora) {
    final contato = ultimoContato;
    if (contato == null) return null;
    final diff = agora.toUtc().difference(contato);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Dias inteiros sem contato (0 no mesmo dia). `null` = nunca sincronizou.
  int? diasSemContato(DateTime agora) => tempoSemContato(agora)?.inDays;

  /// Cliente que passou de 24h sem dar sinal — o caso que o suporte precisa ver.
  bool semContatoHaDias(DateTime agora) {
    final dias = diasSemContato(agora);
    return dias != null && dias >= 1;
  }

  /// Tempo desde o último contato em texto curto: "agora", "há 12min",
  /// "há 3h 20min", "há 2 dias". `null` = nunca sincronizou.
  String? tempoLegivel(DateTime agora) {
    final tempo = tempoSemContato(agora);
    if (tempo == null) return null;
    if (tempo.inMinutes < 1) return 'agora';
    if (tempo.inMinutes < 60) return 'há ${tempo.inMinutes}min';
    if (tempo.inHours < 24) {
      final minutos = tempo.inMinutes % 60;
      return minutos == 0
          ? 'há ${tempo.inHours}h'
          : 'há ${tempo.inHours}h ${minutos}min';
    }
    final dias = tempo.inDays;
    final horas = tempo.inHours % 24;
    final base = dias == 1 ? 'há 1 dia' : 'há $dias dias';
    return horas == 0 ? base : '$base e ${horas}h';
  }

  /// Há quanto tempo o erro pendente ocorreu (em texto curto).
  String? erroHaQuantoTempo(DateTime agora) {
    if (ultimoErroData == null) return null;
    final diff = agora.toUtc().difference(ultimoErroData!);
    if (diff.isNegative) return 'agora';
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    final dias = diff.inDays;
    return dias == 1 ? 'há 1 dia' : 'há $dias dias';
  }

  /// Um erro só continua valendo se não foi superado por uma sincronização
  /// posterior. Cliente que voltou a sincronizar já resolveu o problema.
  ///
  /// O comparativo é `>=` de propósito: o sincronizador grava
  /// `ultimo_erro_data` e `ultima_sincronizacao` com o MESMO instante quando o
  /// ciclo termina com erro. Exigir que o erro fosse estritamente mais novo
  /// faria o monitor esconder exatamente os erros que ele precisa mostrar.
  bool get temErroNaoResolvido {
    if (ultimoErro.trim().isEmpty) return false;
    if (ultimoErroData == null) return true;
    if (ultimaSincronizacao == null) return true;
    return !ultimoErroData!.isBefore(ultimaSincronizacao!);
  }

  /// Erro antigo, que já foi superado por uma sincronização posterior.
  bool get erroJaResolvido =>
      ultimoErro.trim().isEmpty == false && !temErroNaoResolvido;

  /// Situação resumida, já com o tempo embutido quando faz diferença.
  String textoStatus(DateTime agora) {
    final tempo = tempoSemContato(agora);
    if (tempo == null) return 'Nunca sincronizou';
    if (temErroNaoResolvido) return 'Com erro';
    if (tempo.inMinutes < 5) return 'Online agora';
    if (tempo.inMinutes < 30) return 'Ativo (${tempo.inMinutes}min)';
    if (tempo.inHours < 2) return 'Atrasado (${tempo.inMinutes}min)';
    if (tempo.inHours < 24) return 'Parado há ${tempo.inHours}h';
    final dias = tempo.inDays;
    return dias == 1 ? 'OFFLINE há 1 dia' : 'OFFLINE há $dias dias';
  }

  /// Selo curto para destacar o caso grave na lista (null = nada a destacar).
  String? seloOffline(DateTime agora) {
    final dias = diasSemContato(agora);
    if (dias == null) return 'NUNCA SINCRONIZOU';
    if (dias >= 1) return dias == 1 ? '1 DIA OFFLINE' : '$dias DIAS OFFLINE';
    return null;
  }

  /// Severidade: quanto maior, mais urgente aparece na lista do monitor.
  ///
  /// 4 = erro pendente, 3 = sem sinal há dias, 2 = nunca sincronizou,
  /// 1 = parado no mesmo dia, 0 = saudável.
  int criticidade(DateTime agora) {
    if (temErroNaoResolvido) return 4;
    final tempo = tempoSemContato(agora);
    if (tempo == null) return 2;
    if (tempo.inHours >= 24) return 3;
    if (tempo.inHours >= 2) return 1;
    return 0;
  }

  /// Ordena do pior para o melhor: mais grave primeiro e, dentro do mesmo grau,
  /// o que está sem sinal há mais tempo.
  int compararCom(StatusSync outro, DateTime agora) {
    final porCriticidade =
        outro.criticidade(agora).compareTo(criticidade(agora));
    if (porCriticidade != 0) return porCriticidade;
    final meu = tempoSemContato(agora) ?? const Duration(days: 3650);
    final dele = outro.tempoSemContato(agora) ?? const Duration(days: 3650);
    return dele.compareTo(meu);
  }
}
