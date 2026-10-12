import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/ajuste_estoque_lote.dart';
import '../models/estoque.dart';
import '../models/permissao.dart';
import '../models/produto.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/permission_service.dart';
import '../theme.dart';

/// Ajuste geral em massa: estoque **e** preço.
///
/// O usuário monta o lote por filtros (busca, grupo, fornecedor, unidade,
/// status, faixa de estoque), aplica uma regra geral (definir valor, aumentar %
/// ou reduzir %) nas colunas de estoque/preço e ainda pode ajustar item a item
/// direto na tabela — escolhendo na PRÓPRIA linha o operador do valor digitado
/// (+ somar, = definir, − subtrair), sem depender da regra geral. Nada é gravado
/// até tocar em APLICAR — e cada diferença é registrada no histórico (estoque) e
/// no histórico do produto (preço).
class AjusteEstoqueMassaPage extends StatefulWidget {
  const AjusteEstoqueMassaPage({super.key});

  @override
  State<AjusteEstoqueMassaPage> createState() => _AjusteEstoqueMassaPageState();
}

/// Como uma regra geral é aplicada sobre o valor atual de cada item.
enum _ModoAjuste {
  definir,
  somarQuantidade,
  subtrairQuantidade,
  aumentarPercentual,
  reduzirPercentual,
}

extension _ModoAjusteRotulo on _ModoAjuste {
  String get rotulo {
    switch (this) {
      case _ModoAjuste.definir:
        return 'Definir valor (ajustar)';
      case _ModoAjuste.somarQuantidade:
        return 'Somar quantidade';
      case _ModoAjuste.subtrairQuantidade:
        return 'Subtrair quantidade';
      case _ModoAjuste.aumentarPercentual:
        return 'Aumentar %';
      case _ModoAjuste.reduzirPercentual:
        return 'Reduzir %';
    }
  }

  /// Só os modos com percentual usam o sinal `%` no rótulo.
  bool get ehPercentual =>
      this == _ModoAjuste.aumentarPercentual || this == _ModoAjuste.reduzirPercentual;
}

class _RegraAplicada {
  final _ModoAjuste modo;
  final double valor;
  const _RegraAplicada(this.modo, this.valor);

  String get descricao {
    final numero = valor.toStringAsFixed(2).replaceAll('.', ',');
    switch (modo) {
      case _ModoAjuste.definir:
        return 'Definir $numero';
      case _ModoAjuste.somarQuantidade:
        return 'Somar +$numero';
      case _ModoAjuste.subtrairQuantidade:
        return 'Subtrair -$numero';
      case _ModoAjuste.aumentarPercentual:
        return 'Aumentar $numero%';
      case _ModoAjuste.reduzirPercentual:
        return 'Reduzir $numero%';
    }
  }

  /// Calcula o novo valor a partir do valor atual do item.
  double? aplicar(double atual) {
    switch (modo) {
      case _ModoAjuste.definir:
        return valor < 0 ? null : _round2(valor);
      case _ModoAjuste.somarQuantidade:
        return _round2(atual + valor);
      case _ModoAjuste.subtrairQuantidade:
        // Sem trava em zero: subtrair mais do que existe deixa o estoque
        // negativo (5 - 20 = -15), como o usuário pediu.
        return _round2(atual - valor);
      case _ModoAjuste.aumentarPercentual:
        return _round2(atual * (1 + valor / 100));
      case _ModoAjuste.reduzirPercentual:
        return _round2(atual * (1 - valor / 100));
    }
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Lê um número digitado em pt-BR ("1.234,56") ou no formato simples ("12.5").
/// Se houver vírgula, ela é o separador decimal e os pontos são de milhar.
double? _parseNumero(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) return double.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  return double.tryParse(t);
}

class _AjusteEstoqueMassaPageState extends State<AjusteEstoqueMassaPage> {
  static const String _chaveGeral = 'GERAL';
  static const String _chaveSemFornecedor = 'Sem fornecedor';

  // Larguras fixas das colunas (tabela densa alinhada ao cabeçalho).
  static const double _wCheck = 34;
  static const double _wCod = 54;
  static const double _wGrupo = 96;
  // 96 para caber o cabeçalho com o nome do estoque ("EST. DEPÓSITO").
  static const double _wAtual = 96;
  /// Largura do seletor + / = / − que fica dentro de cada linha.
  static const double _wOp = 54;
  static const double _wInput = 82;
  static const double _wPrecoAtual = 78;
  static const double _wPrecoInput = 88;
  /// Espaço da prévia do saldo final ("→ 18") ao lado do campo digitado.
  static const double _wPrevia = 44;
  /// Célula completa da tabela: seletor de operador + 4 de respiro + campo +
  /// 4 de respiro + prévia do resultado.
  static const double _wCelulaValor = _wOp + 4 + _wInput + 4 + _wPrevia;
  static const double _wCelulaPreco = _wOp + 4 + _wPrecoInput + 4 + _wPrevia;
  static const double _wDiff = 60;
  static const double _alturaLinha = 38;

  final _buscaController = TextEditingController();
  final _deController = TextEditingController();
  final _ateController = TextEditingController();
  final _valorEstoqueController = TextEditingController();
  final _valorPrecoController = TextEditingController();
  final _observacaoController = TextEditingController();

  // ---------- Filtros ----------
  String _busca = '';
  final Set<String> _gruposSelecionados = {};
  String? _fornecedorSelecionado;
  String? _unidadeSelecionada;
  bool? _statusAtivo;
  double? _estoqueDe;
  double? _estoqueAte;
  bool _abaixoDoMinimo = false;
  bool _filtrosAbertos = true;

  // ---------- Regras gerais ----------
  _ModoAjuste _modoEstoque = _ModoAjuste.definir;
  _ModoAjuste _modoPreco = _ModoAjuste.aumentarPercentual;
  _RegraAplicada? _regraEstoque;
  _RegraAplicada? _regraPreco;

  // ---------- Edição item a item ----------
  final Set<String> _excluidos = {};
  /// Número **digitado** na linha (bruto, antes do operador). O valor final sai
  /// de [_estoqueOperadorItem]/[_precoOperadorItem] aplicado sobre o saldo/preço
  /// atual — por isso trocar o operador da linha recalcula na hora.
  final Map<String, double> _estoqueManual = {};
  final Map<String, double> _precoManual = {};
  /// Operador escolhido NA PRÓPRIA LINHA (+, =, −): é o "somar/definir/subtrair
  /// direto no item", independente da regra geral do topo.
  final Map<String, _ModoAjuste> _estoqueOperadorItem = {};
  final Map<String, _ModoAjuste> _precoOperadorItem = {};
  /// Incrementa quando as regras mudam, para os campos da tabela recarregarem
  /// os valores calculados sem interferir na digitação item a item.
  int _geracao = 0;

  /// Qual ESTOQUE esta tela está ajustando: ele dá o número da coluna EST., a
  /// base dos filtros e das regras, e é o destino gravado no APLICAR (e no
  /// DESFAZER, pelo registro do lote). Null só enquanto a empresa não tem
  /// estoques cadastrados — aí vale o total do produto, como sempre.
  String? _estoqueId;

  bool _aplicando = false;

  final _scrollHorizontal = ScrollController();
  final _scrollVertical = ScrollController();

  final NumberFormat _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  final NumberFormat _num = NumberFormat.decimalPattern('pt_BR');

  @override
  void dispose() {
    _buscaController.dispose();
    _deController.dispose();
    _ateController.dispose();
    _valorEstoqueController.dispose();
    _valorPrecoController.dispose();
    _observacaoController.dispose();
    _scrollHorizontal.dispose();
    _scrollVertical.dispose();
    super.dispose();
  }

  // ==================== FILTROS ====================

  String _chaveGrupo(Produto p) => p.grupo.trim().isEmpty ? _chaveGeral : p.grupo.trim();

  String _chaveFornecedor(Produto p) {
    final nome = p.fornecedorNome?.trim() ?? '';
    return nome.isEmpty ? _chaveSemFornecedor : nome;
  }

  int get _filtrosAtivos {
    var total = 0;
    if (_busca.trim().isNotEmpty) total++;
    if (_gruposSelecionados.isNotEmpty) total++;
    if (_fornecedorSelecionado != null) total++;
    if (_unidadeSelecionada != null) total++;
    if (_statusAtivo != null) total++;
    if (_estoqueDe != null || _estoqueAte != null) total++;
    if (_abaixoDoMinimo) total++;
    return total;
  }

  void _sincronizarFaixaEstoque() {
    _estoqueDe = double.tryParse(_deController.text.trim().replaceAll(',', '.'));
    _estoqueAte = double.tryParse(_ateController.text.trim().replaceAll(',', '.'));
  }

  List<Produto> _montarLote(List<Produto> todos) {
    final q = _busca.toLowerCase().trim();
    final lista = todos.where((p) {
      if (_gruposSelecionados.isNotEmpty && !_gruposSelecionados.contains(_chaveGrupo(p))) return false;
      if (_fornecedorSelecionado != null && _chaveFornecedor(p) != _fornecedorSelecionado) return false;
      if (_unidadeSelecionada != null && p.unidade.trim().toUpperCase() != _unidadeSelecionada) return false;
      if (_statusAtivo != null && p.ativo != _statusAtivo) return false;
      if (_abaixoDoMinimo && !(p.estoqueMinimo > 0 && _saldoDe(p) <= p.estoqueMinimo + 0.0005)) return false;
      if (_estoqueDe != null && _saldoDe(p) < _estoqueDe! - 0.0005) return false;
      if (_estoqueAte != null && _saldoDe(p) > _estoqueAte! + 0.0005) return false;
      if (q.isEmpty) return true;
      return p.nome.toLowerCase().contains(q) ||
          (p.codigo?.toLowerCase().contains(q) ?? false) ||
          (p.codigoBarras?.toLowerCase().contains(q) ?? false) ||
          p.todosCodigosBarras.any((c) => c.toLowerCase().contains(q));
    }).toList();

    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  void _aplicarPreset(String preset) {
    setState(() {
      _abaixoDoMinimo = false;
      switch (preset) {
        case 'Zerados':
          _deController.text = '0';
          _ateController.text = '0';
          break;
        case 'Até 10':
          _deController.clear();
          _ateController.text = '10';
          break;
        case 'Abaixo do mínimo':
          _abaixoDoMinimo = true;
          _deController.clear();
          _ateController.clear();
          break;
      }
      _sincronizarFaixaEstoque();
      _excluidos.clear();
    });
  }

  void _limparFiltros() {
    setState(() {
      _buscaController.clear();
      _busca = '';
      _gruposSelecionados.clear();
      _fornecedorSelecionado = null;
      _unidadeSelecionada = null;
      _statusAtivo = null;
      _estoqueDe = null;
      _estoqueAte = null;
      _deController.clear();
      _ateController.clear();
      _abaixoDoMinimo = false;
      _excluidos.clear();
    });
  }

  // ==================== REGRAS E VALORES ====================

  // ==================== ESTOQUE ESCOLHIDO ====================

  /// DataService sem listener (a tela já escuta em `build`).
  DataService get _ds => Provider.of<DataService>(context, listen: false);

  /// Saldo do produto NO estoque que esta tela está ajustando: é o número da
  /// coluna EST., o que os filtros usam e a base das regras e das edições item
  /// a item.
  double _saldoDe(Produto p) =>
      _estoqueId == null ? p.estoque : _ds.saldoNoEstoque(p, _estoqueId!);

  /// Nome do estoque escolhido (null quando o ajuste é sobre o total).
  String? get _nomeDoEstoqueEscolhido =>
      _estoqueId == null ? null : nomeDoEstoque(_ds.estoques, _estoqueId!);

  /// Trecho para as mensagens: "no estoque Loja" (ou "no total do produto").
  String get _ondeAjusta => _nomeDoEstoqueEscolhido == null
      ? 'no total do produto'
      : 'no estoque $_nomeDoEstoqueEscolhido';

  /// Garante um estoque escolhido VÁLIDO: a tela abre no estoque PRINCIPAL da
  /// empresa e volta para ele se a sincronização trocar os estoques daqui
  /// (sem isso o DropdownButtonFormField estoura com "value" fora dos items).
  void _garantirEstoqueEscolhido() {
    final estoques = _ds.estoques;
    if (estoques.isEmpty) {
      _estoqueId = null;
      return;
    }
    if (_estoqueId == null || !estoques.any((e) => e.id == _estoqueId)) {
      _estoqueId = _ds.estoquePrincipalAtual?.id ?? estoques.first.id;
    }
  }

  /// Seletor de Loja/Depósito — e de qualquer estoque cadastrado depois, na
  /// tela de Estoques (FAB "Novo Estoque"). Sem estoques cadastrados, some.
  Widget _seletorDeEstoque() {
    final estoques = _ds.estoques;
    if (estoques.isEmpty) return const SizedBox.shrink();
    // FittedBox como as linhas de regra: em janela estreita a linha inteira
    // encolhe em vez de estourar.
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ESTOQUE AJUSTADO',
              style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                value: _estoqueId,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _input('Loja, Depósito…', Icons.warehouse_outlined),
                items: [
                  for (final e in estoques)
                    DropdownMenuItem<String>(
                      value: e.id,
                      child: Text(
                        e.principal ? '${e.nome} (principal)' : e.nome,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _estoqueId = v;
                  // Os valores digitados item a item eram do estoque anterior:
                  // mantê-los viraria base errada (5 na Loja → 5 no Depósito).
                  _estoqueManual.clear();
                  _estoqueOperadorItem.clear();
                  _geracao++;
                }),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'a coluna EST., os filtros e as regras valem só para ele',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  bool _podeAlterarPreco(BuildContext context) {
    final usuario = Provider.of<AuthService>(context, listen: false).usuarioAtual;
    if (usuario == null) return false;
    if (usuario.isAdmin || usuario.isGerente || usuario.isMaster) return true;
    return PermissionService().temPermissao(usuario, TipoPermissao.produtosAlterarPreco);
  }

  bool _podeVerCusto(BuildContext context) {
    final usuario = Provider.of<AuthService>(context, listen: false).usuarioAtual;
    if (usuario == null) return false;
    if (usuario.isAdmin || usuario.isGerente || usuario.isMaster) return true;
    final ps = PermissionService();
    return ps.temPermissao(usuario, TipoPermissao.produtosVisualizarCusto) ||
        ps.temPermissao(usuario, TipoPermissao.vendasVerCusto);
  }

  void _aplicarRegraGeral({required bool estoque}) {
    final controller = estoque ? _valorEstoqueController : _valorPrecoController;
    final valor = _parseNumero(controller.text);

    if (valor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(estoque ? 'Informe o valor do estoque.' : 'Informe o valor ou o percentual do preço.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final modo = estoque ? _modoEstoque : _modoPreco;
    if (valor < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(modo.ehPercentual
              ? 'O percentual não pode ser negativo — use Aumentar ou Reduzir.'
              : 'Informe um valor positivo — use Somar ou Subtrair para entrar/sair.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      final regra = _RegraAplicada(modo, valor);
      if (estoque) {
        _regraEstoque = regra;
        _estoqueManual.clear();
        _estoqueOperadorItem.clear();
      } else {
        _regraPreco = regra;
        _precoManual.clear();
        _precoOperadorItem.clear();
      }
      _geracao++;
    });
  }

  void _limparRegra({required bool estoque}) {
    setState(() {
      if (estoque) {
        _regraEstoque = null;
        _estoqueManual.clear();
        _estoqueOperadorItem.clear();
      } else {
        _regraPreco = null;
        _precoManual.clear();
        _precoOperadorItem.clear();
      }
      _geracao++;
    });
  }

  void _limparTudo() {
    setState(() {
      _regraEstoque = null;
      _regraPreco = null;
      _estoqueManual.clear();
      _precoManual.clear();
      _estoqueOperadorItem.clear();
      _precoOperadorItem.clear();
      _excluidos.clear();
      _geracao++;
    });
  }

  /// Joga estoque **0** em todos os itens incluídos do lote de uma vez.
  ///
  /// Nada é gravado aqui: os valores caem na tabela para conferência e só
  /// entram no banco quando o usuário toca em APLICAR (e continuam podendo ser
  /// desfeitos depois pelo Histórico de ajustes).
  void _zerarEstoqueDoLote(List<Produto> incluidos) {
    if (incluidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item no lote para zerar.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final comEstoque = incluidos.where((p) => _saldoDe(p).abs() >= 0.0005).length;
    if (comEstoque == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos os itens do lote já estão zerados.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    setState(() {
      _modoEstoque = _ModoAjuste.definir;
      _valorEstoqueController.text = '0';
      _regraEstoque = const _RegraAplicada(_ModoAjuste.definir, 0);
      _estoqueManual.clear();
      _estoqueOperadorItem.clear();
      _geracao++;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Zerando ${_ondeAjusta} de $comEstoque item(ns) do lote. '
          'Confira a tabela e toque em APLICAR para gravar.',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  /// Converte o número digitado na linha no valor final do item: `+` soma ao
  /// valor atual, `−` subtrai e `=` define o novo valor.
  static double _aplicarOperadorItem(_ModoAjuste operador, double digitado, double atual) {
    switch (operador) {
      case _ModoAjuste.somarQuantidade:
        return _round2(atual + digitado);
      case _ModoAjuste.subtrairQuantidade:
        return _round2(atual - digitado);
      default:
        return _round2(digitado);
    }
  }

  /// Operador EFETIVO de cada linha.
  ///
  /// O que o usuário escolheu no próprio item manda; se ele não escolheu nada
  /// na linha, a linha segue o modo da REGRA GERAL do topo — com "Somar
  /// quantidade" escolhido lá, digitar 12 na linha soma 12 (6 → 18), com
  /// "Subtrair quantidade" subtrai e qualquer outro modo define o valor.
  ///
  /// Sem isso o número digitado na linha ia SEMPRE como "define", ou seja, o
  /// valor digitado contradizia o modo escolhido no topo da tela.
  _ModoAjuste _operadorItem(Map<String, _ModoAjuste> operadores, String id,
          {required bool estoque}) =>
      operadores[id] ?? _operadorDaGeral(estoque ? _modoEstoque : _modoPreco);

  /// true quando o item tem operador PRÓPRIO (escolhido na linha); false quando
  /// ele apenas está seguindo a regra geral do topo. Só muda o desenho do
  /// seletor, para o usuário ver o que é escolha dele e o que é herança.
  bool _operadorExplicito(Map<String, _ModoAjuste> operadores, String id) =>
      operadores.containsKey(id);

  /// Modo geral do topo → operador das linhas. Percentual não é operador de
  /// linha (não caberia em "+ / = / −"): nesse caso a linha digitada define o
  /// valor, como sempre foi.
  static _ModoAjuste _operadorDaGeral(_ModoAjuste geral) {
    switch (geral) {
      case _ModoAjuste.somarQuantidade:
        return _ModoAjuste.somarQuantidade;
      case _ModoAjuste.subtrairQuantidade:
        return _ModoAjuste.subtrairQuantidade;
      default:
        return _ModoAjuste.definir;
    }
  }

  /// Lê o que o usuário digitou numa linha da tabela.
  ///
  /// Guarda só o número bruto: quem decide se ele soma, define ou subtrai é o
  /// operador da linha (ver [_aplicarOperadorItem]). O atalho de digitar o sinal
  /// continua valendo e ainda troca o operador da linha: `+20` soma e `-20`
  /// subtrai, exatamente como antes. Célula vazia = não alterar este item (nem
  /// pela regra geral do topo).
  void _editarItemLinha({
    required Map<String, double> digitados,
    required Map<String, _ModoAjuste> operadores,
    required String id,
    required String texto,
    required double atual,
  }) {
    final t = texto.trim();
    if (t.isEmpty) {
      digitados[id] = _round2(atual);
      operadores[id] = _ModoAjuste.definir;
      return;
    }
    final numero = _parseNumero(t);
    if (numero == null) return; // só o '+'/'-' digitado ainda
    if (t.startsWith('+')) {
      operadores[id] = _ModoAjuste.somarQuantidade;
    } else if (t.startsWith('-')) {
      operadores[id] = _ModoAjuste.subtrairQuantidade;
    }
    digitados[id] = _round2(numero.abs());
  }

  /// Fecha o número da linha: o campo passa a mostrar o valor já resolvido e o
  /// operador volta para `=`, para o próximo dígito não somar em cima do total.
  void _resolverItemLinha({
    required Map<String, double> digitados,
    required Map<String, _ModoAjuste> operadores,
    required String id,
    required double alvo,
  }) {
    digitados[id] = _round2(alvo);
    operadores[id] = _ModoAjuste.definir;
    _geracao++;
  }

  double _estoqueAlvo(Produto p) {
    final digitado = _estoqueManual[p.id];
    if (digitado != null) {
      return _aplicarOperadorItem(
          _operadorItem(_estoqueOperadorItem, p.id, estoque: true), digitado, _saldoDe(p));
    }
    return _regraEstoque?.aplicar(_saldoDe(p)) ?? _saldoDe(p);
  }

  /// Preço nunca vai para negativo (o estoque pode — ver [_ModoAjuste]).
  double _precoAlvo(Produto p) {
    final digitado = _precoManual[p.id];
    final alvo = digitado == null
        ? (_regraPreco?.aplicar(p.preco) ?? p.preco)
        : _aplicarOperadorItem(_operadorItem(_precoOperadorItem, p.id, estoque: false), digitado, p.preco);
    return math.max(0, alvo);
  }

  // ==================== APLICAR ====================

  Future<void> _aplicar(List<Produto> incluidos, bool podeAlterarPreco) async {
    final novosEstoques = <String, double>{};
    final novosPrecos = <String, double>{};

    for (final p in incluidos) {
      final estoque = _estoqueAlvo(p);
      if ((estoque - _saldoDe(p)).abs() >= 0.0005) novosEstoques[p.id] = estoque;

      if (podeAlterarPreco) {
        final preco = _precoAlvo(p);
        if ((preco - p.preco).abs() >= 0.005) novosPrecos[p.id] = preco;
      }
    }

    if (novosEstoques.isEmpty && novosPrecos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada para alterar — os valores já estão iguais.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Confirmar ajuste geral', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'Serão gravados:\n'
          '• ${novosEstoques.length} saldo(s) $_ondeAjusta (com movimento no histórico de estoque)\n'
          '• ${novosPrecos.length} preço(s) (registrados no histórico do produto)\n\n'
          'O ajuste fica registrado no Histórico de ajustes e pode ser desfeito depois (com estorno no histórico de estoque).',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            label: const Text('APLICAR AGORA'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final service = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual?.nome ?? authService.usuarioAtual?.email;

    setState(() => _aplicando = true);
    try {
      final resumo = await service.aplicarAjusteEmMassa(
        novosEstoques: novosEstoques,
        novosPrecos: novosPrecos,
        usuario: usuario,
        motivo: 'ajuste',
        observacao: _observacaoController.text.trim(),
        estoqueId: _estoqueId,
      );
      // Lote recém-criado: é o que o botão DESFAZER vai reverter.
      final lote = service.ultimoAjusteLote;
      if (!mounted) return;
      setState(() => _aplicando = false);
      _limparTudo();
      await _mostrarResultado(resumo, lote);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro ao aplicar ajuste: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _mostrarResultado(Map<String, int> resumo, AjusteEstoqueLote? lote) async {
    final desfazer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Ajuste concluído', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _linhaResumo('Estoques ajustados', '${resumo['estoquesAjustados'] ?? 0}', Colors.greenAccent),
            _linhaResumo('  entradas (estoque subiu)', '${resumo['entradas'] ?? 0}', Colors.blueAccent),
            _linhaResumo('  saídas (estoque baixou)', '${resumo['saidas'] ?? 0}', Colors.orangeAccent),
            _linhaResumo('Preços ajustados', '${resumo['precosAjustados'] ?? 0}', Colors.purpleAccent),
            _linhaResumo('Sem alteração', '${resumo['semAlteracao'] ?? 0}', Colors.white54),
            if (lote != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Registrado como ${lote.id} • ${lote.totalItens} item(ns) — '
                  'veja em Histórico de ajustes.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
        actions: [
          if (lote != null && lote.podeSerDesfeito)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('DESFAZER'),
              style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, false),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );

    if (desfazer == true && lote != null && mounted) {
      await _desfazerLote(lote.id);
    }
  }

  // ==================== ZERAR TODO O ESTOQUE ====================

  /// Zera o estoque de **todos** os produtos da empresa (ignora os filtros da
  /// tela). Exige digitar ZERAR na confirmação e fica reversível pelo
  /// Histórico de ajustes.
  Future<void> _zerarTodoEstoque() async {
    final service = Provider.of<DataService>(context, listen: false);
    final comEstoque = service.produtos.where((p) => _saldoDe(p).abs() >= 0.0005).length;

    if (comEstoque == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum produto com estoque para zerar.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }

    final confirmacaoController = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final digitouCerto =
              confirmacaoController.text.trim().toUpperCase() == 'ZERAR';
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                SizedBox(width: 10),
                Text('Zerar TODO o estoque', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Isto zera $_ondeAjusta de TODOS os $comEstoque produtos da empresa — '
                  'o catálogo inteiro, sem usar os filtros desta tela.\n\n'
                  'Cada item entra no histórico de estoque como saída e o conjunto fica '
                  'registrado em Histórico de ajustes, onde dá para DESFAZER depois.\n\n'
                  'Digite ZERAR para liberar o botão:',
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmacaoController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'ZERAR',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever, size: 18),
                onPressed: digitouCerto ? () => Navigator.pop(context, true) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white10,
                  disabledForegroundColor: Colors.white24,
                ),
                label: const Text('ZERAR TUDO'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmado != true || !mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual?.nome ?? authService.usuarioAtual?.email;

    setState(() => _aplicando = true);
    try {
      final resumo = await service.zerarTodoEstoque(usuario: usuario);
      final loteId = service.ultimoAjusteLote?.id;
      if (!mounted) return;
      setState(() => _aplicando = false);
      _limparTudo();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estoque zerado em ${resumo['zerados'] ?? 0} produto(s)'
            '${(resumo['jaZerados'] ?? 0) > 0 ? ' • ${resumo['jaZerados']} já estavam zerados' : ''}.',
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 8),
          action: loteId == null
              ? null
              : SnackBarAction(
                  label: 'DESFAZER',
                  textColor: Colors.white,
                  onPressed: () => _desfazerLote(loteId),
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro ao zerar estoque: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // ==================== HISTÓRICO E DESFAZER ====================

  /// Mostra os ajustes em massa já aplicados e permite desfazer cada lote.
  Future<void> _mostrarHistoricoAjustes() async {
    final service = Provider.of<DataService>(context, listen: false);
    final dataHora = DateFormat('dd/MM/yyyy HH:mm');
    String? loteParaDesfazer;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final lotes = service.ajustesEstoqueLote;
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.history, color: Colors.orangeAccent),
              const SizedBox(width: 10),
              const Text('Histórico de ajustes', style: TextStyle(color: Colors.white, fontSize: 18)),
              const Spacer(),
              Text('${lotes.length} lote(s)', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          content: SizedBox(
            width: 640,
            height: 420,
            child: lotes.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum ajuste registrado ainda.\n'
                      'Cada APLICAR (ajuste em massa, ajuste no cadastro do produto,\n'
                      'inventário ou zerar estoque) cria um lote aqui, com os valores anteriores.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    itemCount: lotes.length,
                    itemBuilder: (context, index) {
                      final lote = lotes[index];
                      final desfeito = lote.desfeito;
                      final cor = desfeito ? Colors.white24 : Colors.orangeAccent;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cor.withOpacity(desfeito ? 0.15 : 0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              desfeito ? Icons.undo_rounded : Icons.tune_rounded,
                              size: 18,
                              color: cor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        dataHora.format(lote.data),
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        lote.usuario ?? 'Sistema',
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.purpleAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          lote.origem,
                                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 10),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        lote.id,
                                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${lote.totalItens} item(ns) • ${lote.totalEstoques} estoque(s) • ${lote.totalPrecos} preço(s)',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                  if (lote.observacao != null && lote.observacao!.trim().isNotEmpty)
                                    Text(
                                      'Obs: ${lote.observacao!.trim()}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                  if (desfeito)
                                    Text(
                                      'Desfeito em ${dataHora.format(lote.dataDesfeito ?? lote.data)}'
                                      '${lote.usuarioDesfeito != null ? ' por ${lote.usuarioDesfeito}' : ''}',
                                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (desfeito)
                              const Text('DESFEITO', style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold))
                            else
                              TextButton.icon(
                                onPressed: () {
                                  loteParaDesfazer = lote.id;
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.undo_rounded, size: 15),
                                label: const Text('DESFAZER', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('FECHAR'),
            ),
          ],
        );
      },
    );

    final alvo = loteParaDesfazer;
    if (alvo != null && mounted) {
      await _desfazerLote(alvo);
      // Reabre o histórico para o usuário ver o lote já marcado como DESFEITO.
      if (mounted) await _mostrarHistoricoAjustes();
    }
  }

  /// Desfaz um lote de ajuste: devolve estoque e preço ao valor anterior.
  Future<void> _desfazerLote(String loteId) async {
    final service = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual?.nome ?? authService.usuarioAtual?.email;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Colors.orangeAccent),
            SizedBox(width: 10),
            Text('Desfazer ajuste', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'O estoque e o preço de cada item do lote $loteId voltam para o valor que tinham antes do ajuste.\n\n'
          'A reversão entra no histórico como estorno (nada é apagado).',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo_rounded, size: 18),
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            label: const Text('DESFAZER AGORA'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _aplicando = true);
    try {
      final resumo = await service.desfazerAjusteEstoqueLote(loteId, usuario: usuario);
      if (!mounted) return;
      setState(() => _aplicando = false);
      // As regras em tela já não valem: os produtos voltaram ao valor anterior.
      _limparTudo();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '↩️ Ajuste desfeito: ${resumo['estoquesRevertidos'] ?? 0} estoque(s) e '
            '${resumo['precosRevertidos'] ?? 0} preço(s) restaurados'
            '${(resumo['ignorados'] ?? 0) > 0 ? ' • ${resumo['ignorados']} ignorado(s)' : ''}.',
          ),
          backgroundColor: Colors.greenAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aplicando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erro ao desfazer ajuste: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _linhaResumo(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(valor, style: TextStyle(color: cor, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _mostrarAjuda() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Ajuste geral: estoque e preço', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text(
          '1) Monte o lote pelos filtros (busca, grupo, fornecedor, unidade, status, faixa de estoque).\n'
          '2) Use as regras gerais: ESTOQUE e PREÇO aceitam Definir valor (ajustar), Somar quantidade,\n'
          '   Subtrair quantidade, Aumentar % ou Reduzir %. Toque em APLICAR A TODOS para jogar a regra nas linhas.\n'
          '3) Ajuste item a item direto na tabela: escolha o operador na PRÓPRIA linha —\n'
          '   + SOMA o número ao valor atual (estoque 5 + 20 = 25), = DEFINE o novo valor (5 = 20)\n'
          '   e − SUBTRAI (5 − 20 = -15). Digitar o sinal na frente (+20 / -20) faz o mesmo.\n'
          '   Com + ou − o campo guarda o número digitado e a seta ao lado (→) mostra o valor final\n'
          '   do item (12 → 18 em um item de 6). Com = o número digitado já é o valor final.\n'
          '   Deixe a célula vazia para não alterar aquele item.\n'
          '4) Desmarque o item para tirá-lo do lote.\n'
          '5) Use ZERAR ESTOQUE para jogar 0 em todos os itens do lote de uma vez (ações reversíveis até tocar em APLICAR).\n'
          '6) Toque em APLICAR para gravar. Só o que ficou diferente é gravado, com registro no histórico de estoque.\n'
          '7) O ícone 🗑 no topo zera o estoque de TODOS os produtos do catálogo (não usa os filtros) —\n'
          '   reversível pelo Histórico de ajustes.\n'
          '8) Cada aplicação cria um lote no Histórico de ajustes (ícone 🕘 no topo). Nele você vê quem aplicou,\n'
          '   quando e o que mudou — e pode DESFAZER, devolvendo estoque e preço ao valor anterior.\n'
          '9) O seletor ESTOQUE AJUSTADO escolhe qual Loja/Depósito a tela mostra e grava — os números da\n'
          '   coluna EST. são os daquele estoque, e é ele que os filtros e as regras usam como base.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('ENTENDI'),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final podeAlterarPreco = _podeAlterarPreco(context);
    _garantirEstoqueEscolhido();
    final lote = _montarLote(service.produtos);
    final incluidos = lote.where((p) => !_excluidos.contains(p.id)).toList();

    final grupos = service.produtos.map(_chaveGrupo).toSet().toList()..sort();
    final fornecedores = service.produtos.map(_chaveFornecedor).toSet().toList()..sort();
    final unidades = service.produtos
        .map((p) => p.unidade.trim().toUpperCase())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    var vaoMudarEstoque = 0, vaoMudarPreco = 0;
    var totalEstoqueNovo = 0.0, impacto = 0.0;
    for (final p in incluidos) {
      final estoque = _estoqueAlvo(p);
      if ((estoque - _saldoDe(p)).abs() >= 0.0005) {
        vaoMudarEstoque++;
        totalEstoqueNovo += estoque;
        impacto += (p.precoCusto ?? 0) * (estoque - _saldoDe(p)).abs();
      }
      if (podeAlterarPreco && (_precoAlvo(p) - p.preco).abs() >= 0.005) vaoMudarPreco++;
    }

    final larguraTela = MediaQuery.of(context).size.width;
    final larguraTabela = math.max(1348.0, larguraTela - 24);

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Ajuste Geral • Estoque e Preço',
          actions: [
            IconButton(
              icon: const Icon(Icons.history, color: Colors.orangeAccent),
              tooltip: 'Histórico de ajustes (e desfazer)',
              onPressed: _aplicando ? null : _mostrarHistoricoAjustes,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Zerar TODO o estoque do catálogo',
              onPressed: _aplicando ? null : _zerarTodoEstoque,
            ),
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white70),
              tooltip: 'Como funciona',
              onPressed: _mostrarAjuda,
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _aplicando,
          child: Column(
            children: [
              if (_aplicando)
                const LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.white10, color: Colors.orangeAccent),
              _buildPainelFiltros(grupos, fornecedores, unidades),
              _buildPainelRegras(lote.length, podeAlterarPreco),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: Scrollbar(
                  controller: _scrollHorizontal,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollHorizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: larguraTabela,
                      child: Column(
                        children: [
                          _buildCabecalhoTabela(),
                          Expanded(
                            child: lote.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Nenhum produto bate com os filtros.',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  )
                                : Scrollbar(
                                    controller: _scrollVertical,
                                    thumbVisibility: true,
                                    child: ListView.builder(
                                      controller: _scrollVertical,
                                      padding: EdgeInsets.zero,
                                      itemCount: lote.length,
                                      itemExtent: _alturaLinha,
                                      itemBuilder: (context, index) => _buildLinha(lote[index], index, podeAlterarPreco),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildRodape(incluidos, lote.length, vaoMudarEstoque, vaoMudarPreco, totalEstoqueNovo, impacto, podeAlterarPreco),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Filtros ----------

  Widget _buildPainelFiltros(List<String> grupos, List<String> fornecedores, List<String> unidades) {
    return Container(
      color: const Color(0xFF14141F),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _filtrosAbertos = !_filtrosAbertos),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, size: 15, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  const Text('FILTROS', style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  const SizedBox(width: 8),
                  if (_filtrosAtivos > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text('$_filtrosAtivos ativo(s)', style: const TextStyle(color: Colors.blueAccent, fontSize: 10)),
                    ),
                  const Spacer(),
                  Text(
                    _filtrosAbertos ? 'recolher' : 'abrir',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  Icon(_filtrosAbertos ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.white38),
                ],
              ),
            ),
          ),
          if (_filtrosAbertos)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _buscaController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: _input('Buscar produto, código ou barras...', Icons.search),
                          onChanged: (v) => setState(() {
                            _busca = v;
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final preset in ['Zerados', 'Até 10', 'Abaixo do mínimo'])
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(preset, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                    backgroundColor: Colors.orangeAccent.withOpacity(0.12),
                                    side: BorderSide(color: Colors.orangeAccent.withOpacity(0.3)),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    avatar: const Icon(Icons.bolt, size: 12, color: Colors.orangeAccent),
                                    onPressed: () => _aplicarPreset(preset),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_filtrosAtivos > 0)
                        TextButton.icon(
                          onPressed: _limparFiltros,
                          icon: const Icon(Icons.clear, size: 14),
                          label: const Text('LIMPAR', style: TextStyle(fontSize: 10)),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(
                        width: 60,
                        child: Text('GRUPOS', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 0.5)),
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: const Text('TODOS', style: TextStyle(fontSize: 10, color: Colors.white)),
                                  selected: _gruposSelecionados.isEmpty,
                                  selectedColor: Colors.purpleAccent.withOpacity(0.35),
                                  backgroundColor: Colors.white.withOpacity(0.05),
                                  showCheckmark: false,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (_) => setState(() => _gruposSelecionados.clear()),
                                ),
                              ),
                              for (final g in grupos)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: Text(g, style: const TextStyle(fontSize: 10, color: Colors.white)),
                                    selected: _gruposSelecionados.contains(g),
                                    selectedColor: Colors.purpleAccent.withOpacity(0.35),
                                    backgroundColor: Colors.white.withOpacity(0.05),
                                    showCheckmark: false,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onSelected: (sel) => setState(() {
                                      if (sel) {
                                        _gruposSelecionados.add(g);
                                      } else {
                                        _gruposSelecionados.remove(g);
                                      }
                                      _excluidos.clear();
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _dropdown<String>(
                          label: 'Fornecedor',
                          valor: _fornecedorSelecionado,
                          itens: fornecedores,
                          rotuloTodos: 'Todos os fornecedores',
                          onChanged: (v) => setState(() {
                            _fornecedorSelecionado = v;
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _dropdown<String>(
                          label: 'Unidade',
                          valor: _unidadeSelecionada,
                          itens: unidades,
                          rotuloTodos: 'Todas as unidades',
                          onChanged: (v) => setState(() {
                            _unidadeSelecionada = v;
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _dropdown<bool>(
                          label: 'Status no PDV',
                          valor: _statusAtivo,
                          itens: const [true, false],
                          rotuloTodos: 'Ativos e desativados',
                          rotuloItem: (v) => v ? 'Somente ativos' : 'Somente desativados',
                          onChanged: (v) => setState(() {
                            _statusAtivo = v;
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _deController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: _input('Estoque de', null),
                          onChanged: (_) => setState(() {
                            _sincronizarFaixaEstoque();
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 12, color: Colors.white24),
                      ),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _ateController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: _input('Estoque até', null),
                          onChanged: (_) => setState(() {
                            _sincronizarFaixaEstoque();
                            _excluidos.clear();
                          }),
                        ),
                      ),
                      if (_abaixoDoMinimo)
                        const Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Text('• abaixo do mínimo', style: TextStyle(color: Colors.orangeAccent, fontSize: 10)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Regras gerais ----------

  Widget _buildPainelRegras(int totalLote, bool podeAlterarPreco) {
    return Container(
      color: const Color(0xFF191926),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          _seletorDeEstoque(),
          const SizedBox(height: 6),
          _linhaRegra(
            label: 'ESTOQUE',
            cor: Colors.blueAccent,
            modo: _modoEstoque,
            controller: _valorEstoqueController,
            regra: _regraEstoque,
            hint: _hintModo(_modoEstoque, estoque: true),
            onModo: (m) => setState(() => _modoEstoque = m ?? _ModoAjuste.definir),
            onAplicar: () => _aplicarRegraGeral(estoque: true),
            onLimpar: () => _limparRegra(estoque: true),
            totalLote: totalLote,
          ),
          const SizedBox(height: 6),
          _linhaRegra(
            label: 'PREÇO',
            cor: Colors.purpleAccent,
            modo: _modoPreco,
            controller: _valorPrecoController,
            regra: _regraPreco,
            hint: _hintModo(_modoPreco, estoque: false),
            habilitado: podeAlterarPreco,
            onModo: (m) => setState(() => _modoPreco = m ?? _ModoAjuste.definir),
            onAplicar: () => _aplicarRegraGeral(estoque: false),
            onLimpar: () => _limparRegra(estoque: false),
            totalLote: totalLote,
          ),
        ],
      ),
    );
  }

  Widget _linhaRegra({
    required String label,
    required Color cor,
    required _ModoAjuste modo,
    required TextEditingController controller,
    required _RegraAplicada? regra,
    required String hint,
    required ValueChanged<_ModoAjuste?> onModo,
    required VoidCallback onAplicar,
    required VoidCallback onLimpar,
    required int totalLote,
    bool habilitado = true,
  }) {
    // FittedBox evita estouro em janelas estreitas (escala levemente a linha).
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
        ),
        SizedBox(
          width: 156,
          child: DropdownButtonFormField<_ModoAjuste>(
            value: modo,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E2E),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _input(null, null),
            items: _ModoAjuste.values
                .map((m) => DropdownMenuItem<_ModoAjuste>(
                      value: m,
                      child: Text(m.rotulo, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ))
                .toList(),
            onChanged: habilitado ? onModo : null,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: controller,
            enabled: habilitado,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            decoration: _input(hint, null),
            onSubmitted: (_) => onAplicar(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          child: ElevatedButton.icon(
            onPressed: habilitado ? onAplicar : null,
            icon: const Icon(Icons.arrow_downward, size: 14),
            label: Text('APLICAR A TODOS ($totalLote)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: cor.withOpacity(0.22),
              foregroundColor: cor,
              disabledBackgroundColor: Colors.white10,
              disabledForegroundColor: Colors.white24,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (regra != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cor.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 12, color: cor),
                const SizedBox(width: 4),
                Text(regra.descricao, style: TextStyle(color: cor, fontSize: 11)),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onLimpar,
                  child: Icon(Icons.close, size: 13, color: cor),
                ),
              ],
            ),
          )
        else
          Text(
            _descricaoModo(modo),
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
          ],
        ),
      ),
    );
  }

  /// Texto de exemplo do campo de valor, conforme o modo escolhido.
  String _hintModo(_ModoAjuste modo, {required bool estoque}) {
    switch (modo) {
      case _ModoAjuste.definir:
        return estoque ? 'novo valor' : 'novo preço';
      case _ModoAjuste.somarQuantidade:
        return estoque ? 'qtde a somar' : 'R\$ a somar';
      case _ModoAjuste.subtrairQuantidade:
        return estoque ? 'qtde a subtrair' : 'R\$ a subtrair';
      case _ModoAjuste.aumentarPercentual:
        return estoque ? '% de aumento' : '% de reajuste';
      case _ModoAjuste.reduzirPercentual:
        return estoque ? '% de redução' : '% de desconto';
    }
  }

  static String _descricaoModo(_ModoAjuste modo) {
    switch (modo) {
      case _ModoAjuste.definir:
        return 'define o valor final de cada item';
      case _ModoAjuste.somarQuantidade:
        return 'soma a quantidade ao valor de cada item';
      case _ModoAjuste.subtrairQuantidade:
        return 'subtrai a quantidade do valor de cada item';
      case _ModoAjuste.aumentarPercentual:
        return 'aplica % de aumento sobre o valor de cada item';
      case _ModoAjuste.reduzirPercentual:
        return 'aplica % de redução sobre o valor de cada item';
    }
  }

  // ---------- Tabela ----------

  Widget _buildCabecalhoTabela() {
    return Container(
      height: 28,
      color: const Color(0xFF202033),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: _wCheck),
          _th('CÓD', _wCod, align: TextAlign.left),
          const Expanded(child: Padding(padding: EdgeInsets.only(left: 4), child: Text('PRODUTO', style: _estiloTh))),
          _th('GRUPO', _wGrupo),
          _th(_nomeDoEstoqueEscolhido == null
              ? 'EST. ATUAL'
              : 'EST. ${_nomeDoEstoqueEscolhido!.toUpperCase()}', _wAtual, align: TextAlign.right),
          _th('OP.', _wOp, tooltip: _ajudaOperadorItem),
          const SizedBox(width: 4),
          _th('NOVO', _wInput + 4 + _wPrevia, tooltip: _ajudaCampoNovo),
          _th('PREÇO', _wPrecoAtual, align: TextAlign.right),
          _th('OP.', _wOp, tooltip: _ajudaOperadorItem),
          const SizedBox(width: 4),
          _th('NOVO', _wPrecoInput + 4 + _wPrevia, tooltip: _ajudaCampoNovo),
          _th('Δ EST.', _wDiff, align: TextAlign.right, tooltip: _ajudaDelta),
          _th('Δ PREÇO', _wDiff, align: TextAlign.right, tooltip: _ajudaDelta),
        ],
      ),
    );
  }

  static const TextStyle _estiloTh = TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6);

  /// Texto do cabeçalho OP. (e dos tooltips dos botões de cada linha).
  static const String _ajudaOperadorItem =
      'Como o número digitado entra em cada item:\n'
      '+ soma ao valor atual  •  = define o novo valor  •  − subtrai do valor atual\n'
      'Sem escolher nada na linha, o item segue o modo da regra geral '
      '(ESTOQUE / PREÇO) lá no topo.';

  /// Texto do cabeçalho NOVO: o campo guarda o número digitado e a seta mostra
  /// em quanto o item vai ficar depois de aplicar o operador.
  static const String _ajudaCampoNovo =
      'O campo guarda o número digitado.\n'
      'A seta (→) mostra o valor final do item depois do operador: '
      '12 com + em um item de 6 vira → 18.\n'
      'Com = o número já é o valor final, então não há seta.';

  /// Texto do cabeçalho Δ: mostra a variação, não o valor final.
  static const String _ajudaDelta =
      'Variação do item (não é o valor final):\n'
      'Δ = valor novo − valor atual.\n'
      'Ex.: um item com saldo −2 que vai para 2 tem Δ +4.';


  Widget _th(String texto, double largura, {TextAlign align = TextAlign.center, String? tooltip}) {
    final rotulo = Text(texto, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis, style: _estiloTh);
    return SizedBox(
      width: largura,
      child: tooltip == null ? rotulo : Tooltip(message: tooltip, child: rotulo),
    );
  }

  Widget _buildLinha(Produto p, int index, bool podeAlterarPreco) {
    final incluido = !_excluidos.contains(p.id);
    final estoqueAlvo = _estoqueAlvo(p);
    final precoAlvo = _precoAlvo(p);
    final difEstoque = estoqueAlvo - _saldoDe(p);
    final difPreco = podeAlterarPreco ? precoAlvo - p.preco : 0.0;

    // Com +/− o campo guarda a quantidade digitada (não o saldo final), então a
    // linha mostra uma prévia ("12 → 18") para não parecer que o item ficará
    // com o número digitado. Com = o próprio campo já é o valor final.
    final previaEstoque = (_estoqueManual[p.id] != null &&
            _operadorItem(_estoqueOperadorItem, p.id, estoque: true) != _ModoAjuste.definir)
        ? estoqueAlvo
        : null;
    final previaPreco = (_precoManual[p.id] != null &&
            _operadorItem(_precoOperadorItem, p.id, estoque: false) != _ModoAjuste.definir)
        ? precoAlvo
        : null;
    final mudouEstoque = difEstoque.abs() >= 0.0005;
    final mudouPreco = podeAlterarPreco && difPreco.abs() >= 0.005;

    final corEstoque = !mudouEstoque ? Colors.white38 : (difEstoque > 0 ? Colors.blueAccent : Colors.orangeAccent);
    final corPreco = !mudouPreco ? Colors.white38 : (difPreco > 0 ? Colors.greenAccent : Colors.redAccent);

    return Opacity(
      opacity: incluido ? 1 : 0.38,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: index.isEven ? Colors.white.withOpacity(0.022) : Colors.transparent,
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: _wCheck,
              child: Checkbox(
                value: incluido,
                activeColor: Colors.blueAccent,
                side: const BorderSide(color: Colors.white24),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _excluidos.remove(p.id);
                  } else {
                    _excluidos.add(p.id);
                  }
                }),
              ),
            ),
            SizedBox(
              width: _wCod,
              child: Text(
                p.codigo?.replaceAll('COD-', '') ?? '—',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    if (!p.ativo)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text('OFF', style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _wGrupo,
              child: Text(
                _chaveGrupo(p),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.purpleAccent, fontSize: 10),
              ),
            ),
            SizedBox(
              width: _wAtual,
              child: Text(
                '${_num.format(_saldoDe(p))}${p.unidade.isNotEmpty ? ' ${p.unidade}' : ''}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            SizedBox(
              width: _wCelulaValor,
              child: _campoValor(
                key: ValueKey('est_${p.id}_$_geracao'),
                valor: estoqueAlvo,
                operador: _operadorItem(_estoqueOperadorItem, p.id, estoque: true),
                estoque: true,
                explicito: _operadorExplicito(_estoqueOperadorItem, p.id),
                cor: corEstoque,
                previa: previaEstoque,
                onOperador: (m) => setState(() => _estoqueOperadorItem[p.id] = m),
                onTexto: (texto) => setState(() => _editarItemLinha(
                      digitados: _estoqueManual,
                      operadores: _estoqueOperadorItem,
                      id: p.id,
                      texto: texto,
                      atual: _saldoDe(p),
                    )),
                onResolver: () => setState(() => _resolverItemLinha(
                      digitados: _estoqueManual,
                      operadores: _estoqueOperadorItem,
                      id: p.id,
                      alvo: estoqueAlvo,
                    )),
              ),
            ),
            SizedBox(
              width: _wPrecoAtual,
              child: Text(
                _moeda.format(p.preco),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            SizedBox(
              width: _wCelulaPreco,
              child: podeAlterarPreco
                  ? _campoValor(
                      key: ValueKey('pre_${p.id}_$_geracao'),
                      valor: precoAlvo,
                      operador: _operadorItem(_precoOperadorItem, p.id, estoque: false),
                      estoque: false,
                      explicito: _operadorExplicito(_precoOperadorItem, p.id),
                      cor: corPreco,
                      previa: previaPreco,
                      onOperador: (m) => setState(() => _precoOperadorItem[p.id] = m),
                      onTexto: (texto) => setState(() => _editarItemLinha(
                            digitados: _precoManual,
                            operadores: _precoOperadorItem,
                            id: p.id,
                            texto: texto,
                            atual: p.preco,
                          )),
                      onResolver: () => setState(() => _resolverItemLinha(
                            digitados: _precoManual,
                            operadores: _precoOperadorItem,
                            id: p.id,
                            alvo: precoAlvo,
                          )),
                    )
                  : const Center(child: Icon(Icons.lock_outline, size: 13, color: Colors.white24)),
            ),
            SizedBox(
              width: _wDiff,
              child: Text(
                !mudouEstoque ? '—' : '${difEstoque > 0 ? '+' : ''}${_num.format(difEstoque)}',
                textAlign: TextAlign.right,
                style: TextStyle(color: corEstoque, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
              width: _wDiff,
              child: Text(
                !mudouPreco ? '—' : '${difPreco > 0 ? '+' : ''}${_num.format(difPreco)}',
                textAlign: TextAlign.right,
                style: TextStyle(color: corPreco, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Os operadores que o usuário pode escolher NA LINHA (sem percentual).
  static const List<_ModoAjuste> _operadoresItem = [
    _ModoAjuste.somarQuantidade,
    _ModoAjuste.definir,
    _ModoAjuste.subtrairQuantidade,
  ];

  static String _simboloOperador(_ModoAjuste operador) {
    switch (operador) {
      case _ModoAjuste.somarQuantidade:
        return '+';
      case _ModoAjuste.subtrairQuantidade:
        return '−';
      default:
        return '=';
    }
  }

  static String _descricaoOperador(_ModoAjuste operador, {required bool estoque}) {
    switch (operador) {
      case _ModoAjuste.somarQuantidade:
        return estoque
            ? 'Somar a quantidade digitada ao saldo do item'
            : 'Somar o valor digitado ao preço do item';
      case _ModoAjuste.subtrairQuantidade:
        return estoque
            ? 'Subtrair a quantidade digitada do saldo do item'
            : 'Subtrair o valor digitado do preço do item';
      default:
        return estoque ? 'Definir o novo saldo do item' : 'Definir o novo preço do item';
    }
  }

  /// Seletor + / = / − que fica em cada linha, antes do campo NOVO.
  ///
  /// Escolher aqui é o mesmo que escolher no topo da tela, só que para um item
  /// só: `+` soma ao valor atual, `=` define o novo valor e `−` subtrai.
  Widget _seletorOperadorItem({
    required _ModoAjuste operador,
    required bool estoque,
    required Color cor,
    required bool explicito,
    required ValueChanged<_ModoAjuste> onOperador,
  }) {
    return SizedBox(
      width: _wOp,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final modo in _operadoresItem)
            Tooltip(
              message: (modo == operador && !explicito)
                  ? '${_descricaoOperador(modo, estoque: estoque)}\n'
                      'Vem da regra geral do topo — clique para fixar só neste item.'
                  : _descricaoOperador(modo, estoque: estoque),
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => onOperador(modo),
                child: Container(
                  width: 16,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: modo == operador ? cor.withOpacity(0.22) : Colors.white.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: modo == operador
                          ? cor.withOpacity(0.7)
                          : Colors.white.withOpacity(0.16),
                    ),
                  ),
                  child: Text(
                    _simboloOperador(modo),
                    style: TextStyle(
                      color: modo == operador ? cor : Colors.white60,
                      fontSize: 13,
                      height: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Campo de valor da tabela, com o operador da linha escolhido ao lado.
  ///
  /// O número digitado entra conforme o operador do item: `20` com `+` soma 20
  /// ao saldo atual (5 → 25), com `−` subtrai (5 → -15) e com `=` define o novo
  /// valor (5 → 20). Digitar o sinal na frente (`+20` / `-20`) é atalho para a
  /// mesma coisa e ainda troca o operador da linha. Célula vazia = não alterar
  /// este item, e Enter "fecha" o número (o campo passa a mostrar o valor
  /// resolvido, com o operador voltando para `=`).
  ///
  /// Quando o operador é `+`/`−`, o campo guarda a quantidade digitada e não o
  /// valor final — por isso `previa` recebe esse valor final e a linha mostra
  /// "→ 18" ao lado, deixando claro em quanto o item vai ficar. Com `=` não há
  /// dúvida (o campo já é o valor final), então `previa` vem nulo.
  Widget _campoValor({
    required Key key,
    required double valor,
    required _ModoAjuste operador,
    required bool estoque,
    required Color cor,
    required double? previa,
    required bool explicito,
    required ValueChanged<_ModoAjuste> onOperador,
    required ValueChanged<String> onTexto,
    required VoidCallback onResolver,
  }) {
    return Row(
      children: [
        _seletorOperadorItem(
          operador: operador,
          estoque: estoque,
          cor: cor,
          explicito: explicito,
          onOperador: onOperador,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 30,
            child: TextFormField(
              key: key,
              initialValue: _num.format(_round2(valor)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              // Aceita '+'/'-' para somar/subtrair do valor atual do produto.
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+-]'))],
              textAlign: TextAlign.right,
              // Enter "fecha" o valor: a célula passa a mostrar o número resolvido
              // (ex.: depois de digitar +20 com estoque 5, mostra 25).
              onFieldSubmitted: (_) => onResolver(),
              style: TextStyle(color: cor == Colors.white38 ? Colors.white : cor, fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cor, width: 1)),
              ),
              onChanged: onTexto,
            ),
          ),
        ),
        // Respiro + prévia sempre reservados, para o campo ficar do mesmo
        // tamanho em todas as linhas (mesmo nas que não têm prévia).
        const SizedBox(width: 4),
        SizedBox(
          width: _wPrevia,
          child: previa == null
              ? null
              : Text(
                  '→ ${_num.format(_round2(previa))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: cor == Colors.white38 ? Colors.white54 : cor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  // ---------- Rodapé ----------

  Widget _buildRodape(
    List<Produto> incluidos,
    int totalLote,
    int vaoMudarEstoque,
    int vaoMudarPreco,
    double totalEstoqueNovo,
    double impacto,
    bool podeAlterarPreco,
  ) {
    final podeVerCusto = _podeVerCusto(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF14141F),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${incluidos.length} de $totalLote itens'
              '  •  $vaoMudarEstoque estoque(s)'
              '${podeAlterarPreco ? '  •  $vaoMudarPreco preço(s)' : ''}'
              '${vaoMudarEstoque > 0 ? '  •  novo saldo ${_ondeAjusta} ${_num.format(_round2(totalEstoqueNovo))}' : ''}'
              '${podeVerCusto && impacto > 0 ? '  •  impacto a custo ${_moeda.format(impacto)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 230,
            child: TextField(
              controller: _observacaoController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: _input('Observação (motivo do ajuste)', Icons.notes),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: (_aplicando || incluidos.isEmpty) ? null : () => _zerarEstoqueDoLote(incluidos),
            icon: const Icon(Icons.delete_sweep_outlined, size: 15),
            label: const Text('ZERAR ESTOQUE', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _aplicando ? null : _limparTudo,
            icon: const Icon(Icons.restart_alt, size: 15),
            label: const Text('LIMPAR EDIÇÕES', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
          const SizedBox(width: 8),
          SizedBox(
            child: ElevatedButton.icon(
              onPressed: (_aplicando || (vaoMudarEstoque == 0 && vaoMudarPreco == 0)) ? null : () => _aplicar(incluidos, podeAlterarPreco),
              icon: _aplicando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.save_alt_rounded, size: 17),
              label: Text(
                'APLICAR${vaoMudarEstoque + vaoMudarPreco > 0 ? ' (${vaoMudarEstoque + vaoMudarPreco})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Auxiliares ----------

  InputDecoration _input(String? hint, IconData? icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
      prefixIcon: icon == null ? null : Icon(icon, size: 16, color: Colors.white38),
      prefixIconConstraints: const BoxConstraints(minWidth: 30),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? valor,
    required List<T> itens,
    required ValueChanged<T?> onChanged,
    required String rotuloTodos,
    String Function(T)? rotuloItem,
  }) {
    return SizedBox(
      child: DropdownButtonFormField<T?>(
        value: valor,
        isExpanded: true,
        dropdownColor: const Color(0xFF1E1E2E),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: _input(label, null),
        items: [
          DropdownMenuItem<T?>(value: null, child: Text(rotuloTodos, style: const TextStyle(color: Colors.white38, fontSize: 12))),
          ...itens.map((i) => DropdownMenuItem<T?>(
                value: i,
                child: Text(rotuloItem?.call(i) ?? i.toString(), style: const TextStyle(color: Colors.white, fontSize: 12)),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
