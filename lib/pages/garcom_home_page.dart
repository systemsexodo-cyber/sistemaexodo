import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/garcom_service.dart';
import 'cozinha_mesas_funcionario_page.dart';

/// Página principal do GARÇOM: acesso restrito.
///
/// Menu com botões grandes (touch):
/// 1. Mesas/Comandas — a tela de controle existente;
/// 2. Minhas Vendas — vendas e comissões do garçom logado no período;
/// 3. Ranking — ranking de todos os garçons com medalhas e incentivos.
class GarcomHomePage extends StatefulWidget {
  const GarcomHomePage({super.key});

  @override
  State<GarcomHomePage> createState() => _GarcomHomePageState();
}

class _GarcomHomePageState extends State<GarcomHomePage> {
  @override
  void initState() {
    super.initState();
    // Garante que o garçom logado é o operador das mesas/comandas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);
      final usuario = authService.usuarioAtual;
      if (usuario != null) {
        dataService.responsavelAtivo = usuario.email ?? usuario.nome;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dataService = Provider.of<DataService>(context);
    final usuario = authService.usuarioAtual;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Modo Garçom',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              '👨‍🍳 ${usuario?.nome ?? ''}',
              style: TextStyle(color: Colors.orangeAccent.withOpacity(0.9), fontSize: 13),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () => authService.logout(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _botaoMenu(
              icone: Icons.table_restaurant,
              titulo: 'Mesas e Comandas',
              subtitulo: 'Abrir, lançar itens e acompanhar mesas e comandas',
              cor: Colors.orangeAccent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CozinhaMesasFuncionarioPage()),
              ),
            ),
            const SizedBox(height: 14),
            _botaoMenu(
              icone: Icons.payments_outlined,
              titulo: 'Minhas Vendas e Comissões',
              subtitulo: 'Quanto vendi e quanto vou receber de comissão',
              cor: Colors.greenAccent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const _MinhasVendasPage()),
              ),
            ),
            const SizedBox(height: 14),
            _botaoMenu(
              icone: Icons.emoji_events_outlined,
              titulo: 'Ranking dos Garçons',
              subtitulo: 'Veja quem está vendendo mais e ganhe as medalhas',
              cor: Colors.amberAccent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const _RankingPage()),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quanto mais você vende, mais comissão ganha. Bora subir no ranking! 💪',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoMenu({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF1E1E2E),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cor.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: cor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.4), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// Página com as vendas e comissões do garçom logado.
class _MinhasVendasPage extends StatefulWidget {
  const _MinhasVendasPage();

  @override
  State<_MinhasVendasPage> createState() => _MinhasVendasPageState();
}

class _MinhasVendasPageState extends State<_MinhasVendasPage> {
  String _periodo = 'hoje'; // hoje, semana, mês

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    final usuario = authService.usuarioAtual;

    // Funcionário garçom associado ao usuário logado
    final funcionario = dataService.funcionarios
        .where((f) => f.id == usuario?.funcionarioId && f.garcom)
        .firstOrNull;

    final inicio = GarcomService.inicioDoPeriodo(_periodo);
    final fim = GarcomService.fimDoPeriodo(_periodo);

    final resumo = funcionario != null
        ? GarcomService.resumoDoGarcom(
            funcionario: funcionario,
            vendas: dataService.vendasBalcao,
            pedidos: dataService.pedidos,
            inicio: inicio,
            fim: fim,
          )
        : null;

    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    // Vendas do garçom no período (para a listagem)
    final minhasVendas = <Map<String, dynamic>>[];
    if (funcionario != null) {
      for (final v in dataService.vendasBalcao) {
        if (v.cancelado) continue;
        if (v.dataVenda.isBefore(inicio) || v.dataVenda.isAfter(fim)) continue;
        if (!GarcomService.vendaEdoGarcom(funcionario, v.operador)) continue;
        minhasVendas.add({
          'numero': v.numero,
          'cliente': v.clienteNome ?? '—',
          'data': v.dataVenda,
          'valor': v.valorTotal,
          'tipo': 'Venda',
        });
      }
      for (final p in dataService.pedidos) {
        if (p.status == 'Cancelado') continue;
        if (p.dataPedido.isBefore(inicio) || p.dataPedido.isAfter(fim)) continue;
        if (!GarcomService.vendaEdoGarcom(funcionario, p.operador)) continue;
        minhasVendas.add({
          'numero': p.numero,
          'cliente': p.clienteNome ?? '—',
          'data': p.dataPedido,
          'valor': p.total,
          'tipo': 'Pedido',
        });
      }
      minhasVendas.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        title: const Text('Minhas Vendas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Seletor de período
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                _chipPeriodo('hoje', 'Hoje'),
                const SizedBox(width: 8),
                _chipPeriodo('semana', 'Semana'),
                const SizedBox(width: 8),
                _chipPeriodo('mês', 'Mês'),
              ],
            ),
          ),
          if (funcionario == null)
            Expanded(
              child: Center(
                child: Text(
                  'Seu usuário não está vinculado a um garçom cadastrado.\nPeça ao administrador para marcar "Garçom" no seu cadastro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                ),
              ),
            )
          else ...[
            // Cards de resumo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _cardResumo(
                      label: 'Total Vendido',
                      valor: formatoMoeda.format(resumo?.totalVendido ?? 0),
                      cor: Colors.greenAccent,
                      icone: Icons.attach_money,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _cardResumo(
                      label: 'Comissão (${resumo?.percentual.toStringAsFixed(1) ?? '0'}%)',
                      valor: formatoMoeda.format(resumo?.totalComissao ?? 0),
                      cor: Colors.orangeAccent,
                      icone: Icons.trending_up,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _cardResumo(
                      label: 'Vendas',
                      valor: '${resumo?.totalVendas ?? 0}',
                      cor: Colors.blueAccent,
                      icone: Icons.receipt_long,
                    ),
                  ),
                ],
              ),
            ),
            // Lista de vendas do período
            Expanded(
              child: minhasVendas.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma venda no período',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: minhasVendas.length,
                      itemBuilder: (context, index) {
                        final v = minhasVendas[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  v['tipo'] == 'Pedido' ? Icons.delivery_dining : Icons.receipt,
                                  color: Colors.orangeAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${v['numero']} • ${v['tipo']}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      v['cliente'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                    ),
                                    Text(
                                      DateFormat('dd/MM HH:mm').format(v['data'] as DateTime),
                                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatoMoeda.format(v['valor']),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipPeriodo(String valor, String label) {
    final ativo = _periodo == valor;
    return GestureDetector(
      onTap: () => setState(() => _periodo = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ativo ? Colors.orange.withOpacity(0.25) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? Colors.orange : Colors.white12, width: ativo ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: ativo ? Colors.white : Colors.white70,
            fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _cardResumo({
    required String label,
    required String valor,
    required Color cor,
    required IconData icone,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(height: 6),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Página com o ranking dos garçons (medalhas + incentivos).
class _RankingPage extends StatefulWidget {
  const _RankingPage();

  @override
  State<_RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<_RankingPage> {
  String _periodo = 'semana';

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final inicio = GarcomService.inicioDoPeriodo(_periodo);
    final fim = GarcomService.fimDoPeriodo(_periodo);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final ranking = GarcomService.rankingGarcons(
      funcionarios: dataService.funcionarios,
      vendas: dataService.vendasBalcao,
      pedidos: dataService.pedidos,
      inicio: inicio,
      fim: fim,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        title: const Text('Ranking dos Garçons',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                _chipPeriodo('hoje', 'Hoje'),
                const SizedBox(width: 8),
                _chipPeriodo('semana', 'Semana'),
                const SizedBox(width: 8),
                _chipPeriodo('mês', 'Mês'),
                const Spacer(),
                const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 22),
              ],
            ),
          ),
          if (ranking.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Nenhum garçom cadastrado ainda.\nCadastre garçons no menu Funcionários.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: ranking.length,
                itemBuilder: (context, index) {
                  final item = ranking[index];
                  final medalha = index == 0
                      ? '🥇'
                      : index == 1
                          ? '🥈'
                          : index == 2
                              ? '🥉'
                              : '${index + 1}º';
                  final corDestaque = index == 0
                      ? Colors.amberAccent
                      : index == 1
                          ? Colors.blueGrey
                          : index == 2
                              ? Colors.brown
                              : Colors.white;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: index == 0 ? Colors.amberAccent.withOpacity(0.6) : Colors.white10,
                        width: index == 0 ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(medalha, style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.funcionario.nome,
                                style: TextStyle(
                                  color: corDestaque,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.totalVendas} venda${item.totalVendas == 1 ? '' : 's'} • Comissão ${item.percentual.toStringAsFixed(1)}%',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatoMoeda.format(item.totalVendido),
                              style: TextStyle(
                                color: corDestaque,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Comissão: ${formatoMoeda.format(item.totalComissao)}',
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipPeriodo(String valor, String label) {
    final ativo = _periodo == valor;
    return GestureDetector(
      onTap: () => setState(() => _periodo = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ativo ? Colors.orange.withOpacity(0.25) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? Colors.orange : Colors.white12, width: ativo ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: ativo ? Colors.white : Colors.white70,
            fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
