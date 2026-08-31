import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/nfce.dart';

/// Serviço de contingência NFC-e.
/// Quando o bridge está offline, salva a nota localmente e tenta retransmitir
/// automaticamente a cada 30 segundos quando a conexão retornar.
class NfceContingenciaService extends ChangeNotifier {
  static final NfceContingenciaService instance = NfceContingenciaService._();
  NfceContingenciaService._();

  static const String _pastaBase = r'C:\ExodoNFCe';
  static const String _arquivoFila = r'C:\ExodoNFCe\contingencia_queue.json';
  
  /// Limite máximo de tentativas antes de marcar nota como FALHA definitiva.
  /// Após atingir este limite, a nota é removida da fila e registrada como erro.
  static const int _maxTentativas = 100;
  
  /// Intervalo entre logs de tentativa para notas com muitas falhas
  /// (evita poluição do console — só loga a cada 10 tentativas após o 20º)
  static const int _logIntervalo = 10;

  final List<Map<String, dynamic>> _fila = [];
  Timer? _timerRetry;
  bool _transmitindo = false;

  /// Quantas notas estão aguardando transmissão
  int get totalPendentes => _fila.length;
  bool get temPendentes => _fila.isNotEmpty;

  /// Lista de notas pendentes (somente leitura)
  List<Map<String, dynamic>> get filaAtual => List.unmodifiable(_fila);

  // ─────────────────────────────────────────────────
  // INICIALIZAÇÃO
  // ─────────────────────────────────────────────────

  /// Inicializar: carregar fila do disco e iniciar timer de retry
  Future<void> inicializar() async {
    if (kIsWeb || !Platform.isWindows) return;
    await _carregarFilaDoDisco();
    _limparFilaInvalida();
    _iniciarTimerRetry();
    debugPrint('[Contingência] Inicializado. ${_fila.length} nota(s) na fila.');
  }

  /// Remove da fila notas com número inválido ("0"), vazias ou que já excederam o limite de tentativas.
  void _limparFilaInvalida() {
    final antes = _fila.length;
    _fila.removeWhere((entry) {
      final numero = entry['numero']?.toString() ?? '';
      final tentativas = (entry['tentativas'] as int?) ?? 0;
      if (numero == '0' || numero.isEmpty) {
        debugPrint('[Contingência] 🧹 Removendo nota inválida (número: "$numero") da fila');
        return true;
      }
      if (tentativas >= _maxTentativas) {
        debugPrint('[Contingência] 🧹 Removendo nota $numero (esgotou $_maxTentativas tentativas)');
        return true;
      }
      return false;
    });
    if (_fila.length != antes) {
      debugPrint('[Contingência] 🧹 Limpeza: $antes → ${_fila.length} notas');
      _salvarFilaNoDisco();
    }
  }

  @override
  void dispose() {
    _timerRetry?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────
  // ADICIONAR NA FILA
  // ─────────────────────────────────────────────────

  /// Adiciona uma nota na fila de contingência e salva no disco
  Future<void> adicionarNaFila({
    required Map<String, dynamic> payload,
    required String empresaId,
    required String empresaCnpj,
    required String numero,
    required double valorTotal,
    required DateTime tentativaEm,
  }) async {
    if (kIsWeb || !Platform.isWindows) return;

    final entry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'numero': numero,
      'valor_total': valorTotal,
      'empresa_id': empresaId,
      'empresa_cnpj': empresaCnpj,
      'tentativa_em': tentativaEm.toIso8601String(),
      'payload': payload,
      'tentativas': 0,
    };

    _fila.add(entry);
    await _salvarFilaNoDisco();
    notifyListeners();

    debugPrint('[Contingência] Nota $numero adicionada na fila. Total: ${_fila.length}');
  }

  // ─────────────────────────────────────────────────
  // RETRY AUTOMÁTICO
  // ─────────────────────────────────────────────────

  void _iniciarTimerRetry() {
    _timerRetry?.cancel();
    _timerRetry = Timer.periodic(const Duration(seconds: 30), (_) {
      tentarRetransmitirTudo();
    });
  }

  /// Tenta transmitir todas as notas pendentes.
  /// Retorna o número de notas que foram transmitidas com sucesso.
  Future<int> tentarRetransmitirTudo({
    Function(NFCe nfce)? onSucesso,
    Function(String numero, String erro)? onErro,
  }) async {
    if (kIsWeb || !Platform.isWindows) return 0;
    if (_transmitindo || _fila.isEmpty) return 0;

    _transmitindo = true;
    int sucessos = 0;
    final List<String> removidos = [];

    for (final entry in List.from(_fila)) {
      try {
        final payload = entry['payload'] as Map<String, dynamic>;
        final numero = entry['numero']?.toString() ?? '?';
        final tentativas = (entry['tentativas'] as int?) ?? 0;

        // ═══ LIMITE DE TENTATIVAS ═══
        if (tentativas >= _maxTentativas) {
          debugPrint('[Contingência] ❌ Nota $numero removida após $_maxTentativas tentativas (FALHA DEFINITIVA)');
          removidos.add(entry['id'] as String);
          if (onErro != null) {
            onErro(numero, 'FALHA DEFINITIVA após $_maxTentativas tentativas');
          }
          continue;
        }

        // ═══ NOTA INVÁLIDA (número = 0) ═══
        if (numero == '0' || numero.isEmpty) {
          debugPrint('[Contingência] ❌ Nota com número inválida ("$numero") removida da fila');
          removidos.add(entry['id'] as String);
          continue;
        }

        // Tentar emitir via bridge
        final result = await _enviarParaBridge(payload);

        if (result['status'] == 'sucesso' || result['status'] == 'autorizada') {
          removidos.add(entry['id'] as String);
          sucessos++;
          debugPrint('[Contingência] ✅ Nota $numero transmitida com sucesso!');

          // Notificar callback
          if (onSucesso != null) {
            final nfce = _construirNFCeDoRetorno(result, entry);
            onSucesso(nfce);
          }
        } else {
          // Incrementar contador de tentativas
          entry['tentativas'] = tentativas + 1;
          // Log otimizado: só imprime a cada N tentativas após o 20º
          final t = entry['tentativas'] as int;
          if (t <= 20 || t % _logIntervalo == 0) {
            debugPrint('[Contingência] ⚠️ Nota $numero ainda pendente (tentativa $t/$_maxTentativas)');
          }
          if (onErro != null) {
            onErro(numero, result['mensagem']?.toString() ?? 'Sem resposta');
          }
        }
      } catch (e) {
        // Bridge offline - incrementar e tentar na próxima rodada
        entry['tentativas'] = ((entry['tentativas'] as int?) ?? 0) + 1;
        final t = entry['tentativas'] as int;
        if (t <= 20 || t % _logIntervalo == 0) {
          debugPrint('[Contingência] 🔴 Bridge offline, aguardando (tentativa $t/$_maxTentativas)');
        }
      }
    }

    // Remover as transmitidas com sucesso
    _fila.removeWhere((e) => removidos.contains(e['id']));
    await _salvarFilaNoDisco();
    _transmitindo = false;
    notifyListeners();

    return sucessos;
  }

  /// Remove uma nota específica da fila (ex: após usuário cancelar manualmente)
  Future<void> removerDaFila(String entryId) async {
    _fila.removeWhere((e) => e['id'] == entryId);
    await _salvarFilaNoDisco();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────
  // BRIDGE HTTP
  // ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> _enviarParaBridge(Map<String, dynamic> payload) async {
    final uri = Uri.parse('http://localhost:8000/api/nfce/emitir');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } finally {
      client.close();
    }
  }

  NFCe _construirNFCeDoRetorno(Map<String, dynamic> data, Map<String, dynamic> entry) {
    final now = DateTime.now();
    return NFCe(
      id: data['id']?.toString() ?? now.millisecondsSinceEpoch.toString(),
      numero: data['numero']?.toString() ?? entry['numero']?.toString() ?? '0',
      serie: data['serie']?.toString() ?? '1',
      chaveAcesso: data['chave']?.toString() ?? data['chave_acesso']?.toString(),
      protocolo: data['protocolo']?.toString(),
      dataEmissao: now,
      empresaId: entry['empresa_id']?.toString() ?? '',
      itens: [],
      valorTotal: (entry['valor_total'] as num?)?.toDouble() ?? 0.0,
      pagamentos: [],
      xmlEnviado: data['xml_autorizado']?.toString() ?? data['xml']?.toString(),
      qrCode: data['qr_code']?.toString() ?? data['qrCode']?.toString(),
      status: 'autorizada',
      createdAt: now,
      updatedAt: now,
    );
  }

  // ─────────────────────────────────────────────────
  // PERSISTÊNCIA
  // ─────────────────────────────────────────────────

  Future<void> _carregarFilaDoDisco() async {
    try {
      final arquivo = File(_arquivoFila);
      if (arquivo.existsSync()) {
        final conteudo = arquivo.readAsStringSync();
        if (conteudo.trim().isNotEmpty) {
          final lista = jsonDecode(conteudo) as List<dynamic>;
          _fila.clear();
          _fila.addAll(lista.cast<Map<String, dynamic>>());
        }
      }
    } catch (e) {
      debugPrint('[Contingência] Erro ao carregar fila: $e');
    }
  }

  Future<void> _salvarFilaNoDisco() async {
    try {
      final dir = Directory(_pastaBase);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final arquivo = File(_arquivoFila);
      arquivo.writeAsStringSync(jsonEncode(_fila), encoding: utf8);
    } catch (e) {
      debugPrint('[Contingência] Erro ao salvar fila: $e');
    }
  }

  // ─────────────────────────────────────────────────
  // NUMERO RESERVADO (para não pular numeração)
  // ─────────────────────────────────────────────────

  static const String _arquivoNumeroReservado = r'C:\ExodoNFCe\numero_reservado.json';

  /// Salva o número que foi tentado mas deu erro, para reutilizá-lo
  static Future<void> reservarNumero(String empresaId, int numero) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final dir = Directory(_pastaBase);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final arquivo = File(_arquivoNumeroReservado);
      final dados = {empresaId: numero};
      arquivo.writeAsStringSync(jsonEncode(dados));
      debugPrint('[Contingência] Número $numero reservado para empresa $empresaId');
    } catch (e) {
      debugPrint('[Contingência] Erro ao reservar número: $e');
    }
  }

  /// Obtém número reservado (de emissão anterior com erro) para esta empresa
  static Future<int?> obterNumeroReservado(String empresaId) async {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final arquivo = File(_arquivoNumeroReservado);
      if (!arquivo.existsSync()) return null;
      final dados = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
      final valor = dados[empresaId];
      return valor != null ? (valor as num).toInt() : null;
    } catch (e) {
      return null;
    }
  }

  /// Limpa o número reservado após emissão bem-sucedida
  static Future<void> limparNumeroReservado(String empresaId) async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final arquivo = File(_arquivoNumeroReservado);
      if (arquivo.existsSync()) {
        final dados = jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
        dados.remove(empresaId);
        arquivo.writeAsStringSync(jsonEncode(dados));
        debugPrint('[Contingência] Número reservado limpo para empresa $empresaId');
      }
    } catch (e) {
      debugPrint('[Contingência] Erro ao limpar número reservado: $e');
    }
  }
}
