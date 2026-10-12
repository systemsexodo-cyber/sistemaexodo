import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/departamento.dart';
import '../models/empresa.dart';
import '../models/ticket_producao.dart';
import '../services/data_service.dart';
import '../services/fila_producao_service.dart';
import '../services/producao_pdf_service.dart';
import 'cadastro_departamentos_page.dart';

/// MONITOR DE PRODUÇÃO — as vias que não chegaram na impressora do setor.
///
/// Quando um pedido/venda é lançado, cada setor (Cozinha, Bar, ...) recebe uma
/// via na SUA impressora. Se a impressora está desligada, sem papel ou com o
/// nome errado, a via não sai — e antes isso só aparecia no console.
///
/// Aqui o pessoal da cozinha/bar vê o que ficou faltando POR SETOR e reimprime
/// só o setor que falhou (uma via ou todas as do setor), sem mexer nos setores
/// que já imprimiram.
///
/// A fila é DESTA MÁQUINA: as impressoras são locais, então uma via que falhou
/// aqui só pode ser reimpressa de um PC que tenha aquela impressora.
class MonitorProducaoPage extends StatefulWidget {
  const MonitorProducaoPage({super.key});

  @override
  State<MonitorProducaoPage> createState() => _MonitorProducaoPageState();
}

class _MonitorProducaoPageState extends State<MonitorProducaoPage>
    with TickerProviderStateMixin {
  final FilaProducaoService _fila = FilaProducaoService.instancia;
  TabController? _tabController;
  int _ultimoTamanho = -1;
  bool _reimprimindo = false;

  @override
  void initState() {
    super.initState();
    _fila.addListener(_aoMudarFila);
    if (!_fila.carregada) {
      // Garante que a fila do terminal está em memória mesmo se a tela de
      // produção ainda não foi aberta nesta sessão.
      _fila.carregar();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildTabController(context);
    // Empresa trocada (ou primeira abertura): recarrega a fila do terminal.
    if (!_fila.carregada) _fila.carregar();
  }

  @override
  void dispose() {
    _fila.removeListener(_aoMudarFila);
    _tabController?.dispose();
    super.dispose();
  }

  void _aoMudarFila() {
    if (mounted) setState(() {});
  }

  List<Departamento> _setores(BuildContext context) {
    final ds = Provider.of<DataService>(context, listen: true);
    final deps = ds.departamentos;
    if (deps.isEmpty) {
      return [
        Departamento(
            id: 'dep_cozinha',
            nome: 'Cozinha',
            cor: '#FF5722',
            icone: 'restaurant'),
        Departamento(
            id: 'dep_bar', nome: 'Bar', cor: '#2196F3', icone: 'local_bar'),
      ];
    }
    return deps;
  }

  void _rebuildTabController(BuildContext context) {
    final setores = _setores(context);
    final tamanho = setores.length;
    final novoLength = tamanho + 1; // setores + 'Todos'
    if (_tabController == null ||
        _ultimoTamanho != tamanho ||
        _tabController!.length != novoLength) {
      final indiceAtual = _tabController?.index ?? 0;
      final indiceClamped = indiceAtual.clamp(0, novoLength - 1);
      _tabController?.dispose();
      _tabController = TabController(
        length: novoLength,
        vsync: this,
        initialIndex: indiceClamped,
      );
      _ultimoTamanho = tamanho;
    }
  }

  IconData _iconeDepartamento(Departamento d) {
    switch (d.icone) {
      case 'local_bar':
        return Icons.local_bar;
      case 'soup_kitchen':
        return Icons.soup_kitchen;
      case 'bakery_dining':
        return Icons.bakery_dining;
      case 'icecream':
        return Icons.icecream;
      case 'coffee':
        return Icons.coffee;
      case 'flatware':
        return Icons.flatware;
      case 'kitchen':
        return Icons.kitchen;
      default:
        return Icons.restaurant;
    }
  }

  /// "Nº 3" — para o rodapé da aba (quantas vias estão pendentes).
  String _abaComContagem(String nome, int pendentes) =>
      pendentes > 0 ? '$nome ($pendentes)' : nome;

  @override
  Widget build(BuildContext context) {
    final setores = _setores(context);
    final total = _fila.total;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.print_outlined, color: Colors.amberAccent),
            const SizedBox(width: 8),
            const Text(
              'Monitor de Produção',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            if (total > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  '$total pendente${total == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Recarregar a fila deste terminal',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () async {
              await _fila.carregar();
              if (!mounted) return;
              _avisar('Fila recarregada deste terminal.', Colors.blueGrey);
            },
          ),
          IconButton(
            tooltip: 'Gerenciar Departamentos',
            icon: const Icon(Icons.food_bank_outlined, color: Colors.orangeAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CadastroDepartamentosPage(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: [
            ...setores.map((d) => Tab(
                  icon: Icon(_iconeDepartamento(d)),
                  text: _abaComContagem(d.nome, _fila.contarDoSetor(d.nome)),
                )),
            Tab(
              icon: const Icon(Icons.view_list),
              text: _abaComContagem('Todos', _fila.total),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _faixaDeAviso(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ...setores.map((d) => _listaDoSetor(d.nome, departamento: d)),
                _listaDoSetor('Todos'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faixaDeAviso() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E1E2E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Esta fila é deste terminal (as impressoras de produção são locais). '
              'Reimprimir manda a via só para o setor escolhido.',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  /// Lista das vias pendentes de um setor ('Todos' mostra tudo, em ordem).
  Widget _listaDoSetor(String setor, {Departamento? departamento}) {
    if (!_fila.carregada) {
      return const Center(child: CircularProgressIndicator());
    }

    final ehTodos = setor == 'Todos';
    final vias = ehTodos ? _fila.pendentes : _fila.pendentesDoSetor(setor);
    final descricaoImpressora = departamento == null
        ? null
        : ProducaoPdfService.descricaoImpressorasDoDepartamento(departamento);

    if (vias.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 80, color: Colors.green.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              ehTodos ? 'Nenhuma via pendente' : 'Nenhuma via pendente em $setor',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              'Tudo o que foi lançado chegou na impressora do setor.',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _cabecalhoDoSetor(setor, vias.length, descricaoImpressora),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: vias.length,
            itemBuilder: (context, index) => _cardVia(
              vias[index],
              mostrarSetor: ehTodos,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cabecalhoDoSetor(String setor, int pendentes, String? impressora) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  setor == 'Todos'
                      ? '$pendentes via(s) esperando reimpressão'
                      : '$setor: $pendentes via(s) não saíram na impressora',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              if (setor != 'Todos' && pendentes > 1)
                OutlinedButton.icon(
                  onPressed: _reimprimindo
                      ? null
                      : () => _reimprimirDoSetor(setor),
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('REIMPRIMIR SETOR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                  ),
                ),
            ],
          ),
          if (impressora != null) ...[
            const SizedBox(height: 6),
            Text(
              'Impressora do setor: $impressora',
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardVia(TicketProducao ticket, {bool mostrarSetor = false}) {
    final idade = DateTime.now().difference(ticket.criadoEm);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ticket.tipoDocumento,
                  style: const TextStyle(
                      color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nº ${ticket.documento}'
                  '${mostrarSetor ? ' • ${ticket.setor}' : ''}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Text(
                _idade(idade),
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
          if ((ticket.referencia ?? '').trim().isNotEmpty ||
              (ticket.cliente ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if ((ticket.referencia ?? '').trim().isNotEmpty)
                  ticket.referencia!.trim(),
                if ((ticket.cliente ?? '').trim().isNotEmpty)
                  'Cliente: ${ticket.cliente!.trim()}',
              ].join(' • '),
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          for (final linha in ticket.resumoItens)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $linha',
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
          if (ticket.resumoItens.isEmpty)
            Text(
              '${ticket.quantidadeItens} item(ns)',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Impressora: ${ticket.descricaoImpressora}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  ticket.ultimoErro ?? 'A via não saiu na impressora do setor',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  '${ticket.tentativas} tentativa(s)'
                  '${ticket.tentativas > 1 ? ' — a última ${_idade(DateTime.now().difference(ticket.ultimaTentativaEm))}' : ''}',
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _reimprimindo ? null : () => _reimprimirVia(ticket),
                icon: const Icon(Icons.print, size: 16),
                label: const Text('REIMPRIMIR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _reimprimindo
                    ? null
                    : () => _descartarVia(ticket),
                icon: const Icon(Icons.check, size: 16, color: Colors.white54),
                label: const Text('JÁ SAIU / DESCARTAR',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _idade(Duration d) {
    if (d.inSeconds < 60) return 'agora';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    if (d.inHours < 24) return 'há ${d.inHours} h';
    return 'há ${d.inDays} d';
  }

  Future<void> _reimprimirVia(TicketProducao ticket) async {
    final empresa = _empresaAtual();
    if (empresa == null) return;

    setState(() => _reimprimindo = true);
    final ok = await ProducaoPdfService.reimprimirTicket(
      ticket: ticket,
      empresa: empresa,
      fila: _fila,
    );
    if (!mounted) return;
    setState(() => _reimprimindo = false);
    _avisar(
      ok
          ? '✅ Via de ${ticket.setor} (Nº ${ticket.documento}) reimpressa'
          : '❌ A via de ${ticket.setor} não saiu de novo — continua na fila',
      ok ? Colors.green : Colors.redAccent,
    );
  }

  /// Reimprime TODAS as vias pendentes de um setor — só as daquele setor.
  Future<void> _reimprimirDoSetor(String setor) async {
    final empresa = _empresaAtual();
    if (empresa == null) return;

    final vias = _fila.pendentesDoSetor(setor);
    if (vias.isEmpty) return;

    setState(() => _reimprimindo = true);
    var sucessos = 0;
    for (final via in vias) {
      final ok = await ProducaoPdfService.reimprimirTicket(
        ticket: via,
        empresa: empresa,
        fila: _fila,
      );
      if (ok) sucessos++;
    }
    if (!mounted) return;
    setState(() => _reimprimindo = false);
    _avisar(
      sucessos == vias.length
          ? '✅ $sucessos via(s) de $setor reimpressa(s)'
          : '⚠️ $sucessos de ${vias.length} via(s) de $setor reimpressa(s) — as demais continuam pendentes',
      sucessos == vias.length ? Colors.green : Colors.orange,
    );
  }

  Future<void> _descartarVia(TicketProducao ticket) async {
    await _fila.descartar(ticket.id);
    if (!mounted) return;
    _avisar('Via de ${ticket.setor} (Nº ${ticket.documento}) removida da fila.',
        Colors.blueGrey);
  }

  Empresa? _empresaAtual() {
    final ds = Provider.of<DataService>(context, listen: false);
    final empresa = ds.empresaAtual;
    if (empresa == null) {
      _avisar('Empresa não encontrada para reimprimir.', Colors.redAccent);
    }
    return empresa;
  }

  void _avisar(String mensagem, Color cor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: cor,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
