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

  // Filtros do Fluxo de Caixa (Movimentações do Dia)
  final TextEditingController _buscaFluxoController = TextEditingController();
  String _termoBuscaFluxo = '';
  String _filtroTipoFluxo = 'Todos';
  bool _mostrarTodosCaixas = false;

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    // Operador/funcionário sem permissão (dashboard.ver_totais) não vê o total
    // de vendas/entradas do caixa — apenas o saldo para operar.
    final podeVerTotais = PermissionHelper.podeVerTotais(usuarioLogado);
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
                      child: _buildResumoSession(dataService, aberturaAtual, podeVerTotais),
                    ),
                  ),

                // 3. Filtros do Fluxo de Caixa (tipos + busca)
                if (caixaAberto && aberturaAtual != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: _buildFiltrosFluxo(),
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
                  _buildSliverFluxoLista(dataService, aberturaAtual),

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
    final subtitulo = nomeResp +
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

      await CaixaPDFService.gerarPDFTermico(
        abertura: ab,
        fechamento: fe,
        empresa: empresa,
        vendas: vendas,
        itensDeletadosExtra: canceladosExtra,
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

  Widget _buildResumoSession(DataService ds, AberturaCaixa abertura, bool podeVerTotais) {
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

    return Row(
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

  Widget _buildSliverFluxoLista(DataService ds, AberturaCaixa abertura) {
    // Se "Apenas Meu Caixa" está DESMARCADO, buscar de TODOS os caixas abertos;
    // caso contrário, apenas do caixa selecionado.
    List<Map<String, dynamic>> movs;
    if (_mostrarTodosCaixas) {
      // Modo global: juntar movimentações de todos os caixas abertos
      movs = [];
      for (final caixa in ds.aberturasCaixaAbertas) {
        movs.addAll(_getMovimentacoesExt(ds, caixa));
      }
      // Remover duplicatas por combinação data+descricao+valor
      final seen = <String>{};
      movs = movs.where((m) {
        final key = '${m['data']}_${m['descricao']}_${m['valor']}';
        if (seen.contains(key)) return false;
        seen.add(key);
        return true;
      }).toList();
    } else {
      movs = _getMovimentacoesExt(ds, abertura);
    }

    // Aplicar filtro por tipo
    if (_filtroTipoFluxo != 'Todos') {
      movs = movs.where((m) {
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

    // Aplicar busca por texto (número da venda, descrição)
    if (_termoBuscaFluxo.isNotEmpty) {
      final t = _termoBuscaFluxo.toLowerCase();
      movs = movs.where((m) {
        final desc = (m['descricao'] ?? '').toString().toLowerCase();
        final num = (m['numero'] ?? '').toString().toLowerCase();
        return desc.contains(t) || num.contains(t);
      }).toList();
    }

    if (movs.isEmpty) {
      final temFiltro = _filtroTipoFluxo != 'Todos' || _termoBuscaFluxo.isNotEmpty || _mostrarTodosCaixas;
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
          (context, index) {
            final m = movs[index];
            return Container(
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
                title: Text(
                  m['descricao'].toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${formatoHora.format((m['data'] as DateTime).toLocal())} • ${m['forma']}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                ),
                trailing: Text(
                  formatoMoeda.format(m['valor']),
                  style: TextStyle(
                    color: (m['valor'] as double) >= 0 ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            );
          },
          childCount: movs.length,
        ),
      ),
    );
  }

  /// Barra de filtros do Fluxo de Caixa (Movimentações do Dia)
  Widget _buildFiltrosFluxo() {
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
              if (_filtroTipoFluxo != 'Todos' || _termoBuscaFluxo.isNotEmpty || _mostrarTodosCaixas)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroTipoFluxo = 'Todos';
                    _termoBuscaFluxo = '';
                    _mostrarTodosCaixas = false;
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

  /// Barra de filtros do Histórico de Encerramentos (data e número do caixa)
  Widget _buildFiltrosHistorico(DataService ds) {
    final numerosCaixa = ds.aberturasCaixa
        .map((a) => a.numero)
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final temFiltro = _filtroNumeroCaixa != 'Todos' ||
        _filtroDataInicio != null || _filtroDataFim != null;

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

    hist.sort((a, b) => b.key.dataAbertura.compareTo(a.key.dataAbertura));

    if (hist.isEmpty) {
      final temFiltro = _filtroNumeroCaixa != 'Todos' ||
          _filtroDataInicio != null || _filtroDataFim != null;
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

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = hist[index];
            return _buildCardCaixaModerno(item.key, item.value!, ds, podeVerTotais);
          },
          childCount: hist.length,
        ),
      ),
    );
  }

  Widget _buildCardCaixaModerno(AberturaCaixa ab, FechamentoCaixa fe, DataService ds, bool podeVerTotais) {
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
                    '${ab.numero}  •  ${DateFormat('dd MMM').format(ab.dataAbertura.toLocal())}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        ],
      ),
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
          'icone': Icons.shopping_basket_rounded,
          'cor': Colors.greenAccent,
          'numero': v.numero,
          'tipo': 'Venda',
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
          'forma': 'A Receber',
          'icone': mc.tipo == TipoControle.comanda ? Icons.receipt_long : Icons.table_restaurant,
          'cor': Colors.tealAccent,
          'numero': mc.numero,
          'tipo': label,
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
        'icone': Icons.outbox_rounded,
        'cor': Colors.orangeAccent,
        'numero': '',
        'tipo': 'Pagamento',
      });
    }

    // Suprimentos
    for (final s in ds.getSuprimentosDoCaixa(ab)) {
      list.add({
        'data': s.data,
        'descricao': s.motivo,
        'valor': s.valor,
        'forma': 'Dinheiro',
        'icone': Icons.move_to_inbox_rounded,
        'cor': Colors.blueAccent,
        'numero': '',
        'tipo': 'Suprimento',
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
    final totaisPorForma = <TipoPagamento, double>{};
    double totalItensVendidos = 0.0;
    double valorTotalProdutos = 0.0;
    int totalVendasRealizadas = 0;

    // Inicializar mapa de totais
    for (var tipo in TipoPagamento.values) {
      if (tipo != TipoPagamento.outro) {
        totaisPorForma[tipo] = 0.0;
      }
    }

    // Processar Vendas Balcão
    for (var v in vendasDoCaixa) {
      if (v.isCancelada || v.tipoPagamento == TipoPagamento.outro) continue;
      
      totalVendasRealizadas++;
      totaisPorForma[v.tipoPagamento] = (totaisPorForma[v.tipoPagamento] ?? 0.0) + v.valorTotal;
      
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

      for (var pag in p.pagamentos) {
        if (!pag.recebido || pag.dataRecebimento == null) continue;
        if (pag.dataRecebimento!.isBefore(abertura.dataAbertura)) continue;
        if (pag.tipo == TipoPagamento.outro) continue;

        totaisPorForma[pag.tipo] = (totaisPorForma[pag.tipo] ?? 0.0) + pag.valor;
      }
      
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
                        // Lista de formas de pagamento
                        ...totaisPorForma.entries.where((e) => e.value > 0).map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildInfoRow(
                              e.key.nome,
                              formatoMoeda.format(e.value),
                              e.key.icone,
                              e.key.cor,
                            ),
                          );
                        }).toList(),
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

