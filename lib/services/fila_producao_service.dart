import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ticket_producao.dart';

/// Fila das vias de produção que NÃO saíram na impressora do setor.
///
/// A fila é da MÁQUINA: a impressora de cada setor é local, então uma via que
/// falhou aqui só pode ser reimpressa de um PC que tenha aquela impressora. Por
/// isso o estado vive no SharedPreferences do terminal (chave por empresa),
/// sem nuvem e sem sincronização — do mesmo jeito que a "última impressora do
/// terminal" em `ImpressaoService`.
///
/// Quem alimenta a fila é `ProducaoPdfService.imprimirTicketsProducao`: cada
/// destino (setor + impressora) que não imprimiu entra aqui; quando a via sai
/// (na primeira tentativa ou numa reimpressão) o registro é removido.
class FilaProducaoService extends ChangeNotifier {
  FilaProducaoService._();

  /// Instância usada pelo app (uma fila por terminal).
  static final FilaProducaoService instancia = FilaProducaoService._();

  /// Instância isolada para testes (não mexe na fila do terminal).
  @visibleForTesting
  factory FilaProducaoService.paraTeste() = FilaProducaoService._;

  static const String _chaveBase = 'fila_producao';
  static const int _maximoTickets = 200;

  String _empresaId = '';
  bool _carregada = false;
  bool _carregando = false;
  List<TicketProducao> _pendentes = [];

  /// Vias que ainda não saíram, da mais antiga para a mais nova.
  List<TicketProducao> get pendentes => List.unmodifiable(_pendentes);

  bool get carregada => _carregada;

  int get total => _pendentes.length;

  String get chaveArmazenamento =>
      _empresaId.isEmpty ? _chaveBase : '${_chaveBase}_$_empresaId';

  /// Fixa a empresa da fila (chamado na troca de empresa).
  ///
  /// A carga é preguiçosa: quem lê/mexe na fila chama [carregar] ou cai em
  /// `_garantirCarregada`, então não há corrida entre trocar de empresa e ler.
  void initialize({required String empresaId}) {
    if (_carregada && empresaId == _empresaId) return;
    _empresaId = empresaId;
    _carregada = false;
  }

  /// Recarrega do armazenamento local.
  Future<void> carregar() async {
    if (_carregando) return;
    _carregando = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(chaveArmazenamento);
      final lista = <TicketProducao>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decodificado = jsonDecode(raw);
        if (decodificado is List) {
          for (final item in decodificado) {
            if (item is! Map) continue;
            final ticket = TicketProducao.fromMap(Map<String, dynamic>.from(item));
            if (ticket.documento.trim().isEmpty && ticket.setor.trim().isEmpty) {
              continue;
            }
            lista.add(ticket);
          }
        }
      }
      _pendentes = _ordenar(lista);
    } catch (e) {
      debugPrint('>>> [FilaProducao] ⚠️ Erro ao carregar a fila: $e');
    } finally {
      _carregando = false;
      _carregada = true;
      notifyListeners();
    }
  }

  /// Vias pendentes de um setor (comparação pelo nome, sem diferenciar
  /// maiúsculas/minúsculas).
  List<TicketProducao> pendentesDoSetor(String setor) {
    final alvo = setor.trim().toLowerCase();
    if (alvo.isEmpty) return const [];
    return _pendentes
        .where((t) => t.setor.trim().toLowerCase() == alvo)
        .toList(growable: false);
  }

  int contarDoSetor(String setor) => pendentesDoSetor(setor).length;

  /// Entra (ou atualiza) uma via que não imprimiu. A mesma via não vira duas
  /// entradas: tentativa nova só aumenta o contador e troca o motivo.
  Future<void> registrarFalha(TicketProducao ticket) async {
    await _garantirCarregada();
    final indice = _pendentes.indexWhere((t) => t.chave == ticket.chave);
    if (indice >= 0) {
      _pendentes[indice] = _pendentes[indice].comNovaFalha(ticket.ultimoErro);
    } else {
      _pendentes.add(ticket.copyWith(empresaId: _empresaId));
    }
    _pendentes = _ordenar(_podar(_pendentes));
    await _salvar();
    notifyListeners();
  }

  /// Tira da fila a via que acabou de sair (primeira impressão ou reimpressão).
  Future<void> registrarSucesso({
    required String documento,
    required String setor,
    String? impressora,
  }) async {
    await _garantirCarregada();
    final alvo = '${documento.trim().toUpperCase()}|${setor.trim().toLowerCase()}|'
        '${impressora?.trim().toLowerCase() ?? ''}';
    final antes = _pendentes.length;
    _pendentes = _pendentes
        .where((t) =>
            '${t.documento.trim().toUpperCase()}|${t.setor.trim().toLowerCase()}|'
                '${t.impressora.trim().toLowerCase()}' !=
            alvo)
        .toList();
    if (_pendentes.length == antes) return;
    await _salvar();
    notifyListeners();
  }

  /// Remove uma via da fila sem imprimir (o operador conferiu que já saiu ou
  /// que não precisa mais).
  Future<void> descartar(String id) async {
    await _garantirCarregada();
    final antes = _pendentes.length;
    _pendentes = _pendentes.where((t) => t.id != id).toList();
    if (_pendentes.length == antes) return;
    await _salvar();
    notifyListeners();
  }

  /// Limpa as vias de um setor (usado pelo "já resolvi" do monitor).
  Future<void> descartarDoSetor(String setor) async {
    await _garantirCarregada();
    final alvo = setor.trim().toLowerCase();
    final antes = _pendentes.length;
    _pendentes = _pendentes
        .where((t) => t.setor.trim().toLowerCase() != alvo)
        .toList();
    if (_pendentes.length == antes) return;
    await _salvar();
    notifyListeners();
  }

  /// Registra o resultado de uma impressão: sai da fila se imprimiu na
  /// impressora do setor; entra/atualiza se não.
  Future<void> registrarResultado({
    required String documento,
    required String setor,
    required String impressora,
    required bool imprimiu,
    TicketProducao? ticket,
    String? erro,
  }) async {
    if (imprimiu) {
      await registrarSucesso(
        documento: documento,
        setor: setor,
        impressora: impressora,
      );
      return;
    }
    if (ticket == null) return;
    await registrarFalha(ticket.copyWith(ultimoErro: erro ?? ticket.ultimoErro));
  }

  Future<void> _garantirCarregada() async {
    if (!_carregada) await carregar();
  }

  Future<void> _salvar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dados = jsonEncode(_pendentes.map((t) => t.toMap()).toList());
      await prefs.setString(chaveArmazenamento, dados);
    } catch (e) {
      debugPrint('>>> [FilaProducao] ⚠️ Erro ao salvar a fila: $e');
    }
  }

  /// Mais antigas primeiro: é a ordem em que a cozinha precisa delas.
  List<TicketProducao> _ordenar(List<TicketProducao> lista) {
    final copia = List<TicketProducao>.from(lista);
    copia.sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
    return copia;
  }

  /// Mantém só as mais novas quando a fila cresce demais (evita crescer sem
  /// limite num terminal que fica dias com a impressora fora do ar).
  List<TicketProducao> _podar(List<TicketProducao> lista) {
    if (lista.length <= _maximoTickets) return lista;
    return lista.sublist(lista.length - _maximoTickets);
  }
}
