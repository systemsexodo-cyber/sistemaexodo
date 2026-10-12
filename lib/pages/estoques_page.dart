import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/estoque.dart';
import '../models/estoque_historico.dart';
import '../models/produto.dart';
import '../services/data_service.dart';

const _uuid = Uuid();

/// ESTOQUES — onde a mercadoria fica (Loja, Depósito, Caminhão…).
///
/// Três coisas nesta tela:
/// 1. os estoques cadastrados (qual é o PRINCIPAL, onde a venda acontece);
/// 2. a TRANSFERÊNCIA de mercadoria de um estoque para outro;
/// 3. as transferências recentes, para conferir o que já foi movimentado.
///
/// A venda também transfere sozinha: quando o saldo não está no estoque
/// principal, o app traz o que falta do depósito (ou de onde tiver) e registra
/// as duas pontas no histórico — o cadastro de cada produto e a venda continuam
/// olhando o TOTAL do produto, como sempre.
class EstoquesPage extends StatefulWidget {
  const EstoquesPage({super.key});

  @override
  State<EstoquesPage> createState() => _EstoquesPageState();
}

class _EstoquesPageState extends State<EstoquesPage> {
  final TextEditingController _buscaController = TextEditingController();
  final TextEditingController _qtdController = TextEditingController();

  Produto? _produto;
  String? _origemId;
  String? _destinoId;
  List<Produto> _resultados = [];
  bool _definirComoPadrao = false;
  bool _transferindo = false;

  @override
  void dispose() {
    _buscaController.dispose();
    _qtdController.dispose();
    super.dispose();
  }

  // ==================== CADASTRO DOS ESTOQUES ====================

  Future<void> _abrirFormularioEstoque(Estoque? atual) async {
    final ds = Provider.of<DataService>(context, listen: false);
    final nomeController = TextEditingController(text: atual?.nome ?? '');
    var principal = atual?.principal ?? ds.estoques.isEmpty;

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Text(atual == null ? 'Novo estoque' : 'Editar estoque',
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nomeController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nome do estoque',
                    hintText: 'Ex.: Loja, Depósito, Caminhão',
                    labelStyle: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: principal,
                  onChanged: (v) => setStateDialog(() => principal = v == true),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.tealAccent,
                  title: const Text('É o estoque PRINCIPAL (onde a venda acontece)',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ),
                const Text(
                  'Só um estoque é o principal. É para ele que a mercadoria é trazida '
                  'automaticamente quando a venda precisa de algo que está em outro estoque.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );

    if (salvar != true) return;
    final nome = nomeController.text.trim();
    if (nome.isEmpty) return;

    await ds.salvarEstoque(Estoque(
      id: atual?.id ?? 'estoque_${_uuid.v4().substring(0, 8)}',
      nome: nome,
      principal: principal,
      ordem: atual?.ordem ?? ds.estoques.length,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _excluirEstoque(Estoque e) async {
    final ds = Provider.of<DataService>(context, listen: false);
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Excluir "${e.nome}"?', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'O saldo que estiver neste estoque é transferido para o principal — nada de '
          'mercadoria é perdido. Produtos que tinham este estoque como padrão passam a usar o principal.',
          style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ds.excluirEstoque(e.id);
    if (mounted) setState(() {});
  }

  // ==================== TRANSFERÊNCIA ====================

  void _buscarProduto(String termo) {
    final ds = Provider.of<DataService>(context, listen: false);
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    final achados = <Produto>[];
    for (final p in ds.produtos) {
      if (p.nome.toLowerCase().contains(t) ||
          (p.codigo ?? '').toLowerCase() == t ||
          (p.codigoBarras ?? '').toLowerCase() == t) {
        achados.add(p);
        if (achados.length >= 25) break;
      }
    }
    setState(() => _resultados = achados);
  }

  void _escolherProduto(Produto p) {
    final ds = Provider.of<DataService>(context, listen: false);
    final estoques = ds.estoques;
    setState(() {
      _produto = p;
      _resultados = [];
      _buscaController.text = p.nome;
      _destinoId = estoques.isNotEmpty ? ds.estoquePadraoDe(p) : null;
      // A origem começa no primeiro estoque que NÃO é o destino (com um só
      // estoque não há transferência a fazer — o aviso aparece ao transferir).
      _origemId = estoques.isEmpty
          ? null
          : estoques.firstWhere((e) => e.id != _destinoId,
              orElse: () => estoques.first).id;
      _definirComoPadrao = false;
    });
  }

  Future<void> _transferir() async {
    final ds = Provider.of<DataService>(context, listen: false);
    final produto = _produto;
    final origem = _origemId;
    final destino = _destinoId;
    if (produto == null || origem == null || destino == null) return;

    final quantidade =
        double.tryParse(_qtdController.text.trim().replaceAll(',', '.')) ?? 0;
    setState(() => _transferindo = true);
    try {
      final (ok, msg) = await ds.transferirEstoque(
        produtoId: produto.id,
        deEstoqueId: origem,
        paraEstoqueId: destino,
        quantidade: quantidade,
        usuario: null,
        definirComoPadrao: _definirComoPadrao,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
      ));
      if (ok) {
        setState(() {
          _qtdController.clear();
          _produto = ds.produtos.where((p) => p.id == produto.id).firstOrNull ?? produto;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao transferir: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _transferindo = false);
    }
  }

  // ==================== TELA ====================

  @override
  Widget build(BuildContext context) {
    final ds = Provider.of<DataService>(context);
    final estoques = ds.estoques;
    final principal = ds.estoquePrincipalAtual;

    return Scaffold(
      backgroundColor: const Color(0xFF161621),
      appBar: AppBar(
        title: const Text('Estoques', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormularioEstoque(null),
        icon: const Icon(Icons.add),
        label: const Text('Novo Estoque'),
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const Text(
            'Estoque é o LUGAR onde a mercadoria fica. Cada produto tem um saldo em cada estoque e um '
            'estoque PADRÃO (definido no cadastro dele). A venda continua baixando o total do produto — '
            'a diferença é de onde sai: se não tiver no estoque principal, o app traz do outro e registra '
            'a transferência no histórico.',
            style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 16),

          _titulo('Estoques cadastrados (${estoques.length})'),
          const SizedBox(height: 8),
          if (estoques.isEmpty)
            const Text('Nenhum estoque cadastrado.',
                style: TextStyle(color: Colors.white38, fontSize: 12))
          else
            ...estoques.map((e) => _cardEstoque(ds, e, principal?.id)),
          const SizedBox(height: 20),

          _titulo('Transferir mercadoria'),
          const SizedBox(height: 4),
          const Text(
            'Move a quantidade de um estoque para outro do MESMO produto. O total do produto não muda — '
            'só o lugar onde a mercadoria está. As duas pontas (saída e entrada) ficam no histórico.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 10),
          _campoBuscaProduto(),
          if (_resultados.isNotEmpty) _listaResultados(),
          if (_produto != null) ..._formularioTransferencia(ds),

          const SizedBox(height: 20),
          _titulo('Transferências recentes'),
          const SizedBox(height: 8),
          ..._listaTransferencias(ds),
        ],
      ),
    );
  }

  Widget _titulo(String texto) => Text(
        texto,
        style: const TextStyle(
            color: Colors.tealAccent, fontSize: 15, fontWeight: FontWeight.bold),
      );

  Widget _cardEstoque(DataService ds, Estoque e, String? principalId) {
    final ehPrincipal = e.id == principalId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.tealAccent.withOpacity(ehPrincipal ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colors.tealAccent.withOpacity(ehPrincipal ? 0.45 : 0.15)),
      ),
      child: Row(
        children: [
          Icon(ehPrincipal ? Icons.home_work : Icons.warehouse_outlined,
              color: Colors.tealAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(e.nome,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (ehPrincipal) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('PRINCIPAL — a venda sai daqui',
                            style: TextStyle(color: Colors.tealAccent, fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                Text('id: ${e.id}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          if (!ehPrincipal)
            TextButton(
              onPressed: () async {
                await ds.definirEstoquePrincipal(e.id);
                if (mounted) setState(() {});
              },
              child: const Text('Tornar principal', style: TextStyle(fontSize: 11.5)),
            ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
            tooltip: 'Editar nome',
            onPressed: () => _abrirFormularioEstoque(e),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            tooltip: ehPrincipal
                ? 'O estoque principal não pode ser excluído'
                : 'Excluir (o saldo vai para o principal)',
            onPressed: ehPrincipal ? null : () => _excluirEstoque(e),
          ),
        ],
      ),
    );
  }

  Widget _campoBuscaProduto() {
    return TextField(
      controller: _buscaController,
      style: const TextStyle(color: Colors.white),
      onChanged: _buscarProduto,
      decoration: InputDecoration(
        labelText: 'Produto',
        hintText: 'Digite o nome ou o código',
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: const Icon(Icons.search, color: Colors.white38),
        suffixIcon: _produto == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                onPressed: () => setState(() {
                  _produto = null;
                  _buscaController.clear();
                  _resultados = [];
                }),
              ),
      ),
    );
  }

  Widget _listaResultados() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _resultados.length,
        itemBuilder: (ctx, i) {
          final p = _resultados[i];
          return ListTile(
            dense: true,
            title: Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
              'Total ${p.estoque.toStringAsFixed(2)} ${p.unidade}'
              '${p.codigo != null && p.codigo!.isNotEmpty ? ' • cód ${p.codigo}' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            onTap: () => _escolherProduto(p),
          );
        },
      ),
    );
  }

  List<Widget> _formularioTransferencia(DataService ds) {
    final produto = _produto!;
    final saldos = ds.saldosDoProduto(produto);
    final saldoOrigem = _origemId == null ? 0.0 : ds.saldoNoEstoque(produto, _origemId!);

    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(produto.nome,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              'Total: ${produto.estoque.toStringAsFixed(2)} ${produto.unidade} • '
              'padrão: ${nomeDoEstoque(ds.estoques, ds.estoquePadraoDe(produto))}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                for (final s in saldos)
                  Text('${s.estoque.nome}: ${s.saldo.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: s.saldo > 0 ? Colors.lightGreenAccent : Colors.white38,
                          fontSize: 11.5)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _origemId,
                    dropdownColor: const Color(0xFF1E1E2E),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                        labelText: 'De (origem)',
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 12)),
                    items: [
                      for (final e in ds.estoques)
                        DropdownMenuItem(value: e.id, child: Text(e.nome)),
                    ],
                    onChanged: (v) => setState(() => _origemId = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _destinoId,
                    dropdownColor: const Color(0xFF1E1E2E),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    decoration: const InputDecoration(
                        labelText: 'Para (destino)',
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 12)),
                    items: [
                      for (final e in ds.estoques)
                        DropdownMenuItem(value: e.id, child: Text(e.nome)),
                    ],
                    onChanged: (v) => setState(() => _destinoId = v),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _qtdController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'Qtd.',
                        labelStyle: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ),
              ],
            ),
            if (_origemId != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Disponível em ${nomeDoEstoque(ds.estoques, _origemId)}: ${saldoOrigem.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            CheckboxListTile(
              value: _definirComoPadrao,
              onChanged: (v) => setState(() => _definirComoPadrao = v == true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.tealAccent,
              dense: true,
              title: const Text(
                  'O destino passa a ser o estoque PADRÃO deste produto (onde ele mora)',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _transferindo ? null : _transferir,
                icon: _transferindo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.swap_horiz, size: 18),
                label: Text(_transferindo ? 'Transferindo...' : 'Transferir'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _listaTransferencias(DataService ds) {
    final transferencias = ds.transferenciasRecentes();
    if (transferencias.isEmpty) {
      return const [
        Text('Nenhuma transferência ainda. A venda também gera transferência automática '
            'quando precisa trazer mercadoria de outro estoque.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5)),
      ];
    }
    return [
      for (final t in transferencias)
        _linhaTransferencia(ds, t),
    ];
  }

  Widget _linhaTransferencia(DataService ds, EstoqueHistorico t) {
    final produto = ds.produtos.where((p) => p.id == t.produtoId).firstOrNull;
    final nomeProduto = produto?.nome ?? t.produtoId;
    final automatica = (t.observacao ?? '').contains('automática');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(automatica ? Icons.bolt : Icons.swap_horiz,
              color: automatica ? Colors.amberAccent : Colors.tealAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nomeProduto,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${t.data.day.toString().padLeft(2, '0')}/${t.data.month.toString().padLeft(2, '0')}/'
                  '${t.data.year} ${t.data.hour.toString().padLeft(2, '0')}:${t.data.minute.toString().padLeft(2, '0')}'
                  ' • ${t.quantidade.abs().toStringAsFixed(2)} • ${t.usuario ?? 'sistema'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                ),
                Text(t.observacao ?? '',
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
