import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/caixa.dart';
import '../models/forma_pagamento.dart';
import '../theme.dart';
import 'home_page.dart';
import '../widgets/sync_status_widget.dart';
import '../services/caixa_pdf_service.dart';
import '../services/caixa_fluxo_export_service.dart';
import '../services/caixa_mov_filtro_service.dart';
import '../services/auth_service.dart';
import '../widgets/permission_widget.dart';
import '../models/venda_balcao.dart';
import '../models/empresa.dart';
import '../models/usuario.dart';
import 'package:printing/printing.dart';
import '../models/mesa_comanda.dart';


/// Página de gerenciamento de caixa
class CaixaPage extends StatefulWidget {
  const CaixaPage({super.key});

  @override
  State<CaixaPage> createState() => _CaixaPageState();
}

class _CaixaPageState extends State<CaixaPage> {
  final NumberFormat formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final DateFormat formatoData = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat formatoHora = DateFormat('HH:mm');

  String? _responsavelSelecionado;
  bool _responsavelInicializado = false;

  // Filtros do Histórico de Encerramentos
  DateTime? _filtroDataInicio;
  DateTime? _filtroDataFim;
  String _filtroNumeroCaixa = 'Todos';
  // Só caixas com diferença entre o esperado e o contado — é o que o gestor
  // mais precisa achar rapidamente no histórico.
  bool _filtroSomenteDivergentes = false;

  /// Tolerância (R$) para considerar um fechamento como divergente.
  static const double _toleranciaDivergencia = 0.005;

  // Filtros do Fluxo de Caixa (Movimentações do Dia)
  final TextEditingController _buscaFluxoController = TextEditingController();
  String _termoBuscaFluxo = '';
  String _filtroTipoFluxo = 'Todos';
  TipoPagamento? _filtroFormaFluxo; // null = todas as formas de pagamento
  bool _mostrarTodosCaixas = false;
  // Janela de horário do Fluxo de Caixa, em minutos desde a meia-noite
  // (08:30 → 510). Só filtra quando os DOIS extremos foram escolhidos —
  // mesma regra do modal de movimentações de um caixa encerrado.
  int? _horaInicioFluxoMin;
  int? _horaFimFluxoMin;

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    // Operador/funcionário sem permissão (dashboard.ver_totais) não vê o total
    // de vendas/entradas do caixa — apenas o saldo para operar.
    final podeVerTotais = PermissionHelper.podeVerTotais(usuarioLogado);
    // Detalhamento por forma de pagamento (Dinheiro, PIX, Cartão...) é controlado
    // por permissão própria (caixa.ver_totais_formas_pagamento).
    final podeVerFormasPagamento =
        PermissionHelper.podeVerTotaisFormasPagamento(usuarioLogado);
    // Operador/funcionário sem permissão (caixa.ver_fluxo_caixa) não vê a tela
    // de Fluxo de Caixa (entradas, saídas e histórico de encerramentos).
    final podeVerFluxoCaixa = PermissionHelper.podeVerFluxoCaixa(usuarioLogado);

    if (!_responsavelInicializado && usuarioLogado != null) {
      _responsavelSelecionado = usuarioLogado.email.isNotEmpty ? usuarioLogado.email : usuarioLogado.nome;
      dataService.responsavelAtivo = _responsavelSelecionado;
      _responsavelInicializado = true;
    } else if (_responsavelInicializado) {
      dataService.responsavelAtivo = _responsavelSelecionado;
    }

    // Sem a permissão caixa.ver_fluxo_caixa, a tela de Fluxo de Caixa fica
    // bloqueada (o operador não vê entradas, saídas nem histórico).
    if (!podeVerFluxoCaixa) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Fluxo de Caixa'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: const [SyncStatusWidget()],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, color: Colors.white30, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Acesso restrito',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Você não tem permissão para visualizar o Fluxo de Caixa.\nSolicite a liberação ao administrador.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Fluxo de Caixa'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: const [SyncStatusWidget()],
        ),
        body: Consumer<DataService>(
          builder: (context, dataService, child) {
            final caixaAberto = dataService.caixaAberto;
            final aberturaAtual = dataService.aberturaCaixaAtual;
            final aberturasAbertas = dataService.aberturasCaixaAbertas;

            // Movimentações do fluxo calculadas UMA vez por build. Antes a barra
            // de filtros e a lista chamavam `_movimentacoesFluxoBase` cada uma,
            // varrendo vendas, mesas/comandas e sangrias duas vezes por rebuild.
            final movsFluxoBase = (caixaAberto && aberturaAtual != null)
                ? _movimentacoesFluxoBase(dataService, aberturaAtual)
                : <Map<String, dynamic>>[];
            final movsFluxoFiltradas = _filtrarFluxo(movsFluxoBase);

            // Conjunto único de identificadores de operadores (E-mail ou Nome)
            final Set<String> todosOperadores = {};
            if (usuarioLogado != null) {
              todosOperadores.add(usuarioLogado.email.isNotEmpty ? usuarioLogado.email : usuarioLogado.nome);
            }
            for (final f in dataService.funcionarios) {
              final idVal = (f.email != null && f.email!.isNotEmpty) ? f.email! : f.nome;
              if (idVal.isNotEmpty) {
                todosOperadores.add(idVal);
              }
            }
            for (final a in dataService.aberturasCaixa) {
              if (a.responsavel != null && a.responsavel!.isNotEmpty) {
                todosOperadores.add(a.responsavel!);
              }
            }

            return CustomScrollView(
              slivers: [
                // 0. Dropdown de Operadores (visível para Administradores e Gerentes)
                if (usuarioLogado != null && (usuarioLogado.isAdmin || usuarioLogado.isMaster || usuarioLogado.isGerente || usuarioLogado.email.toLowerCase() == 'user'))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_search_rounded, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 12),
                            const Text(
                              'Visualizar Caixa de:',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  dropdownColor: const Color(0xFF1E1E2E),
                                  value: _responsavelSelecionado,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                  items: todosOperadores.map((operador) {
                                    // Obter nome amigável para exibição (ex: se for e-mail, tenta achar o nome do funcionário correspondente)
                                    String nomeExibicao = operador;
                                    if (operador.contains('@')) {
                                      final func = dataService.funcionarios.firstWhereOrNull(
                                        (f) => f.email?.toLowerCase() == operador.toLowerCase(),
                                      );
                                      if (func != null) {
                                        nomeExibicao = func.nome;
                                      } else if (usuarioLogado != null && usuarioLogado.email.toLowerCase() == operador.toLowerCase()) {
                                        nomeExibicao = usuarioLogado.nome;
                                      }
                                    }
                                    return DropdownMenuItem<String>(
                                      value: operador,
                                      child: Text(nomeExibicao),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _responsavelSelecionado = val;
                                        dataService.responsavelAtivo = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 0.5. Todos os caixas abertos (um por usuário da empresa)
                if (aberturasAbertas.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _buildCaixasAbertosSection(dataService, aberturasAbertas, usuarioLogado),
                    ),
                  ),

                // 1. Card de Status do Caixa
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildStatusHeader(caixaAberto, aberturaAtual, dataService),
                  ),
                ),

                // 2. Seção de Resumo (Apenas se aberto)
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildResumoSession(
                          dataService, aberturaAtual, podeVerTotais, podeVerFormasPagamento),
                    ),
                  ),

                // 3. Filtros do Fluxo de Caixa (tipos + busca)
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: _buildFiltrosFluxo(movsFluxoBase, aberturaAtual),
                    ),
                  ),

                // 4. Título do Fluxo de Caixa Atual
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Movimentações do Dia',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Sessão Atual',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 5. Lista do Fluxo de Caixa Atual
                if (caixaAberto && aberturaAtual != null)
                  _buildSliverFluxoLista(movsFluxoFiltradas),

                // 5.1 Total do que está sendo exibido (respeita os filtros)
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _buildTotalFluxo(movsFluxoFiltradas),
                    ),
                  ),

                // 5. Histórico Separador
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                    child: Text(
                      'Histórico de Encerramentos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 6. Lista do Histórico
                // 5.5 Filtros do Histórico
                if (dataService.fechamentosCaixa.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildFiltrosHistorico(dataService),
                    ),
                  ),

                // 6. Lista do Histórico
                _buildSliverHistorico(dataService, podeVerTotais),
                
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Seção com TODOS os caixas abertos da empresa (um por usuário).
  ///
  /// Operador comum (não gestor) SÓ vê os caixas abertos dele mesmo — antes a
  /// seção listava todos os caixas de todos os usuários da empresa (ex.: o
  /// CAIXA-037 do 'user' aparecia para o carlos, que achava que era o caixa dele).
  Widget _buildCaixasAbertosSection(DataService ds, List<AberturaCaixa> abertas, Usuario? usuarioLogado) {
    final ehGestor = usuarioLogado != null &&
        (usuarioLogado.isAdmin ||
            usuarioLogado.isMaster ||
            usuarioLogado.isGerente ||
            usuarioLogado.email.toLowerCase() == 'user');

    // Filtro para operador: só caixas abertos do próprio operador.
    final exibir = !ehGestor
        ? abertas.where((ab) {
            if (ab.responsavel == null || ab.responsavel!.trim().isEmpty) return false;
            final idLogado = usuarioLogado!.email.isNotEmpty
                ? usuarioLogado.email
                : usuarioLogado.nome;
            String norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9@]'), '');
            final na = norm(ab.responsavel!);
            final nb = norm(idLogado);
            if (na.isEmpty || nb.isEmpty) return false;
            if (na == nb) return true;
            final localA = na.contains('@') ? na.split('@').first : na;
            final localB = nb.contains('@') ? nb.split('@').first : nb;
            return localA == localB && localA.isNotEmpty;
          }).toList()
        : abertas;

    if (exibir.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.blueAccent, size: 22),
            const SizedBox(width: 10),
            Text(
              'Caixas Abertos (${exibir.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...exibir.map((ab) => _buildCardCaixaAberto(ds, ab, ehGestor)),
      ],
    );
  }

  Widget _buildCardCaixaAberto(DataService ds, AberturaCaixa ab, bool ehGestor) {
    final saldo = ds.calcularSaldoDoCaixa(ab);
    final ehSelecionado = ds.aberturaCaixaAtual?.id == ab.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ehSelecionado
            ? Colors.blueAccent.withOpacity(0.12)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ehSelecionado
              ? Colors.blueAccent.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ehSelecionado ? Icons.lock_open_rounded : Icons.account_balance_rounded,
            color: ehSelecionado ? Colors.blueAccent : Colors.white54,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ab.numero}${ab.responsavel != null && ab.responsavel!.isNotEmpty ? ' • ${ab.responsavel}' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saldo: ${formatoMoeda.format(saldo)}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Aberto ${formatoData.format(ab.dataAbertura.toLocal())}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          if (ehGestor)
            IconButton(
              icon: const Icon(Icons.visibility, color: Colors.blueAccent, size: 20),
              tooltip: 'Ver o que foi vendido neste caixa',
              onPressed: () => _mostrarVendasDoCaixa(ds, ab),
            ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 20),
            tooltip: 'Fechar este caixa',
            onPressed: () => _mostrarDialogoFechamento(context, ds, aberturaParam: ab),
          ),
        ],
      ),
    );
  }

  /// Abre o modal com as vendas realizadas em um caixa (o que foi vendido)
  void _mostrarVendasDoCaixa(DataService ds, AberturaCaixa ab,
      {FechamentoCaixa? fechamento}) {
    // Para caixas ja fechados, limita as vendas ate o encerramento
    final vendas = ds.getVendasDoCaixa(ab)
        .where((v) => fechamento == null ||
            v.dataVenda.isBefore(
                fechamento!.dataFechamento.add(const Duration(seconds: 1))))
        .toList();
    final totalVendas = vendas.fold<double>(0.0, (sum, v) => sum + v.valorTotal);
    final nomeResp = ab.responsavel ?? '—';
    final titulo = 'Vendas do ' + ab.numero;
    // Data e hora de abertura (e de fechamento, quando encerrado): sem isso o
    // gestor não sabe a qual sessão de caixa as vendas pertencem.
    final fechado = fechamento;
    final periodo = fechado == null
        ? 'Abertura: ${formatoData.format(ab.dataAbertura.toLocal())}'
        : 'Abertura: ${formatoData.format(ab.dataAbertura.toLocal())} → '
            '${formatoData.format(fechado.dataFechamento.toLocal())}';
    final subtitulo = periodo +
        ' • ' + nomeResp +
        ' • ' + vendas.length.toString() + ' venda(s) • Total: ' +
        formatoMoeda.format(totalVendas);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_basket_rounded, color: Colors.blueAccent, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titulo,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(subtitulo,
                              style: TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: vendas.isEmpty
                    ? Center(
                        child: Text('Nenhuma venda neste caixa',
                            style: TextStyle(color: Colors.white30)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: vendas.length,
                        itemBuilder: (context, i) {
                          final v = vendas[i];
                          return _buildCardVendaModal(v);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardVendaModal(VendaBalcao v) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Venda ' + v.numero,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatForma(v.tipoPagamento),
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatoData.format(v.dataVenda.toLocal()),
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          ...v.itens.map((item) {
            final qtdStr = item.quantidade % 1 == 0
                ? item.quantidade.toStringAsFixed(0)
                : item.quantidade.toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.nome,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(qtdStr + 'x', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(width: 12),
                  Text(
                    formatoMoeda.format(item.subtotal),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
          const Divider(color: Colors.white12, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Total', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 12),
              Text(
                formatoMoeda.format(v.valorTotal),
                style: const TextStyle(color: Colors.greenAccent, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(bool aberto, AberturaCaixa? abertura, DataService ds) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: aberto
              ? [Colors.blueAccent.withOpacity(0.4), Colors.blue.withOpacity(0.1)]
              : [Colors.grey.withOpacity(0.3), Colors.black.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: aberto ? Colors.blueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (aberto ? Colors.blueAccent : Colors.black).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                _buildAnimatedIcon(aberto),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aberto ? 'Caixa Operacional${abertura?.responsavel != null ? " • Operador: ${abertura!.responsavel}" : ""}' : 'Caixa Encerrado',
                        style: TextStyle(
                          color: aberto ? Colors.blueAccent : Colors.white60,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        abertura?.numero ?? '--',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (aberto && abertura != null)
                        Text(
                          'Iniciado em: ${formatoData.format(abertura.dataAbertura.toLocal())}',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildQuickActions(aberto, ds),
        ],
      ),
    );
  }

  Widget _buildAnimatedIcon(bool aberto) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: (aberto ? Colors.blueAccent : Colors.grey).withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: (aberto ? Colors.blueAccent : Colors.grey).withOpacity(0.3),
        ),
      ),
      child: Icon(
        aberto ? Icons.point_of_sale_rounded : Icons.lock_clock_rounded,
        color: aberto ? Colors.blueAccent : Colors.grey,
        size: 32,
      ),
    );
  }

  Future<void> _imprimirFechamento(AberturaCaixa ab, FechamentoCaixa fe) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = authService.empresaAtual;
      
      if (empresa == null) throw Exception('Empresa não selecionada');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Gerando Impressão do Caixa...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Obter vendas entre abertura e fechamento (somente do MESMO operador do
      // caixa e dentro da janela [abertura, fechamento] — getVendasDoCaixa já
      // aplica ambos os filtros). Isso impede vendas de outros caixas/usuários
      // de aparecerem na impressão do fechamento.
      final vendas = dataService.getVendasDoCaixa(ab)
          .where((v) => v.dataVenda
              .isBefore(fe.dataFechamento.add(const Duration(seconds: 1))))
          .toList();

      final List<String> canceladosExtra = [];
      for (var mesa in dataService.mesasComandas) {
        final cancelados = mesa.itens.where((i) {
          if (i.status != StatusItem.cancelado) return false;
          if (i.dataModificacao == null) return false;
          return (i.dataModificacao!.isAfter(ab.dataAbertura) ||
                  i.dataModificacao!.isAtSameMomentAs(ab.dataAbertura)) &&
                 i.dataModificacao!.isBefore(fe.dataFechamento.add(const Duration(seconds: 1)));
        }).toList();
        if (cancelados.isNotEmpty) {
          final labelOrigem = mesa.tipo == TipoControle.comanda ? '[COMANDA]' : '[MESA]';
          final canceladosInfo = cancelados.map((i) => 
            '${i.quantidade.toStringAsFixed(0)}x ${i.nome} por ${i.usuarioModificou ?? "Sistema"}'
          ).join(', ');
          canceladosExtra.add('$labelOrigem ${mesa.numero} (Aberta): $canceladosInfo');
        }
      }

      // Recebimentos de pedidos/mesas no período do caixa (mesma regra exibida
      // no diálogo de fechamento), para o papel não ficar só com as vendas do
      // PDV.
      final recebimentosPedidos = dataService.calcularRecebimentosDePedidosDoCaixa(
        ab,
        limite: fe.dataFechamento,
      );

      await CaixaPDFService.gerarPDFTermico(
        abertura: ab,
        fechamento: fe,
        empresa: empresa,
        vendas: vendas,
        itensDeletadosExtra: canceladosExtra,
        recebimentosPedidos: recebimentosPedidos,
      ).then((pdfData) async {
        if (context.mounted) Navigator.pop(context);
        
        await Printing.layoutPdf(
          onLayout: (format) async => pdfData,
          name: 'Fechamento_Caixa_${ab.numero}.pdf',
        );
      });
      
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _buscaFluxoController.dispose();
    super.dispose();
  }

  Widget _buildQuickActions(bool aberto, DataService ds) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (!aberto)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _mostrarDialogoAbertura(context, ds),
                icon: const Icon(Icons.play_circle_filled_rounded, size: 28),
                label: const Text('INICIAR NOVA SESSÃO DE CAIXA', style: TextStyle(letterSpacing: 1.1, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: Colors.blueAccent.withOpacity(0.4),
                ),
              ),
            )
          else ...[
            _buildActionButton(
              label: 'Pagamento',
              icon: Icons.remove_circle_rounded,
              color: Colors.orangeAccent,
              onTap: () => _mostrarDialogoSangria(context, ds, isPagamento: true),
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              label: 'Suprimento',
              icon: Icons.add_circle_rounded,
              color: Colors.lightBlueAccent,
              onTap: () => _mostrarDialogoSuprimento(context, ds),
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              label: 'Fechar',
              icon: Icons.stop_circle_rounded,
              color: Colors.redAccent,
              onTap: () => _mostrarDialogoFechamento(context, ds),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResumoSession(DataService ds, AberturaCaixa abertura, bool podeVerTotais, bool podeVerFormasPagamento) {
    // Pegar totais reais do DS (apenas do caixa em questão)
    final sangrias = ds.getSangriasDoCaixa(abertura);
    final suprimentos = ds.getSuprimentosDoCaixa(abertura);
    final totalSangrias = sangrias.fold(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos = suprimentos.fold(0.0, (sum, s) => sum + s.valor);

    // Calcular Vendas (do caixa em questão)
    final vendas = ds.getVendasDoCaixa(abertura);
    final totalVendas = vendas.fold(0.0, (sum, v) => sum + v.valorTotal);

    // Saldo Atual
    final saldo = abertura.valorInicial + totalVendas + totalSuprimentos - totalSangrias;

    // Separação do que entrou por Dinheiro, PIX, Cartão, etc.
    final resumoFormas = podeVerFormasPagamento
        ? ds.calcularResumoFormaPagamentoDoCaixa(abertura)
        : <ResumoFormaPagamento>[];

    return Column(
      children: [
        Row(
          children: [
            // Total de vendas/entradas: oculto para quem não pode ver totais
            if (podeVerTotais)
              _buildStatCard('Entradas', formatoMoeda.format(totalVendas + totalSuprimentos), Icons.trending_up, Colors.greenAccent),
            if (podeVerTotais) const SizedBox(width: 12),
            // O saldo inclui o total vendido (valorInicial + vendas + suprimentos - sangrias),
            // então também fica oculto para quem não pode ver totais.
            if (podeVerTotais)
              _buildStatCard('Saldo', formatoMoeda.format(saldo), Icons.account_balance_wallet, Colors.blueAccent),
            if (podeVerTotais) const SizedBox(width: 12),
            _buildStatCard('Saídas', formatoMoeda.format(totalSangrias), Icons.trending_down, Colors.redAccent),
          ],
        ),
        if (resumoFormas.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCardResumoFormas(
            resumoFormas,
            titulo: 'Entradas por Forma de Pagamento',
          ),
        ],
      ],
    );
  }

  /// Card com a separação das entradas por forma de pagamento
  /// (Dinheiro, PIX, Cartão de Crédito/Débito, Ticket, etc.).
  Widget _buildCardResumoFormas(
    List<ResumoFormaPagamento> resumo, {
    String titulo = 'Por Forma de Pagamento',
  }) {
    if (resumo.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...resumo.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: r.tipo.cor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(r.tipo.icone, color: r.tipo.cor, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        r.rotulo,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (r.quantidade > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '${r.quantidade}x',
                          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                        ),
                      ),
                    Text(
                      formatoMoeda.format(r.valor),
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Versão compacta (chips horizontais) do resumo por forma de pagamento,
  /// usada nos cards de caixas já encerrados.
  Widget _buildChipsResumoFormas(List<ResumoFormaPagamento> resumo) {
    if (resumo.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: resumo.map((r) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: r.tipo.cor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: r.tipo.cor.withOpacity(0.25)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.rotulo.toUpperCase(),
                  style: TextStyle(color: r.tipo.cor, fontSize: 9, fontWeight: FontWeight.bold),
                ),
                Text(
                  formatoMoeda.format(r.valor),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.02),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  color: color.withOpacity(0.9), 
                  fontWeight: FontWeight.w900, 
                  fontSize: 16,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Movimentações do dia SEM filtros aplicados.
  ///
  /// Se "Ver todos os caixas abertos" está marcado, junta as movimentações de
  /// TODOS os caixas abertos (removendo duplicatas); caso contrário, apenas do
  /// caixa selecionado. Usado tanto pela lista quanto pela barra de filtros
  /// (para descobrir quais formas de pagamento tiveram movimento).
  List<Map<String, dynamic>> _movimentacoesFluxoBase(
    DataService ds,
    AberturaCaixa abertura,
  ) {
    if (!_mostrarTodosCaixas) {
      return _getMovimentacoesExt(ds, abertura);
    }
    // Modo global: juntar movimentações de todos os caixas abertos
    final movs = <Map<String, dynamic>>[];
    for (final caixa in ds.aberturasCaixaAbertas) {
      movs.addAll(_getMovimentacoesExt(ds, caixa));
    }
    // Remover duplicatas por combinação data+descricao+valor
    final seen = <String>{};
    return movs.where((m) {
      final key = '${m['data']}_${m['descricao']}_${m['valor']}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  /// Há algum filtro ativo no Fluxo de Caixa?
  bool get _temFiltroFluxo =>
      _filtroTipoFluxo != 'Todos' ||
      _filtroFormaFluxo != null ||
      _termoBuscaFluxo.isNotEmpty ||
      _mostrarTodosCaixas ||
      CaixaMovFiltroService.janelaAtiva(_horaInicioFluxoMin, _horaFimFluxoMin);

  /// Aplica os filtros ativos do Fluxo de Caixa (tipo, forma e busca).
  List<Map<String, dynamic>> _filtrarFluxo(List<Map<String, dynamic>> movs) {
    var out = movs;

    // Filtro por tipo
    if (_filtroTipoFluxo != 'Todos') {
      out = out.where((m) {
        final tipo = (m['tipo'] ?? '').toString();
        switch (_filtroTipoFluxo) {
          case 'Vendas': return tipo == 'Venda';
          case 'Pagamento': return tipo == 'Pagamento';
          case 'Suprimento': return tipo == 'Suprimento';
          case 'Mesa/Comanda': return tipo == 'Mesa' || tipo == 'Comanda';
          default: return true;
        }
      }).toList();
    }

    // Filtro por forma de pagamento (Dinheiro, PIX, Cartão...)
    if (_filtroFormaFluxo != null) {
      out = out.where((m) => m['tipoPagamento'] == _filtroFormaFluxo).toList();
    }

    // Busca por texto (número da venda, descrição)
    if (_termoBuscaFluxo.isNotEmpty) {
      final t = _termoBuscaFluxo.toLowerCase();
      out = out.where((m) {
        final desc = (m['descricao'] ?? '').toString().toLowerCase();
        final num = (m['numero'] ?? '').toString().toLowerCase();
        return desc.contains(t) || num.contains(t);
      }).toList();
    }

    // Filtro por horário (janela De/Até escolhida pelo usuário)
    out = CaixaMovFiltroService.porHorario(
      out,
      inicioMin: _horaInicioFluxoMin,
      fimMin: _horaFimFluxoMin,
    );

    return out;
  }

  Widget _buildSliverFluxoLista(List<Map<String, dynamic>> movs) {
    if (movs.isEmpty) {
      final temFiltro = _temFiltroFluxo;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.1), size: 48),
              const SizedBox(height: 12),
              Text(
                temFiltro
                    ? 'Nenhuma movimentação encontrada com os filtros'
                    : 'Nenhuma movimentação registrada',
                style: TextStyle(color: Colors.white.withOpacity(0.3)),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildMovCard(movs[index]),
          childCount: movs.length,
        ),
      ),
    );
  }

  /// Linha de uma movimentação do fluxo.
  ///
  /// Mesas/comandas com valor "a receber" (ainda não pagas) aparecem
  /// esmaecidas e marcadas — elas NÃO entram nos totais do caixa, então não
  /// podem parecer uma entrada já realizada.
  Widget _buildMovCard(Map<String, dynamic> m) {
    final contabilizado = m['contabilizado'] != false;
    final valor = (m['valor'] as double?) ?? 0.0;
    return Opacity(
      opacity: contabilizado ? 1.0 : 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (m['cor'] as Color).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(m['icone'] as IconData, color: m['cor'] as Color, size: 20),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  m['descricao'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!contabilizado) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'A RECEBER',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${formatoHora.format((m['data'] as DateTime).toLocal())} • ${m['forma']}',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
          trailing: Text(
            formatoMoeda.format(valor),
            style: TextStyle(
              color: !contabilizado
                  ? Colors.white.withOpacity(0.55)
                  : (valor >= 0 ? Colors.greenAccent : Colors.redAccent),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Total do que está sendo exibido na lista do fluxo (respeita os filtros).
  ///
  /// Só entram movimentações contabilizadas — mesas/comandas "a receber" ficam
  /// de fora, como no saldo do caixa.
  Widget _buildTotalFluxo(List<Map<String, dynamic>> movs) {
    if (movs.isEmpty) return const SizedBox.shrink();

    double entradas = 0.0;
    double saidas = 0.0;
    int contabilizadas = 0;
    int aReceber = 0;
    for (final m in movs) {
      if (m['contabilizado'] == false) {
        aReceber++;
        continue;
      }
      contabilizadas++;
      final v = (m['valor'] as double?) ?? 0.0;
      if (v >= 0) {
        entradas += v;
      } else {
        saidas += -v;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.functions_rounded, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                'Total do filtro atual',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$contabilizadas movimentação(ões)',
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniInfo('Entradas', formatoMoeda.format(entradas)),
              ),
              Expanded(
                child: _miniInfo('Saídas', formatoMoeda.format(saidas)),
              ),
              Expanded(
                child: _miniInfo('Saldo', formatoMoeda.format(entradas - saidas)),
              ),
            ],
          ),
          if (aReceber > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$aReceber mesa(s)/comanda(s) a receber — não incluídas nos totais.',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// Barra de filtros do Fluxo de Caixa (Movimentações do Dia).
  ///
  /// Recebe as movimentações já calculadas pelo `build()` — antes esta barra
  /// recalculava tudo (`_movimentacoesFluxoBase`) a cada rebuild.
  Widget _buildFiltrosFluxo(
    List<Map<String, dynamic>> movsBase,
    AberturaCaixa abertura,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              const Text('Filtrar Movimentações',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                // No modo "todos os caixas" não existe uma abertura única para
                // identificar no CSV (só manda o período quando é uma sessão só).
                onPressed: () => _exportarFluxoCSV(
                      _filtrarFluxo(movsBase),
                      caixa: _mostrarTodosCaixas ? null : abertura.numero,
                      abertura: _mostrarTodosCaixas ? null : abertura,
                    ),
                icon: const Icon(Icons.file_download_outlined,
                    size: 18, color: Colors.greenAccent),
                tooltip: 'Exportar movimentações (CSV)',
                visualDensity: VisualDensity.compact,
              ),
              if (_temFiltroFluxo)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroTipoFluxo = 'Todos';
                    _filtroFormaFluxo = null;
                    _termoBuscaFluxo = '';
                    _mostrarTodosCaixas = false;
                    _horaInicioFluxoMin = null;
                    _horaFimFluxoMin = null;
                    _buscaFluxoController.clear();
                  }),
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  label: const Text('Limpar',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Barra de busca
          TextField(
            controller: _buscaFluxoController,
            onChanged: (v) => setState(() => _termoBuscaFluxo = v),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar por número da venda, descrição...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 20),
              filled: true,
              fillColor: const Color(0xFF2D2D44),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          // Filtros por tipo (ChoiceChips)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                'Todos', 'Vendas', 'Pagamento', 'Suprimento', 'Mesa/Comanda',
              ].map((tipo) {
                final isSelected = _filtroTipoFluxo == tipo;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tipo),
                    selected: isSelected,
                    onSelected: (val) => setState(() => _filtroTipoFluxo = tipo),
                    backgroundColor: const Color(0xFF2D2D44),
                    selectedColor: Colors.blueAccent.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blueAccent : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.transparent,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Forma de pagamento (Dinheiro, PIX, Cartão...) e janela de horário.
          _buildSecaoFormaHorario(
            movsBase: movsBase,
            formaSelecionada: _filtroFormaFluxo,
            horaInicioMin: _horaInicioFluxoMin,
            horaFimMin: _horaFimFluxoMin,
            onForma: (tp) => setState(() => _filtroFormaFluxo = tp),
            // A hora vem de um diálogo assíncrono: a tela pode ter sido
            // descartada enquanto o seletor estava aberto.
            onHoraInicio: (m) {
              if (!mounted) return;
              setState(() => _horaInicioFluxoMin = m);
            },
            onHoraFim: (m) {
              if (!mounted) return;
              setState(() => _horaFimFluxoMin = m);
            },
            onLimparHorario: () => setState(() {
              _horaInicioFluxoMin = null;
              _horaFimFluxoMin = null;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Checkbox(
                value: _mostrarTodosCaixas,
                activeColor: Colors.blueAccent,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _mostrarTodosCaixas = val;
                    });
                  }
                },
              ),
              const Text(
                'Ver todos os caixas abertos',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Chip de filtro por forma de pagamento no Fluxo de Caixa.
  Widget _buildFormaChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.18) : const Color(0xFF2D2D44),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: selected ? color : Colors.white54, size: 14),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? color : Colors.white60,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formas de pagamento que realmente tiveram movimento na lista, para montar
  /// os chips sem oferecer um filtro que não acharia nada.
  List<TipoPagamento> _formasComMovimento(List<Map<String, dynamic>> movs) {
    final presentes = <TipoPagamento>{};
    for (final m in movs) {
      final tp = m['tipoPagamento'];
      if (tp is TipoPagamento) presentes.add(tp);
    }
    return TipoPagamento.values.where(presentes.contains).toList();
  }

  /// Seção "Forma de pagamento" + "Horário" dos filtros de movimentação.
  ///
  /// Compartilhada pela barra do Fluxo de Caixa (caixa aberto) e pelo modal de
  /// movimentações de um caixa encerrado: antes só o fluxo aberto filtrava por
  /// forma de pagamento, e nenhum dos dois filtrava por horário.
  Widget _buildSecaoFormaHorario({
    required List<Map<String, dynamic>> movsBase,
    required TipoPagamento? formaSelecionada,
    required int? horaInicioMin,
    required int? horaFimMin,
    required ValueChanged<TipoPagamento?> onForma,
    required ValueChanged<int?> onHoraInicio,
    required ValueChanged<int?> onHoraFim,
    required VoidCallback onLimparHorario,
  }) {
    final formas = _formasComMovimento(movsBase);
    final rotuloHorario =
        CaixaMovFiltroService.rotulo(horaInicioMin, horaFimMin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Forma de pagamento (Dinheiro, PIX, Cartão de Crédito/Débito, Ticket...).
        // Só aparece quando há mais de uma forma no período.
        if (formas.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: Colors.greenAccent, size: 16),
              const SizedBox(width: 6),
              const Text('Forma de pagamento:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFormaChip(
                  label: 'Todas',
                  selected: formaSelecionada == null,
                  color: Colors.blueAccent,
                  onTap: () => onForma(null),
                ),
                ...formas.map((tp) => _buildFormaChip(
                      // Mesmo rótulo usado na lista, para o filtro não divergir
                      // do que aparece em cada movimentação.
                      label: _formatForma(tp),
                      selected: formaSelecionada == tp,
                      color: tp.cor,
                      icon: tp.icone,
                      onTap: () => onForma(tp),
                    )),
              ],
            ),
          ),
        ],
        // Janela de horário da movimentação (De/Até).
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.schedule, color: Colors.orangeAccent, size: 16),
            const SizedBox(width: 6),
            const Text('Horário:',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            if (rotuloHorario != null)
              TextButton.icon(
                onPressed: onLimparHorario,
                icon: const Icon(Icons.close, size: 14, color: Colors.white54),
                label: const Text('Limpar horário',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildHoraChip(
                label: 'De',
                minutos: horaInicioMin,
                color: Colors.orangeAccent,
                onTap: () async {
                  final escolhido = await _escolherHora(
                    atual: horaInicioMin,
                    titulo: 'Horário inicial',
                  );
                  if (escolhido != null) onHoraInicio(escolhido);
                },
              ),
              _buildHoraChip(
                label: 'Até',
                minutos: horaFimMin,
                color: Colors.orangeAccent,
                onTap: () async {
                  final escolhido = await _escolherHora(
                    atual: horaFimMin,
                    titulo: 'Horário final',
                  );
                  if (escolhido != null) onHoraFim(escolhido);
                },
              ),
              if (rotuloHorario != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                    ),
                    child: Text(
                      rotuloHorario,
                      style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Janela que atravessa a meia-noite é fácil de errar: avisa o que está
        // sendo incluído (ex.: "De 22:00" até "Até 02:00").
        if (rotuloHorario != null && horaInicioMin! > horaFimMin!)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Intervalo atravessa a meia-noite: inclui de '
              '${CaixaMovFiltroService.formatarMinutos(horaInicioMin)} até 23:59 e de '
              '00:00 até ${CaixaMovFiltroService.formatarMinutos(horaFimMin)}.',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
            ),
          ),
      ],
    );
  }

  /// Chip "De"/"Até" do filtro de horário; toca para escolher a hora.
  Widget _buildHoraChip({
    required String label,
    required int? minutos,
    required Color color,
    required VoidCallback onTap,
  }) {
    final ativo = minutos != null;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ativo ? color.withOpacity(0.18) : const Color(0xFF2D2D44),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ativo ? color : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule, color: ativo ? color : Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                ativo
                    ? '$label ${CaixaMovFiltroService.formatarMinutos(minutos)}'
                    : label,
                style: TextStyle(
                  color: ativo ? color : Colors.white60,
                  fontSize: 12,
                  fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Abre o seletor de hora e devolve os minutos desde a meia-noite escolhidos
  /// (ou `null` se o usuário cancelar).
  Future<int?> _escolherHora({required int? atual, required String titulo}) async {
    if (!mounted) return null;
    final inicial =
        atual != null ? TimeOfDay(hour: atual ~/ 60, minute: atual % 60) : TimeOfDay.now();
    final escolhido = await showTimePicker(
      context: context,
      initialTime: inicial,
      helpText: titulo,
    );
    if (escolhido == null) return null;
    return escolhido.hour * 60 + escolhido.minute;
  }

  /// Barra de filtros do Histórico de Encerramentos (data e número do caixa)
  Widget _buildFiltrosHistorico(DataService ds) {
    final numerosCaixa = ds.aberturasCaixa
        .map((a) => a.numero)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final temFiltro = _filtroNumeroCaixa != 'Todos' ||
        _filtroDataInicio != null ||
        _filtroDataFim != null ||
        _filtroSomenteDivergentes;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              const Text('Filtrar por:',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (temFiltro)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroNumeroCaixa = 'Todos';
                    _filtroDataInicio = null;
                    _filtroDataFim = null;
                    _filtroSomenteDivergentes = false;
                  }),
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  label: const Text('Limpar',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Caixa:', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E2E),
                    value: _filtroNumeroCaixa,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: [
                      const DropdownMenuItem<String>(
                          value: 'Todos', child: Text('Todos')),
                      ...numerosCaixa.map((n) =>
                          DropdownMenuItem<String>(value: n, child: Text(n))),
                    ],
                    onChanged: (v) => setState(() => _filtroNumeroCaixa = v ?? 'Todos'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDataChip('De', _filtroDataInicio, inicial: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDataChip('Até', _filtroDataFim, inicial: false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Atalho do gestor: mostrar apenas os caixas que fecharam com
          // diferença entre o esperado e o contado.
          Row(
            children: [
              FilterChip(
                selected: _filtroSomenteDivergentes,
                onSelected: (v) => setState(() => _filtroSomenteDivergentes = v),
                avatar: Icon(
                  Icons.error_outline,
                  size: 16,
                  color: _filtroSomenteDivergentes ? Colors.redAccent : Colors.white54,
                ),
                label: Text(
                  'Só divergentes',
                  style: TextStyle(
                    fontSize: 12,
                    color: _filtroSomenteDivergentes ? Colors.redAccent : Colors.white60,
                    fontWeight: _filtroSomenteDivergentes ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                backgroundColor: const Color(0xFF2D2D44),
                selectedColor: Colors.redAccent.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: _filtroSomenteDivergentes ? Colors.redAccent : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataChip(String label, DateTime? valor, {required bool inicial}) {
    return InkWell(
      onTap: () => _selecionarDataFiltro(inicial: inicial),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                valor == null
                    ? '—'
                    : DateFormat('dd/MM/yyyy').format(valor!),
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selecionarDataFiltro({required bool inicial}) async {
    final atual = inicial ? _filtroDataInicio : _filtroDataFim;
    final picked = await showDatePicker(
      context: context,
      initialDate: atual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: inicial ? 'Data inicial' : 'Data final',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (picked != null) {
      setState(() {
        final dia = DateTime(picked.year, picked.month, picked.day);
        if (inicial) {
          _filtroDataInicio = dia;
          if (_filtroDataFim != null && _filtroDataFim!.isBefore(dia)) {
            _filtroDataFim = dia;
          }
        } else {
          _filtroDataFim = dia;
          if (_filtroDataInicio != null && _filtroDataInicio!.isAfter(dia)) {
            _filtroDataInicio = dia;
          }
        }
      });
    }
  }

  Widget _buildSliverHistorico(DataService ds, bool podeVerTotais) {
    final usuarioLogadoHist = Provider.of<AuthService>(context, listen: false).usuarioAtual;
    final ehGestorHist = usuarioLogadoHist != null &&
        (usuarioLogadoHist.isAdmin ||
            usuarioLogadoHist.isMaster ||
            usuarioLogadoHist.isGerente ||
            usuarioLogadoHist.email.toLowerCase() == 'user');
    // Detalhamento por forma de pagamento no histórico (permissão própria).
    final podeVerFormasPagamentoHist =
        PermissionHelper.podeVerTotaisFormasPagamento(usuarioLogadoHist);

    var hist = ds.aberturasCaixa.map((ab) {
      final fe = ds.fechamentosCaixa.firstWhereOrNull((f) => f.aberturaCaixaId == ab.id);
      return MapEntry(ab, fe);
    }).where((e) => e.value != null).toList();

    // Operador comum só vê os encerramentos dos PRÓPRIOS caixas — antes o
    // histórico listava todos os caixas de todos os usuários da empresa.
    if (!ehGestorHist && usuarioLogadoHist != null) {
      final idLogado = usuarioLogadoHist.email.isNotEmpty
          ? usuarioLogadoHist.email
          : usuarioLogadoHist.nome;
      hist = hist.where((e) {
        final resp = e.key.responsavel;
        if (resp == null || resp.trim().isEmpty) return false;
        String norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9@]'), '');
        final na = norm(resp);
        final nb = norm(idLogado);
        if (na.isEmpty || nb.isEmpty) return false;
        if (na == nb) return true;
        final localA = na.contains('@') ? na.split('@').first : na;
        final localB = nb.contains('@') ? nb.split('@').first : nb;
        return localA == localB && localA.isNotEmpty;
      }).toList();
    }

    // Aplica os filtros de número do caixa e período
    if (_filtroNumeroCaixa != 'Todos') {
      hist = hist.where((e) => e.key.numero == _filtroNumeroCaixa).toList();
    }
    if (_filtroDataInicio != null) {
      hist = hist.where((e) => !e.key.dataAbertura.isBefore(_filtroDataInicio!)).toList();
    }
    if (_filtroDataFim != null) {
      final fim = _filtroDataFim!.add(const Duration(days: 1));
      hist = hist.where((e) => e.key.dataAbertura.isBefore(fim)).toList();
    }

    // Filtro "só divergentes" — o que o gestor mais procura no histórico.
    if (_filtroSomenteDivergentes) {
      hist = hist
          .where((e) => e.value!.diferenca.abs() > _toleranciaDivergencia)
          .toList();
    }

    hist.sort((a, b) => b.key.dataAbertura.compareTo(a.key.dataAbertura));

    if (hist.isEmpty) {
      final temFiltro = _filtroNumeroCaixa != 'Todos' ||
          _filtroDataInicio != null ||
          _filtroDataFim != null ||
          _filtroSomenteDivergentes;
      return SliverToBoxAdapter(
        child: Center(
          child: Text(
            temFiltro
                ? 'Nenhum encerramento encontrado com os filtros'
                : 'Nenhum fechamento passado',
            style: TextStyle(color: Colors.white30),
          ),
        ),
      );
    }

    // Resumo do que está sendo exibido (respeita filtros e a visibilidade do
    // operador): quantos caixas, quantos divergentes e a soma das diferenças.
    final divergentes =
        hist.where((e) => e.value!.diferenca.abs() > _toleranciaDivergencia).length;
    final somaDiferencas =
        hist.fold<double>(0.0, (s, e) => s + e.value!.diferenca);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return _buildResumoHistorico(
                total: hist.length,
                divergentes: divergentes,
                somaDiferencas: somaDiferencas,
                podeVerTotais: podeVerTotais,
              );
            }
            final item = hist[index - 1];
            return _buildCardCaixaModerno(
              item.key,
              item.value!,
              ds,
              podeVerTotais,
              podeVerFormasPagamentoHist,
            );
          },
          childCount: hist.length + 1,
        ),
      ),
    );
  }

  /// Faixa de resumo do Histórico de Encerramentos — quantos caixas estão
  /// sendo exibidos, quantos fecharam divergentes e a soma das diferenças.
  Widget _buildResumoHistorico({
    required int total,
    required int divergentes,
    required double somaDiferencas,
    required bool podeVerTotais,
  }) {
    final cor = divergentes > 0 ? Colors.redAccent : Colors.greenAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(divergentes > 0 ? Icons.warning_amber_rounded : Icons.verified_outlined,
                  color: cor, size: 18),
              const SizedBox(width: 8),
              Text(
                '$total caixa(s) no filtro',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _miniInfo(
                  'Divergentes',
                  '$divergentes de $total',
                ),
              ),
              if (podeVerTotais)
                Expanded(
                  child: _miniInfo(
                    'Soma das dif.',
                    '${somaDiferencas >= 0 ? '+' : ''}${formatoMoeda.format(somaDiferencas)}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardCaixaModerno(
    AberturaCaixa ab,
    FechamentoCaixa fe,
    DataService ds,
    bool podeVerTotais,
    bool podeVerFormasPagamento,
  ) {
    // Separação do que foi Dinheiro, PIX, Cartão etc. neste caixa.
    final resumoFormas = podeVerFormasPagamento
        ? ds.calcularResumoFormaPagamentoDoCaixa(ab)
        : <ResumoFormaPagamento>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ab.numero,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Abertura: ${DateFormat('dd/MM/yyyy HH:mm').format(ab.dataAbertura.toLocal())}'
                    '  •  Fechamento: ${DateFormat('dd/MM/yyyy HH:mm').format(fe.dataFechamento.toLocal())}',
                    style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
                  ),
                  if (ab.responsavel != null && ab.responsavel!.isNotEmpty)
                    Text(
                      ab.responsavel!,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (fe.diferenca >= 0 ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fe.diferenca >= 0 ? 'Conforme' : 'Divergente',
                      style: TextStyle(color: fe.diferenca >= 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 10),
                    ),
                    const SizedBox(width: 4),
                    if (podeVerTotais)
                      IconButton(
                        icon: const Icon(Icons.receipt_long, color: Colors.cyanAccent, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _mostrarDetalhesCaixaFechado(
                          ds,
                          ab,
                          fe,
                          podeVerTotais: podeVerTotais,
                          podeVerFormasPagamento: podeVerFormasPagamento,
                        ),
                        tooltip: 'Detalhes completos do caixa',
                      ),
                    if (podeVerTotais)
                      IconButton(
                        icon: const Icon(Icons.visibility, color: Colors.blueAccent, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _mostrarVendasDoCaixa(ds, ab, fechamento: fe),
                        tooltip: 'Ver vendas deste caixa',
                      ),
                    if (podeVerTotais)
                      IconButton(
                        icon: const Icon(Icons.print, color: Colors.blueAccent, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _imprimirFechamento(ab, fe),
                        tooltip: 'Imprimir Fechamento',
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Entrada/Real/Dif. revelam o total vendido — ocultos para quem não
              // pode ver totais (operador sem dashboard.ver_totais).
              if (podeVerTotais)
                Expanded(child: _miniInfo('Entrada', formatoMoeda.format(fe.valorEsperado))),
              if (podeVerTotais)
                Expanded(child: _miniInfo('Real', formatoMoeda.format(fe.valorReal))),
              if (podeVerTotais)
                Expanded(child: _miniInfo('Dif.', formatoMoeda.format(fe.diferenca))),
            ],
          ),
          if (resumoFormas.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded, color: Colors.blueAccent, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Entradas por forma de pagamento',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildChipsResumoFormas(resumoFormas),
          ],
          if (podeVerTotais) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _mostrarDetalhesCaixaFechado(
                  ds,
                  ab,
                  fe,
                  podeVerTotais: podeVerTotais,
                  podeVerFormasPagamento: podeVerFormasPagamento,
                ),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('VER DETALHES COMPLETOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Modal com TODOS os detalhes de um caixa já encerrado — pensado para o
  /// gestor conferir o fechamento: período, vendas, separação por forma de
  /// pagamento, sangrias/suprimentos, conferência e observações.
  void _mostrarDetalhesCaixaFechado(
    DataService ds,
    AberturaCaixa ab,
    FechamentoCaixa fe, {
    required bool podeVerTotais,
    required bool podeVerFormasPagamento,
  }) {
    final vendas = ds.getVendasDoCaixa(ab);
    final totalVendas =
        vendas.fold<double>(0.0, (sum, v) => sum + v.valorTotal);
    final totalItens =
        vendas.fold<double>(0.0, (sum, v) => sum + v.quantidadeItens);
    final sangrias = ds.getSangriasDoCaixa(ab);
    final suprimentos = ds.getSuprimentosDoCaixa(ab);
    final totalSangrias =
        sangrias.fold<double>(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos =
        suprimentos.fold<double>(0.0, (sum, s) => sum + s.valor);
    final resumoFormas = podeVerFormasPagamento
        ? ds.calcularResumoFormaPagamentoDoCaixa(ab)
        : <ResumoFormaPagamento>[];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.9,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.cyanAccent, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalhes do ${ab.numero}',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${ab.responsavel?.isNotEmpty == true ? ab.responsavel! : "Sem responsável"}  •  '
                            '${DateFormat('dd/MM/yyyy HH:mm').format(ab.dataAbertura.toLocal())} → '
                            '${DateFormat('HH:mm').format(fe.dataFechamento.toLocal())}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    // Conferência do fechamento
                    _buildDetalheSecao('Conferência do Fechamento', Icons.calculate_outlined, [
                      _buildInfoRow('Fundo de caixa inicial', formatoMoeda.format(ab.valorInicial), Icons.account_balance_wallet, Colors.grey),
                      if (podeVerTotais)
                        _buildInfoRow('Total de vendas', formatoMoeda.format(totalVendas), Icons.trending_up, Colors.greenAccent),
                      _buildInfoRow('Total suprimentos', formatoMoeda.format(totalSuprimentos), Icons.add_circle_outline, Colors.lightBlueAccent),
                      _buildInfoRow('Total sangrias', formatoMoeda.format(totalSangrias), Icons.remove_circle_outline, Colors.orangeAccent),
                      _buildInfoRow('Valor esperado', formatoMoeda.format(fe.valorEsperado), Icons.calculate, Colors.blueAccent),
                      _buildInfoRow('Valor real (contado)', formatoMoeda.format(fe.valorReal), Icons.account_balance_wallet, Colors.white),
                      _buildInfoRow(
                        'Diferença',
                        '${fe.diferenca >= 0 ? '+' : ''}${formatoMoeda.format(fe.diferenca)}',
                        fe.diferenca >= 0 ? Icons.check_circle_outline : Icons.error_outline,
                        fe.diferenca >= 0 ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ]),
                    // Separação por forma de pagamento
                    if (resumoFormas.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalheSecao('Entradas por Forma de Pagamento', Icons.payments_outlined, [
                        ...resumoFormas.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: r.tipo.cor.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(r.tipo.icone, color: r.tipo.cor, size: 14),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      r.rotulo,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (r.quantidade > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Text(
                                        '${r.quantidade}x',
                                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
                                      ),
                                    ),
                                  Text(
                                    formatoMoeda.format(r.valor),
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )),
                      ]),
                    ],
                    // Resumo de vendas
                    if (podeVerTotais) ...[
                      const SizedBox(height: 16),
                      _buildDetalheSecao('Vendas do Período', Icons.shopping_basket_outlined, [
                        _buildInfoRow('Vendas realizadas', '${vendas.length}', Icons.receipt, Colors.white70),
                        _buildInfoRow('Itens vendidos', totalItens % 1 == 0 ? totalItens.toStringAsFixed(0) : totalItens.toStringAsFixed(1), Icons.inventory_2_outlined, Colors.white70),
                        _buildInfoRow('Ticket médio', formatoMoeda.format(vendas.isEmpty ? 0 : totalVendas / vendas.length), Icons.insights, Colors.white70),
                      ]),
                    ],
                    // Sangrias e suprimentos detalhados
                    if (sangrias.isNotEmpty || suprimentos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalheSecao('Sangrias e Suprimentos', Icons.swap_vert, [
                        ...sangrias.map((s) => _buildMovLinha(s.motivo, -s.valor, s.data, Colors.orangeAccent)),
                        ...suprimentos.map((s) => _buildMovLinha(s.motivo, s.valor, s.data, Colors.lightBlueAccent)),
                      ]),
                    ],
                    // Observação do fechamento
                    if (fe.observacao != null && fe.observacao!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalheSecao('Observações do Fechamento', Icons.edit_note, [
                        Text(
                          fe.observacao!,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ]),
                    ],
                    if (ab.observacao != null && ab.observacao!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalheSecao('Observações da Abertura', Icons.note_alt_outlined, [
                        Text(
                          ab.observacao!,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ]),
                    ],
                    // Movimentações do caixa encerrado, linha a linha (entradas,
                    // saídas, vendas, mesas e sangrias) — antes só era possível
                    // ver o fluxo detalhado do caixa ABERTO.
                    if (podeVerTotais) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _mostrarMovimentacoesCaixaFechado(ds, ab, fe);
                          },
                          icon: const Icon(Icons.list_alt, size: 16),
                          label: const Text('VER MOVIMENTAÇÕES DO CAIXA',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                            side: BorderSide(color: Colors.greenAccent.withOpacity(0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (podeVerTotais)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _mostrarVendasDoCaixa(ds, ab, fechamento: fe);
                              },
                              icon: const Icon(Icons.visibility, size: 16),
                              label: const Text('VER VENDAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueAccent,
                                side: BorderSide(color: Colors.blueAccent.withOpacity(0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        if (podeVerTotais) const SizedBox(width: 10),
                        if (podeVerTotais)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                                _imprimirFechamento(ab, fe);
                              },
                              icon: const Icon(Icons.print, size: 16),
                              label: const Text('IMPRIMIR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.cyanAccent,
                                side: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Bloco de seção do modal de detalhes do caixa encerrado.
  Widget _buildDetalheSecao(String titulo, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// Linha de sangria/suprimento no modal de detalhes.
  Widget _buildMovLinha(String motivo, double valor, DateTime data, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              motivo.isEmpty ? '—' : motivo,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatoHora.format(data.toLocal()),
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
          ),
          const SizedBox(width: 12),
          Text(
            formatoMoeda.format(valor),
            style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Exporta as movimentações exibidas no Fluxo de Caixa para CSV, para o
  /// gestor levar os dados para planilha (a impressão só cobre o fechamento).
  Future<void> _exportarFluxoCSV(
    List<Map<String, dynamic>> movs, {
    String? caixa,
    AberturaCaixa? abertura,
  }) async {
    if (movs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma movimentação para exportar.')),
      );
      return;
    }
    try {
      final linhas = movs.map((m) {
        return LinhaFluxoExport(
          data: (m['data'] as DateTime?) ?? DateTime.now(),
          tipo: (m['tipo'] ?? '').toString(),
          descricao: (m['descricao'] ?? '').toString(),
          forma: (m['forma'] ?? '').toString(),
          valor: (m['valor'] as double?) ?? 0.0,
          contabilizado: m['contabilizado'] != false,
        );
      }).toList();

      final destino = await CaixaFluxoExportService.exportar(
        linhas,
        caixa: caixa,
        abertura: abertura?.dataAbertura,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(destino == null
              ? 'Não foi possível gerar o CSV.'
              : 'Fluxo exportado: $destino'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar fluxo: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Modal com as movimentações de um caixa JÁ ENCERRADO, linha a linha.
  ///
  /// `getVendasDoCaixa`/`getSangriasDoCaixa`/`getSuprimentosDoCaixa` já limitam
  /// a janela [abertura, fechamento], então o mesmo cálculo do fluxo da sessão
  /// aberta vale aqui.
  void _mostrarMovimentacoesCaixaFechado(
    DataService ds,
    AberturaCaixa ab,
    FechamentoCaixa fe,
  ) {
    final movs = _getMovimentacoesExt(ds, ab);
    // Filtros LOCAIS do modal (não mexem na barra do fluxo do caixa aberto):
    // aqui o gestor quer responder "o que entrou de PIX entre 18h e 20h?" em um
    // caixa específico, inclusive já encerrado.
    TipoPagamento? formaSelecionada;
    int? horaInicioMin;
    int? horaFimMin;

    List<Map<String, dynamic>> aplicarFiltros() {
      var out = movs;
      if (formaSelecionada != null) {
        out = out.where((m) => m['tipoPagamento'] == formaSelecionada).toList();
      }
      return CaixaMovFiltroService.porHorario(
        out,
        inicioMin: horaInicioMin,
        fimMin: horaFimMin,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final movsFiltradas = aplicarFiltros();
            final temFiltro = formaSelecionada != null ||
                CaixaMovFiltroService.janelaAtiva(horaInicioMin, horaFimMin);
            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.9,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.list_alt, color: Colors.greenAccent, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Movimentações do ${ab.numero}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(ab.dataAbertura.toLocal())} → '
                                '${DateFormat('dd/MM/yyyy HH:mm').format(fe.dataFechamento.toLocal())}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.file_download_outlined,
                              color: Colors.greenAccent),
                          // Exporta o que está na tela: o CSV tem que respeitar os
                          // filtros aplicados aqui, como no fluxo do caixa aberto.
                          tooltip: temFiltro
                              ? 'Exportar movimentações filtradas (CSV)'
                              : 'Exportar movimentações (CSV)',
                          onPressed: () => _exportarFluxoCSV(
                                movsFiltradas,
                                caixa: ab.numero,
                                abertura: ab,
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.filter_alt_rounded,
                                  color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 8),
                              const Text('Filtrar Movimentações',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (temFiltro)
                                TextButton.icon(
                                  onPressed: () => setSheetState(() {
                                    formaSelecionada = null;
                                    horaInicioMin = null;
                                    horaFimMin = null;
                                  }),
                                  icon: const Icon(Icons.close,
                                      size: 16, color: Colors.white54),
                                  label: const Text('Limpar',
                                      style: TextStyle(
                                          color: Colors.white54, fontSize: 12)),
                                ),
                            ],
                          ),
                          _buildSecaoFormaHorario(
                            movsBase: movs,
                            formaSelecionada: formaSelecionada,
                            horaInicioMin: horaInicioMin,
                            horaFimMin: horaFimMin,
                            onForma: (tp) => setSheetState(() {
                              formaSelecionada = tp;
                            }),
                            // A hora vem de um diálogo assíncrono: o modal pode
                            // ter sido fechado enquanto o seletor estava aberto.
                            onHoraInicio: (m) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                horaInicioMin = m;
                              });
                            },
                            onHoraFim: (m) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                horaFimMin = m;
                              });
                            },
                            onLimparHorario: () => setSheetState(() {
                              horaInicioMin = null;
                              horaFimMin = null;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: movsFiltradas.isEmpty
                        ? Center(
                            child: Text(
                              movs.isEmpty
                                  ? 'Nenhuma movimentação registrada neste caixa.'
                                  : 'Nenhuma movimentação com os filtros aplicados.',
                              style: TextStyle(color: Colors.white.withOpacity(0.3)),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            children: [
                              ...movsFiltradas.map(_buildMovCard),
                              const SizedBox(height: 8),
                              _buildTotalFluxo(movsFiltradas),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white30, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }

  List<Map<String, dynamic>> _getMovimentacoesExt(DataService ds, AberturaCaixa ab) {
    final list = <Map<String, dynamic>>[];

    // Vendas (apenas do caixa em questão)
    for (final v in ds.getVendasDoCaixa(ab)) {
      if (!v.cancelado) {
        list.add({
          'data': v.dataVenda,
          'descricao': 'Venda PDV ${v.numero}',
          'valor': v.valorTotal,
          'forma': _formatForma(v.tipoPagamento),
          'tipoPagamento': v.tipoPagamento,
          'icone': Icons.shopping_basket_rounded,
          'cor': Colors.greenAccent,
          'numero': v.numero,
          'tipo': 'Venda',
          'contabilizado': true,
        });
      }
    }

    // Mesas / Comandas (itens em preparo/pendentes vinculados ao operador do caixa)
    final respAb = (ab.responsavel ?? '').trim();
    for (final mc in ds.mesasComandas) {
      if (respAb.isNotEmpty) {
        final criador = (mc.usuarioCriou ?? mc.usuarioModificou ?? '').trim();
        if (criador.isNotEmpty && !ds.vendaPertenceAoOperador(criador, respAb)) {
          continue;
        }
      }
      final itensValidos = mc.itens.where((i) =>
          i.status != StatusItem.cancelado &&
          i.status != StatusItem.entregue).toList();
      if (itensValidos.isNotEmpty) {
        final totalMc = itensValidos.fold<double>(0.0, (sum, i) => sum + i.subtotal);
        final label = mc.tipo == TipoControle.comanda ? 'Comanda' : 'Mesa';
        list.add({
          'data': itensValidos.last.dataModificacao ?? mc.dataAbertura,
          'descricao': '$label ${mc.numero}',
          'valor': totalMc,
          // Mesa/comanda ainda em aberto: o valor é "a receber" e NÃO entra nos
          // totais (só virará entrada quando o pagamento for registrado).
          'forma': 'A receber · não contabilizado',
          'tipoPagamento': null,
          'icone': mc.tipo == TipoControle.comanda ? Icons.receipt_long : Icons.table_restaurant,
          'cor': Colors.tealAccent,
          'numero': mc.numero,
          'tipo': label,
          'contabilizado': false,
        });
      }
    }

    // Sangrias
    for (final s in ds.getSangriasDoCaixa(ab)) {
      list.add({
        'data': s.data,
        'descricao': s.motivo,
        'valor': -s.valor,
        'forma': 'Dinheiro',
        'tipoPagamento': TipoPagamento.dinheiro,
        'icone': Icons.outbox_rounded,
        'cor': Colors.orangeAccent,
        'numero': '',
        'tipo': 'Pagamento',
        'contabilizado': true,
      });
    }

    // Suprimentos
    for (final s in ds.getSuprimentosDoCaixa(ab)) {
      list.add({
        'data': s.data,
        'descricao': s.motivo,
        'valor': s.valor,
        'forma': 'Dinheiro',
        'tipoPagamento': TipoPagamento.dinheiro,
        'icone': Icons.move_to_inbox_rounded,
        'cor': Colors.blueAccent,
        'numero': '',
        'tipo': 'Suprimento',
        'contabilizado': true,
      });
    }

    list.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));
    return list;
  }

  String _formatForma(TipoPagamento t) {
    switch (t) {
      case TipoPagamento.dinheiro: return 'Dinheiro';
      case TipoPagamento.cartaoCredito: return 'Crédito';
      case TipoPagamento.cartaoDebito: return 'Débito';
      case TipoPagamento.pix: return 'PIX';
      case TipoPagamento.alimentacao: return 'Ticket';
      default: return 'Outro';
    }
  }

  Widget _buildCardCaixa(
    AberturaCaixa abertura,
    FechamentoCaixa? fechamento,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isAberto = fechamento == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isAberto ? Icons.lock_open : Icons.lock,
                    color: isAberto ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abertura.numero,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        formatoData.format(abertura.dataAbertura.toLocal()),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAberto
                        ? Colors.green.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isAberto ? 'Aberto' : 'Fechado',
                    style: TextStyle(
                      color: isAberto ? Colors.green : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Valor Inicial',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                    Text(
                      formatoMoeda.format(abertura.valorInicial),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (fechamento != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Valor Real',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorReal),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (fechamento != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valor Esperado',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.valorEsperado),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Diferença',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                      Text(
                        formatoMoeda.format(fechamento.diferenca),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: fechamento.diferenca >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Fechado em: ${formatoData.format(fechamento.dataFechamento.toLocal())}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoAbertura(BuildContext context, DataService dataService) {
    final valorController = TextEditingController(text: '0.00');
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Abrir Caixa', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor Inicial (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor inicial';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor < 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const HomePage()),
                (route) => false,
              );
            },
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.abrirCaixaComValor(
                    valor,
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Caixa aberto com ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(valor)}',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao abrir caixa: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Abrir Caixa'),
          ),
        ],
      ),
    );
  }

  // Função auxiliar para construir linha de informação
  Widget _buildInfoRow(String label, String value, IconData icon, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white.withOpacity(0.6), size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white.withOpacity(0.9),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _mostrarDialogoFechamento(BuildContext context, DataService dataService,
      {AberturaCaixa? aberturaParam}) {
    final abertura = aberturaParam ?? dataService.aberturaCaixaAtual;
    if (abertura == null) return;

    // Operador/funcionário sem permissão (dashboard.ver_totais) não vê os
    // totais de vendas no fechamento do caixa. O detalhamento por forma de
    // pagamento é controlado por uma permissão própria
    // (caixa.ver_totais_formas_pagamento).
    final authServiceFech = Provider.of<AuthService>(context, listen: false);
    final podeVerTotais = PermissionHelper.podeVerTotais(authServiceFech.usuarioAtual);
    final podeVerFormasPagamento = PermissionHelper.podeVerTotaisFormasPagamento(authServiceFech.usuarioAtual);
    final podeVerTotalVendido = PermissionHelper.podeVerTotalVendidoFechamento(authServiceFech.usuarioAtual);
// (ok)

    final valorEsperadoController = TextEditingController();
    final valorRealController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');

    // Calcular valor esperado baseado nas vendas do caixa em questão
    final vendasDoCaixa = dataService.getVendasDoCaixa(abertura);

    // --- Novos cálculos para detalhamento ---
    //
    // Separação por forma de pagamento a partir da MESMA fonte do card do
    // fluxo e do modal do histórico (`calcularResumoFormaPagamentoDoCaixa`):
    // vendas com pagamento dividido entram por cada parte e formas
    // personalizadas (Caju, VR...) mantêm o nome cadastrado. Antes este
    // diálogo somava só a forma principal de cada venda, então o "Resumo por
    // Forma" aqui divergia do card de "Entradas por Forma de Pagamento".
    final resumoVendasFormas = dataService.calcularResumoFormaPagamentoDoCaixa(abertura);

    // Recebimentos de pedidos/mesas no período, em separado, para o gestor ver
    // quanto veio de venda de balcão e quanto veio de pedido. Mesma fonte usada
    // na impressão do fechamento (DataService).
    final totaisPedidosForma =
        dataService.calcularRecebimentosDePedidosDoCaixa(abertura);

    // Mapa combinado (vendas + pedidos), usado no "Valor Esperado" do caixa
    // físico (só a parcela em DINHEIRO é considerada mais abaixo).
    final totaisPorForma = <TipoPagamento, double>{};
    for (final r in resumoVendasFormas) {
      totaisPorForma[r.tipo] = (totaisPorForma[r.tipo] ?? 0.0) + r.valor;
    }
    totaisPedidosForma.forEach((tipo, valor) {
      totaisPorForma[tipo] = (totaisPorForma[tipo] ?? 0.0) + valor;
    });

    double totalItensVendidos = 0.0;
    double valorTotalProdutos = 0.0;
    // getVendasDoCaixa já exclui vendas canceladas — mesma base do card.
    final totalVendasRealizadas = vendasDoCaixa.length;

    // Processar Vendas Balcão (apenas itens; o valor por forma já veio do
    // resumo acima).
    for (var v in vendasDoCaixa) {
      for (var item in v.itens) {
        totalItensVendidos += item.quantidade;
        valorTotalProdutos += item.subtotal;
      }
    }

    // Processar Pedidos (Mesas/Comandas)
    // IMPORTANTE: só entram pedidos do MESMO operador do caixa (responsavel),
    // e pagamentos feitos dentro da janela [abertura, agora]. Sem esse filtro,
    // pagamentos de mesas de OUTROS operadores eram somados no caixa errado.
    final respCaixa = abertura.responsavel?.trim().toLowerCase();
    final temRespCaixa = respCaixa != null && respCaixa.isNotEmpty;
    bool mesmoOperador(String? a, String? b) {
      if (a == null || b == null) return false;
      String norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9@]'), '');
      final na = norm(a), nb = norm(b);
      if (na.isEmpty || nb.isEmpty) return false;
      if (na == nb) return true;
      final localA = na.contains('@') ? na.split('@').first : na;
      final localB = nb.contains('@') ? nb.split('@').first : nb;
      return localA == localB && localA.isNotEmpty;
    }

    for (var p in dataService.pedidos) {
      // Filtro de operador do pedido (vendedorNome), quando o caixa é nominado.
      if (temRespCaixa) {
        final operadorPedido = p.vendedorNome;
        if (operadorPedido == null || operadorPedido.trim().isEmpty) continue;
        if (!mesmoOperador(operadorPedido, respCaixa)) continue;
      }

      // Os totais por forma dos pedidos vêm de
      // `calcularRecebimentosDePedidosDoCaixa` (mesma regra da impressão);
      // aqui só contamos os itens dos pedidos recebidos no período.

      // Contabilizar itens dos pedidos recebidos no período
      // (Aproximação: se o pedido teve pagamento no período, contamos seus itens)
      final tevePagamentoNoPeriodo = p.pagamentos.any((pag) => 
        pag.recebido && 
        pag.dataRecebimento != null && 
        !pag.dataRecebimento!.isBefore(abertura.dataAbertura)
      );
      
      if (tevePagamentoNoPeriodo) {
        for (var item in p.produtos) {
          totalItensVendidos += item.quantidade;
          valorTotalProdutos += (item.preco * item.quantidade);
        }
        for (var item in p.servicos) {
          totalItensVendidos += 1;
          valorTotalProdutos += (item.valor + item.valorAdicional);
        }
      }
    }

    // Calcular sangrias e suprimentos do caixa em questão
    final sangriasCaixaAtual = dataService.getSangriasDoCaixa(abertura);
    final suprimentosCaixaAtual = dataService.getSuprimentosDoCaixa(abertura);
    final totalSangrias = sangriasCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    final totalSuprimentos = suprimentosCaixaAtual.fold(0.0, (sum, s) => sum + s.valor);
    
    // Valor esperado no caixa FÍSICO (Dinheiro + Inicial + Suprimentos - Sangrias)
    // Nota: PIX/Cartão não ficam no caixa físico, mas o sistema pode querer rastrear
    // Aqui mantemos a lógica original de "Dinheiro + PIX" se assim estava,
    // mas geralmente PIX não entra na conferência de "dinheiro na gaveta".
    // Vou ajustar para ser apenas DINHEIRO + INICIAL para o "Esperado" físico.
    final totalDinheiro = totaisPorForma[TipoPagamento.dinheiro] ?? 0.0;
    final valorEsperadoCalculado = abertura.valorInicial + totalDinheiro - totalSangrias + totalSuprimentos;
    
    valorEsperadoController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');
    valorRealController.text = valorEsperadoCalculado.toStringAsFixed(2).replaceAll('.', ',');

    bool salvandoFechamento = false;

    Future<void> fecharCaixa(BuildContext dialogContext, {required bool imprimir}) async {
      print('>>> [Fechar Caixa] ========== BOTÃO PRESSIONADO ==========');
      if (salvandoFechamento) {
        print('>>> [Fechar Caixa] Ignorando clique duplicado...');
        return;
      }
      salvandoFechamento = true;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Processando fechamento...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }

      if (formKey.currentState == null) {
        print('>>> [Fechar Caixa] ERRO: formKey.currentState é null!');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Formulário não inicializado'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final isValid = formKey.currentState!.validate();
      if (!isValid) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, preencha todos os campos obrigatórios corretamente'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      formKey.currentState!.save();

      try {
        final valorEsperadoStr = valorEsperadoController.text.replaceAll('.', '').replaceAll(',', '.');
        final valorRealStr = valorRealController.text.replaceAll('.', '').replaceAll(',', '.');

        final valorEsperado = double.tryParse(valorEsperadoStr) ?? 0.0;
        final valorReal = double.tryParse(valorRealStr) ?? 0.0;

        final responsavel = responsavelController.text.trim().isEmpty
            ? null
            : responsavelController.text.trim();

        final fechamento = await dataService.registrarFechamentoCaixa(
          valorEsperado: valorEsperado,
          valorReal: valorReal,
          observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
          responsavel: responsavel,
          abertura: abertura,
        );

        if (fechamento == null) {
          print('>>> [Fechar Caixa] ERRO: Fechamento retornou null');
          salvandoFechamento = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Erro ao fechar caixa.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        if (context.mounted) {
          Navigator.pop(dialogContext);

          if (imprimir && abertura != null) {
            await _imprimirFechamento(abertura, fechamento);
          } else if (!imprimir && abertura != null) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Column(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Caixa Encerrado!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'O caixa ${abertura.numero} foi fechado com sucesso.',
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Diferença: ${formatoMoeda.format(fechamento.diferenca)}',
                      style: TextStyle(
                        color: fechamento.diferenca >= 0 ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Column(
                    children: [
                      if (podeVerTotais)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _imprimirFechamento(abertura, fechamento);
                              if (context.mounted) Navigator.pop(context);
                            },
                            icon: const Icon(Icons.print),
                            label: const Text('IMPRIMIR FECHAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('CONCLUIR E SAIR', style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomePage()),
              (route) => false,
            );
          }
        }
      } catch (e) {
        print('>>> [Fechar Caixa] EXCEÇÃO: $e');
        salvandoFechamento = false;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao fechar caixa: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.redAccent.withOpacity(0.3),
                Colors.red.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fechar Caixa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Preencha os dados para finalizar',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Informações da abertura - Card melhorado
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.withOpacity(0.2),
                        Colors.blue.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.4), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.point_of_sale, color: Colors.blueAccent, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            abertura.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.event, color: Colors.white54, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Aberto em: ${formatoData.format(abertura.dataAbertura.toLocal())}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEstatsCard(
                              'Vendas',
                              totalVendasRealizadas.toString(),
                              Icons.receipt_long,
                              Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEstatsCard(
                              'Itens Vendidos',
                              totalItensVendidos.toString(),
                              Icons.inventory_2,
                              Colors.orangeAccent,
                            ),
                          ),
                          // Total em R$ dos itens: só para quem pode ver totais
                          if (podeVerTotais) const SizedBox(width: 12),
                          if (podeVerTotais)
                            Expanded(
                              child: _buildEstatsCard(
                                'Total em Itens',
                                formatoMoeda.format(valorTotalProdutos),
                                Icons.monetization_on,
                                Colors.greenAccent,
                              ),
                            ),
                        ],
                      ),
                      // Total por forma de pagamento: permissão própria
                      // (caixa.ver_totais_formas_pagamento)
                      if (podeVerFormasPagamento) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Resumo por Forma de Pagamento',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Vendas do PDV por forma (pagamento dividido detalhado,
                        // nome da forma personalizada preservado).
                        ...resumoVendasFormas.where((r) => r.valor > 0).map((r) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildInfoRow(
                              r.rotulo,
                              formatoMoeda.format(r.valor),
                              r.tipo.icone,
                              r.tipo.cor,
                            ),
                          );
                        }),
                        // Recebimentos de pedidos/mesas (fonte separada, para o
                        // gestor saber o que veio de balcão e o que veio de pedido).
                        if (totaisPedidosForma.values.any((v) => v > 0)) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Recebimentos de Pedidos/Mesas',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...totaisPedidosForma.entries.where((e) => e.value > 0).map((e) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _buildInfoRow(
                                e.key.nome,
                                formatoMoeda.format(e.value),
                                e.key.icone,
                                e.key.cor,
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 12),
                      ],
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Movimentações (Sangria/Sup.)',
                        formatoMoeda.format(totalSuprimentos - totalSangrias),
                        Icons.swap_vert,
                        (totalSuprimentos - totalSangrias) >= 0 ? Colors.blueAccent : Colors.orangeAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Fundo de Caixa Inicial',
                        formatoMoeda.format(abertura.valorInicial),
                        Icons.account_balance_wallet,
                        Colors.grey,
                      ),
                      if (podeVerTotalVendido) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.calculate, color: Colors.greenAccent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Valor Esperado',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              formatoMoeda.format(valorEsperadoCalculado),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Seção de Valores
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.attach_money, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Valores do Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (podeVerTotalVendido) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: valorEsperadoController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Esperado (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.calculate, color: Colors.blueAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor esperado';
                          }
                          final valor = double.tryParse(
                            value.replaceAll('.', '').replaceAll(',', '.'),
                          );
                          if (valor == null || valor < 0) {
                            return 'Valor inválido';
                          }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: valorRealController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Valor Real no Caixa (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: '0,00',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.account_balance_wallet, color: Colors.greenAccent),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Informe o valor real';
                          }
                          final valor = double.tryParse(
                            value.replaceAll('.', '').replaceAll(',', '.'),
                          );
                          if (valor == null || valor < 0) {
                            return 'Valor inválido';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Informações do Responsável
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.purple.withOpacity(0.15),
                        Colors.purple.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline, color: Colors.purpleAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Responsável pelo Fechamento',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: responsavelController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: 'Nome Completo',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Ex: João Silva',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: const Icon(Icons.person, color: Colors.purpleAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red, width: 2),
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                        // Campo agora é opcional - sem validação obrigatória
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Seção de Observações
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.note_alt, color: Colors.orangeAccent, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Observações',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OPCIONAL',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: observacaoController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Informe observações sobre o fechamento:\n• Diferenças encontradas\n• Problemas identificados\n• Observações importantes',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13,
                            height: 1.5,
                          ),
                          prefixIcon: const Icon(Icons.edit_note, color: Colors.orangeAccent, size: 24),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
                          ),
                        ),
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Informação sobre campos obrigatórios
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Certifique-se de preencher todos os campos obrigatórios antes de fechar o caixa.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => fecharCaixa(dialogContext, imprimir: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Fechar Caixa',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => fecharCaixa(dialogContext, imprimir: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.print, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Fechar e Imprimir',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSangria(BuildContext context, DataService dataService, {bool isPagamento = false}) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isPagamento ? Icons.outbox : Icons.remove_circle, color: isPagamento ? Colors.purpleAccent : Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text(isPagamento ? 'Registrar Pagamento' : 'Registrar Sangria', style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSangria(
                    valor: valor,
                    motivo: isPagamento ? '[PAGAMENTO] ${motivoController.text.trim()}' : motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isPagamento 
                            ? 'Pagamento registrado: ${formatoMoeda.format(valor)}'
                            : 'Sangria registrada: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: isPagamento ? Colors.purple : Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar sangria: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoSuprimento(BuildContext context, DataService dataService) {
    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.add_circle, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text('Registrar Suprimento', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Informe o valor';
                    }
                    final valor = double.tryParse(
                      value.replaceAll('.', '').replaceAll(',', '.'),
                    );
                    if (valor == null || valor <= 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: motivoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Motivo *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o motivo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: responsavelController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Responsável (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: observacaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final valor = double.parse(
                    valorController.text.replaceAll('.', '').replaceAll(',', '.'),
                  );

                  await dataService.registrarSuprimento(
                    valor: valor,
                    motivo: motivoController.text.trim(),
                    observacao: observacaoController.text.trim().isEmpty
                        ? null
                        : observacaoController.text.trim(),
                    responsavel: responsavelController.text.trim().isEmpty
                        ? null
                        : responsavelController.text.trim(),
                  );

                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Suprimento registrado: ${formatoMoeda.format(valor)}',
                        ),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao registrar suprimento: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEstatsCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

