import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../custom_app_bar.dart';

/// Inventário de conferência da loja.
///
/// O usuário percorre os produtos (por grupo), digita a quantidade contada
/// fisicamente e o sistema compara com o estoque atual: OK (verde), faltando
/// (vermelho) ou sobrando (laranja). Ao finalizar, os ajustes são aplicados
/// automaticamente no estoque com registro no histórico (motivo 'inventario').
///
/// Conveniências de contagem:
///  * ENTER no campo salta para a linha de baixo (próximo produto), para
///    contar em sequência sem tirar a mão do teclado;
///  * as contagens são GRAVADAS sozinhas (SharedPreferences, por empresa),
///    então dá para sair da tela e voltar depois sem perder o que já foi
///    contado. O rascunho só é apagado quando o inventário é aplicado.
class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  String? _grupoFiltro;
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();
  // produtoId -> quantidade contada (null = ainda não conferido)
  final Map<String, double> _contagens = {};
  final Map<String, TextEditingController> _controllers = {};
  // produtoId -> foco do campo, para o ENTER saltar para a linha de baixo
  final Map<String, FocusNode> _focos = {};
  bool _finalizando = false;

  // Rascunho: chave por empresa, para o mesmo PC não misturar contagens de
  // lojas diferentes. Iniciada em [didChangeDependencies] (a empresa já está
  // carregada) e daí as contagens são gravadas automaticamente.
  String? _chaveRascunho;
  bool _rascunhoIniciado = false;
  Timer? _timerRascunho;
  DateTime? _rascunhoSalvoEm;

  @override
  void dispose() {
    _timerRascunho?.cancel();
    // Última gravação: garante que o que foi digitado neste último instante
    // também vá para o rascunho (o widget já não vai mais dar feedback).
    _gravarRascunho(imediato: true);
    _buscaController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rascunhoIniciado) return;
    _rascunhoIniciado = true;
    final empresaId =
        Provider.of<DataService>(context, listen: false).empresaAtual?.id;
    _chaveRascunho =
        'inventario_rascunho${empresaId == null ? '' : '_$empresaId'}';
    _carregarRascunho();
  }

  FocusNode _focoPara(String produtoId) =>
      _focos.putIfAbsent(produtoId, () => FocusNode());

  String _formatarContagem(double valor) =>
      valor.toStringAsFixed(2).replaceAll('.', ',');

  /// ENTER no campo: confere a linha e salta para a de baixo, para contar em
  /// sequência sem tirar a mão do teclado. No fim da lista solta o foco.
  void _focarLinhaSeguinte(List<Produto> lista, int index) {
    final alvo = index + 1;
    if (alvo >= lista.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    final id = lista[alvo].id;
    final foco = _focos[id];
    final contexto = foco?.context;
    if (foco == null || contexto == null) {
      // Linha de baixo ainda fora da área construída da lista: deixa a ordem
      // de foco do Flutter resolver (na prática ela já está visível).
      FocusScope.of(context).nextFocus();
      return;
    }

    // Só rola quando a linha não está TODA visível: garantir visibilidade o
    // tempo todo faria a lista pular a cada ENTER.
    final linha = contexto.findRenderObject();
    final listaBox =
        Scrollable.maybeOf(contexto)?.context.findRenderObject();
    if (linha is RenderBox &&
        linha.hasSize &&
        listaBox is RenderBox &&
        listaBox.hasSize) {
      final topo = linha.localToGlobal(Offset.zero, ancestor: listaBox).dy;
      final base = topo + linha.size.height;
      if (topo < 0 || base > listaBox.size.height) {
        Scrollable.ensureVisible(contexto,
            duration: Duration.zero, alignment: 0.1);
      }
    }

    foco.requestFocus();
    final c = _controllers[id];
    if (c != null && c.text.isNotEmpty) {
      // Seleciona o que já estiver escrito: o próximo número digitado
      // substitui em vez de entrar no meio do valor antigo.
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
  }

  /// Carrega o rascunho salvo (se houver) e repõe as contagens.
  Future<void> _carregarRascunho() async {
    final chave = _chaveRascunho;
    if (chave == null) return;
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(chave);
    if (bruto == null || bruto.isEmpty || !mounted) return;
    try {
      final mapa = jsonDecode(bruto) as Map<String, dynamic>;
      final recuperadas = <String, double>{};
      mapa.forEach((produtoId, valor) {
        final contagem =
            valor is num ? valor.toDouble() : double.tryParse('$valor');
        if (contagem != null) recuperadas[produtoId] = contagem;
      });
      if (recuperadas.isEmpty) return;
      setState(() => _contagens.addAll(recuperadas));
      // Linhas já construídas ganham o texto salvo (as demais leem na criação).
      _controllers.forEach((produtoId, c) {
        final contagem = _contagens[produtoId];
        if (contagem != null && c.text.isEmpty) {
          c.text = _formatarContagem(contagem);
        }
      });
      setState(() => _rascunhoSalvoEm = DateTime.now());
    } catch (_) {
      // Rascunho corrompido: ignora e segue sem ele.
    }
  }

  /// Grava as contagens para dar "continuar depois". Passo a passo (digitação)
  /// usa um debounce; com `imediato` grava na hora (ex.: ao sair da tela).
  Future<void> _gravarRascunho({bool imediato = false}) async {
    final chave = _chaveRascunho;
    if (chave == null) return;
    if (!imediato) {
      _timerRascunho?.cancel();
      _timerRascunho = Timer(const Duration(milliseconds: 600), () {
        _gravarRascunho(imediato: true);
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (_contagens.isEmpty) {
      await prefs.remove(chave);
      if (mounted) setState(() => _rascunhoSalvoEm = null);
      return;
    }
    await prefs.setString(chave, jsonEncode(_contagens));
    if (mounted) setState(() => _rascunhoSalvoEm = DateTime.now());
  }

  /// Apaga o rascunho: usado quando o inventário é aplicado.
  Future<void> _limparRascunho() async {
    final chave = _chaveRascunho;
    if (chave == null) return;
    _timerRascunho?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(chave);
    if (mounted) setState(() => _rascunhoSalvoEm = null);
  }

  TextEditingController _controllerPara(String produtoId, double estoqueAtual) {
    return _controllers.putIfAbsent(produtoId, () {
      // Linha criada depois de o rascunho ter sido carregado já nasce preenchida.
      final contagemSalva = _contagens[produtoId];
      final c = TextEditingController(
        text: contagemSalva == null ? '' : _formatarContagem(contagemSalva),
      );
      // Ao tocar no produto, já sugere o estoque do sistema como ponto de partida
      c.addListener(() {
        final texto = c.text.trim().replaceAll(',', '.');
        if (texto.isEmpty) {
          _contagens.remove(produtoId);
        } else {
          _contagens[produtoId] = double.tryParse(texto) ?? 0;
        }
        setState(() {});
        // Rascunho: cada tecla agenda a gravação (debounce) para dar
        // "gravar e continuar depois" sem um botão a esquecer de apertar.
        _gravarRascunho();
      });
      return c;
    });
  }

  /// Marca como conferido com a quantidade exata do sistema (atalho rápido)
  void _copiarSistema(Produto p) {
    final c = _controllerPara(p.id, p.estoque);
    c.text = _formatarContagem(p.estoque);
  }

  Future<void> _finalizarInventario(List<Produto> produtos) async {
    if (_contagens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confira pelo menos um produto antes de finalizar.'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    final naoConferidos = produtos.where((p) => !_contagens.containsKey(p.id)).length;
    final finalizar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Finalizar Inventário?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text(
          '${_contagens.length} produto(s) conferido(s)'
          '${naoConferidos > 0 ? ' • $naoConferidos ainda sem contagem (ficarão como estão)' : ''}.\n\n'
          'As diferenças serão aplicadas no estoque e registradas no histórico como ajuste de inventário.\n\n'
          'O inventário inteiro fica num lote do Histórico de ajustes (no Ajuste Geral) e pode ser DESFEITO.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            label: const Text('APLICAR AJUSTES'),
          ),
        ],
      ),
    );
    if (finalizar != true || !mounted) return;

    setState(() => _finalizando = true);
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual?.nome ?? authService.usuarioAtual?.email;

    final resumo = await dataService.aplicarInventario(
      Map<String, double>.from(_contagens),
      usuario: usuario,
    );
    // Lote criado pelo inventário — permite desfazer tudo de uma vez.
    final loteId = dataService.ultimoAjusteLote?.id;

    if (!mounted) return;
    setState(() {
      _finalizando = false;
      _contagens.clear();
      for (final c in _controllers.values) {
        c.text = '';
      }
    });
    // Aplicado: o rascunho deixa de fazer sentido.
    await _limparRascunho();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '✓ Inventário aplicado: ${resumo['conferidos']} conferidos • '
          '${resumo['faltas']} faltando • ${resumo['sobras']} sobrando • '
          '${resumo['zerados'] ?? 0} zerado(s) • '
          '${resumo['ajustados']} ajustados'
          '${loteId != null ? ' • lote $loteId' : ''}',
        ),
        backgroundColor: Colors.tealAccent,
        duration: const Duration(seconds: 8),
        action: loteId == null
            ? null
            : SnackBarAction(
                label: 'DESFAZER',
                textColor: Colors.black,
                onPressed: () async {
                  try {
                    final estorno = await dataService.desfazerAjusteEstoqueLote(
                      loteId,
                      usuario: usuario,
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '↩️ Inventário desfeito: ${estorno['estoquesRevertidos'] ?? 0} estoque(s) restaurados'
                          '${(estorno['ignorados'] ?? 0) > 0 ? ' • ${estorno['ignorados']} ignorado(s)' : ''}.',
                        ),
                        backgroundColor: Colors.greenAccent,
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Erro ao desfazer inventário: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final produtos = service.produtos;

    final grupos = produtos.map((p) => p.grupo).where((g) => g.isNotEmpty).toSet().toList()..sort();

    List<Produto> filtrados = produtos.where((p) {
      if (_grupoFiltro != null && p.grupo != _grupoFiltro) return false;
      if (_busca.isNotEmpty) {
        final q = _busca.toLowerCase();
        if (!p.nome.toLowerCase().contains(q) &&
            !(p.codigo?.toLowerCase().contains(q) ?? false) &&
            !(p.codigoBarras?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList();
    filtrados.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    final conferidos = _contagens.length;
    // Contagem 0 = ZERAMENTO (mostrado à parte, não é falta nem sobra).
    final zerando = filtrados.where((p) => _contagens.containsKey(p.id) && _contagens[p.id] == 0 && p.estoque.abs() > 0.0005).length;
    final faltas = filtrados.where((p) => _contagens.containsKey(p.id) && _contagens[p.id]! < p.estoque - 0.0005 && _contagens[p.id] != 0).length;
    final sobras = filtrados.where((p) => _contagens.containsKey(p.id) && _contagens[p.id]! > p.estoque + 0.0005 && _contagens[p.id] != 0).length;

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Inventário da Loja',
          actions: [
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.tealAccent),
              tooltip: 'Finalizar Inventário',
              onPressed: _finalizando ? null : () => _finalizarInventario(filtrados),
            ),
          ],
        ),
        body: Column(
          children: [
            // Resumo
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _chipResumo('CONFERIDOS', conferidos, Colors.tealAccent),
                  const SizedBox(width: 8),
                  _chipResumo('FALTANDO', faltas, Colors.redAccent),
                  const SizedBox(width: 8),
                  _chipResumo('SOBRANDO', sobras, Colors.orangeAccent),
                  const SizedBox(width: 8),
                  _chipResumo('ZERANDO', zerando, Colors.amberAccent),
                ],
              ),
            ),
            // Filtros
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Buscar produto, código ou barras...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => _busca = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String?>(
                    icon: Icon(Icons.category, color: _grupoFiltro != null ? Colors.purpleAccent : Colors.white60, size: 22),
                    tooltip: 'Filtrar por Grupo',
                    color: const Color(0xFF1A1A2E),
                    onSelected: (v) => setState(() => _grupoFiltro = v),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: null, child: Text('Todos os Grupos', style: TextStyle(color: Colors.white))),
                      ...grupos.map((g) => PopupMenuItem(value: g, child: Text(g, style: const TextStyle(color: Colors.white)))),
                    ],
                  ),
                ],
              ),
            ),
            // Instrução
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white.withOpacity(0.35), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Digite a quantidade contada e tecle ENTER para ir para a linha de baixo. Tocar no produto copia o estoque do sistema. Verde = OK, vermelho = falta, laranja = sobrou.',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            // Rascunho gravado: dá para sair e continuar depois.
            if (_rascunhoSalvoEm != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.save_rounded, color: Colors.tealAccent.withOpacity(0.65), size: 12),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Rascunho gravado às '
                        '${_rascunhoSalvoEm!.hour.toString().padLeft(2, '0')}:'
                        '${_rascunhoSalvoEm!.minute.toString().padLeft(2, '0')} — '
                        'pode sair e voltar depois que as contagens continuam.',
                        style: TextStyle(color: Colors.tealAccent.withOpacity(0.65), fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(child: Text('Nenhum produto neste filtro', style: TextStyle(color: Colors.white24)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrados.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) => _buildItemInventario(filtrados, index),
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _finalizando ? null : () => _finalizarInventario(filtrados),
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.black,
          icon: _finalizando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.check_circle_outline),
          label: Text(_finalizando ? 'Aplicando...' : 'Finalizar Inventário (${conferidos})'),
        ),
      ),
    );
  }

  Widget _chipResumo(String label, int valor, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: cor.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Text('$valor', style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: cor.withOpacity(0.6), fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemInventario(List<Produto> lista, int index) {
    final p = lista[index];
    final sistema = p.estoque;
    final contado = _contagens[p.id];
    final controller = _controllerPara(p.id, sistema);
    final custo = p.precoCusto ?? 0.0;

    Color? corStatus;
    String? textoStatus;
    if (contado != null) {
      if ((contado - sistema).abs() < 0.0005) {
        corStatus = Colors.greenAccent;
        textoStatus = 'Confere';
      } else if (contado == 0) {
        // Contou 0: o saldo será ZERADO (não é falta nem sobra).
        corStatus = Colors.amberAccent;
        textoStatus = 'ZERAR → 0';
      } else if (contado < sistema) {
        corStatus = Colors.redAccent;
        textoStatus = '−${(sistema - contado).toStringAsFixed(2)}';
      } else {
        corStatus = Colors.orangeAccent;
        textoStatus = '+${(contado - sistema).toStringAsFixed(2)}';
      }
    }

    return Material(
      color: corStatus != null ? corStatus.withOpacity(0.07) : Colors.white.withOpacity(0.03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _copiarSistema(p),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: corStatus != null ? corStatus.withOpacity(0.35) : Colors.white.withOpacity(0.04)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      'Sistema: ${sistema.toStringAsFixed(2)} ${p.unidade}'
                      '${custo > 0 ? ' • Custo: R\$ ${custo.toStringAsFixed(2)}' : ''}',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                    if (contado != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        textoStatus!,
                        style: TextStyle(color: corStatus, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: controller,
                  focusNode: _focoPara(p.id),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _focarLinhaSeguinte(lista, index),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: corStatus ?? Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'contado',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: corStatus != null
                          ? BorderSide(color: corStatus.withOpacity(0.6))
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
