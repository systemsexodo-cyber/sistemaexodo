import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/empresa.dart';
import '../models/produto.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/etiqueta_service.dart';

/// Editor de etiqueta de preço.
///
/// Permite escolher o modelo (tamanho), ajustar margens/fontes, ver o preview
/// no tamanho real da etiqueta e imprimir a quantidade desejada de cópias.
///
/// Os ajustes podem ser guardados como **modelos nomeados** (vários por
/// empresa), além do último uso, que é lembrado automaticamente. Pode receber
/// vários produtos e imprime uma etiqueta por produto, todas com o mesmo
/// layout.
class EditorEtiquetaPage extends StatefulWidget {
  /// Produtos que serão impressos.
  final List<Produto> produtos;

  /// Empresa usada para a impressão, para o rodapé e para salvar o modelo.
  final Empresa? empresa;

  /// Título da AppBar.
  final String? titulo;

  EditorEtiquetaPage({
    super.key,
    required Produto produto,
    this.empresa,
    this.titulo,
  }) : produtos = [produto];

  /// Várias etiquetas de uma vez (ex.: produtos selecionados na lista).
  EditorEtiquetaPage.lote({
    super.key,
    required this.produtos,
    this.empresa,
    this.titulo,
  });

  @override
  State<EditorEtiquetaPage> createState() => _EditorEtiquetaPageState();
}

class _EditorEtiquetaPageState extends State<EditorEtiquetaPage> {
  static const double _larguraMin = 25;
  static const double _larguraMax = 110;
  static const double _alturaMin = 15;
  static const double _alturaMax = 90;
  static const double _margemMin = 1;
  static const double _margemMax = 15;
  static const double _fonteMin = 5;
  static const double _fonteMax = 20;

  final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  late EtiquetaConfig _config;
  bool _imprimindo = false;

  /// Modelos nomeados salvos desta empresa.
  List<EtiquetaModelo> _modelos = [];

  /// Nome do modelo carregado agora (para destacar o chip selecionado).
  String? _modeloAtivo;

  Produto get _produto => widget.produtos.first;

  int get _totalEtiquetas => widget.produtos.length * _config.quantidade;

  bool get _ehLote => widget.produtos.length > 1;

  @override
  void initState() {
    super.initState();
    _config = _configPadrao();
    _carregarConfigSalva();
    _carregarModelos();
  }

  EtiquetaConfig _configPadrao() {
    // Produto a granel (kg/g/l/ml) ganha a etiqueta maior por padrão, porque
    // precisa mostrar também a unidade de venda.
    return _produto.vendaFracionada
        ? EtiquetaTamanho.grande.configuracaoPadrao
        : EtiquetaTamanho.precoPadrao.configuracaoPadrao;
  }

  Future<void> _carregarConfigSalva() async {
    final empresa = widget.empresa;
    if (empresa == null) return;

    final salva = await EtiquetaConfigStorage.carregar(empresa.id);
    if (salva == null || !mounted) return;
    setState(() => _config = salva);
  }

  /// Empresa usada para salvar/ler modelos: prioriza a sessão (AuthService) e
  /// os dados carregados (DataService), caindo para a empresa da página.
  Empresa? _empresaDosModelos() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    return authService.empresaAtual ??
        dataService.empresaAtual ??
        widget.empresa;
  }

  Future<void> _carregarModelos() async {
    final empresa = _empresaDosModelos();
    if (empresa == null) return;

    // Fonte da verdade: configurações da empresa (banco local + nuvem).
    final modelosSalvos = EtiquetaModeloStorage.ler(empresa.configuracoes);
    // Empresa nunca gravou por aqui: tenta o espelho local (legado).
    final List<EtiquetaModelo> modelos =
        modelosSalvos ?? await EtiquetaModeloStorage.listarLocal(empresa.id);
    if (!mounted) return;
    setState(() => _modelos = modelos);
  }

  /// Grava a lista de modelos nas configurações da empresa (banco) e
  /// atualiza AuthService + DataService para o resto do app enxergar.
  Future<bool> _persistirModelos(List<EtiquetaModelo> modelos) async {
    final empresa = _empresaDosModelos();
    if (empresa == null) return false;

    final novaConfig = EtiquetaModeloStorage.gravar(
      empresa.configuracoes,
      modelos,
    );
    final atualizada = empresa.copyWith(configuracoes: novaConfig);

    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    try {
      await authService.atualizarEmpresa(atualizada);
    } catch (e) {
      debugPrint('>>> [EditorEtiqueta] Falha ao salvar no banco: $e');
    }
    dataService.setEmpresaAtual(atualizada);
    await EtiquetaModeloStorage.espelharLocal(empresa.id, modelos);
    return true;
  }

  /// Pede um nome e guarda o layout atual como modelo reutilizável.
  Future<void> _salvarModelo() async {
    final empresa = widget.empresa;
    if (empresa == null) {
      _avisar('Abra uma empresa antes de salvar modelos de etiqueta.');
      return;
    }

    final erro = _validar();
    if (erro != null) {
      _avisar(erro);
      return;
    }

    final sugerido =
        '${_config.larguramm.toStringAsFixed(0)} × '
        '${_config.alturamm.toStringAsFixed(0)} mm';

    // Nada de TextEditingController aqui: ele só poderia ser descartado quando
    // o diálogo já saiu da tela, mas o `await showDialog` retorna antes de a
    // animação de saída terminar. Descartar ali faz o TextField em animação
    // usar um controlador morto ("A TextEditingController was used after being
    // disposed"), o que corrompe o Overlay e derruba os Tooltips em cascata.
    // Com initialValue + onChanged o texto vive só dentro do diálogo.
    var digitado = sugerido;

    final nome = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salvar modelo'),
        content: TextFormField(
          initialValue: sugerido,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nome do modelo',
            hintText: 'Ex.: 50 × 30 mm prateleira',
          ),
          onChanged: (valor) => digitado = valor,
          onFieldSubmitted: (valor) => Navigator.pop(dialogContext, valor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, digitado),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    final nomeLimpo = nome?.trim();
    if (nomeLimpo == null || nomeLimpo.isEmpty || !mounted) return;

    // Substitui um modelo com o mesmo nome ou adiciona um novo.
    final modelosAtualizados = List<EtiquetaModelo>.from(_modelos);
    final indiceExistente = modelosAtualizados.indexWhere(
      (modelo) => modelo.nome.toLowerCase() == nomeLimpo.toLowerCase(),
    );
    final novoModelo = EtiquetaModelo(nome: nomeLimpo, config: _config);
    if (indiceExistente >= 0) {
      modelosAtualizados[indiceExistente] = novoModelo;
    } else {
      modelosAtualizados.add(novoModelo);
    }
    await _persistirModelos(modelosAtualizados);
    await _carregarModelos();
    if (!mounted) return;
    setState(() => _modeloAtivo = nomeLimpo);
    _avisar('Modelo "$nomeLimpo" salvo.', sucesso: true);
  }

  /// Carrega o layout de um modelo salvo.
  void _aplicarModelo(EtiquetaModelo modelo) {
    setState(() {
      _config = modelo.config.copyWith(quantidade: _config.quantidade);
      _modeloAtivo = modelo.nome;
    });
    _avisar('Modelo "${modelo.nome}" carregado.', sucesso: true);
  }

  Future<void> _removerModelo(EtiquetaModelo modelo) async {
    final empresa = widget.empresa;
    if (empresa == null) return;

    final confirma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Apagar "${modelo.nome}"?'),
        content: const Text('O modelo salvo será removido deste terminal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirma != true || !mounted) return;

    final modelosAtualizados = _modelos
        .where((item) => item.nome != modelo.nome)
        .toList();
    await _persistirModelos(modelosAtualizados);
    await _carregarModelos();
    if (!mounted) return;
    setState(() {
      if (_modeloAtivo == modelo.nome) _modeloAtivo = null;
    });
  }

  String? _validar() {
    if (_config.larguramm <= 0 || _config.alturamm <= 0) {
      return 'Largura e altura devem ser maiores que zero';
    }
    if (_config.larguramm - _config.margemEsqmm - _config.margemDirmm <= 5) {
      return 'As margens laterais não deixam espaço útil na etiqueta';
    }
    if (_config.alturamm - (_config.margemVmm * 2) <= 5) {
      return 'As margens superior/inferior não deixam espaço útil na etiqueta';
    }
    return null;
  }

  Future<void> _imprimir() async {
    final empresa = widget.empresa;
    if (empresa == null) {
      _avisar('Abra uma empresa antes de imprimir etiquetas.');
      return;
    }

    final erro = _validar();
    if (erro != null) {
      _avisar(erro);
      return;
    }

    setState(() => _imprimindo = true);
    try {
      // Lembra o modelo para as próximas impressões desta empresa.
      await EtiquetaConfigStorage.salvar(empresa.id, _config);

      await EtiquetaService.imprimirEtiquetas(
        context: context,
        produtos: widget.produtos,
        config: _config,
        empresa: empresa,
      );
      if (!mounted) return;
      _avisar(
        _totalEtiquetas == 1
            ? 'Etiqueta enviada para impressão.'
            : '$_totalEtiquetas etiquetas enviadas para impressão.',
        sucesso: true,
      );
    } catch (e) {
      if (!mounted) return;
      _avisar('Erro ao imprimir a etiqueta: $e');
    } finally {
      if (mounted) setState(() => _imprimindo = false);
    }
  }

  void _avisar(String mensagem, {bool sucesso = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: sucesso ? Colors.green.shade700 : null,
      ),
    );
  }

  void _aplicarTamanho(EtiquetaTamanho tamanho) {
    setState(() {
      _config = tamanho.configuracaoPadrao.copyWith(
        quantidade: _config.quantidade,
      );
      _modeloAtivo = null;
    });
  }

  /// Qualquer ajuste manual desmarca o modelo carregado, porque o layout
  /// deixa de ser exatamente o que foi salvo.
  void _configAlterada(EtiquetaConfig nova) {
    setState(() {
      _config = nova;
      _modeloAtivo = null;
    });
  }

  void _alterarQuantidade(int delta) {
    // Só muda o nº de cópias: o layout continua sendo o do modelo carregado.
    final nova = (_config.quantidade + delta).clamp(1, 99);
    setState(() => _config = _config.copyWith(quantidade: nova));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cs = tema.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.titulo ??
              (_ehLote
                  ? 'Etiquetas • ${widget.produtos.length} produtos'
                  : 'Etiqueta • ${_produto.nome}'),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Desktop: a etiqueta fica num painel fixo à direita, então dá
            // para ver o resultado enquanto se mexem nos ajustes.
            if (constraints.maxWidth >= 900) return _layoutDuasColunas(cs);
            // Celular/tablet: a etiqueta fica presa no topo e só os ajustes
            // rolam — ela nunca sai da tela.
            return _layoutColunaUnica(cs, constraints.maxHeight);
          },
        ),
      ),
    );
  }

  /// Controles à esquerda (rolam) + etiqueta e botão de imprimir fixos.
  Widget _layoutDuasColunas(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 24),
            children: [
              _secaoModelos(cs),
              const SizedBox(height: 16),
              _secaoModelosSalvos(cs),
              const SizedBox(height: 16),
              _secaoAjustes(cs),
            ],
          ),
        ),
        VerticalDivider(
          width: 1,
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
        SizedBox(
          width: 380,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _cartaoProduto(cs),
                        const SizedBox(height: 12),
                        _secaoPreview(cs, alturaMaxima: 320),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _botaoImprimir(cs),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Produto + etiqueta presos no topo; ajustes rolam embaixo.
  Widget _layoutColunaUnica(ColorScheme cs, double alturaTela) {
    // Em telas baixas a etiqueta encolhe para sobrar espaço aos ajustes.
    final alturaPreview = (alturaTela * 0.26).clamp(90.0, 170.0).toDouble();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              _cartaoProduto(cs),
              const SizedBox(height: 10),
              _secaoPreview(cs, alturaMaxima: alturaPreview),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              _secaoModelos(cs),
              const SizedBox(height: 12),
              _secaoModelosSalvos(cs),
              const SizedBox(height: 12),
              _secaoAjustes(cs),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _botaoImprimir(cs),
        ),
      ],
    );
  }

  Widget _botaoImprimir(ColorScheme cs) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _imprimindo ? null : _imprimir,
        icon: _imprimindo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.print_rounded),
        label: Text(
          _imprimindo
              ? 'ENVIANDO…'
              : (_totalEtiquetas == 1
                    ? 'IMPRIMIR ETIQUETA'
                    : 'IMPRIMIR $_totalEtiquetas ETIQUETAS'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Escala (px por mm) que faz a etiqueta caber no espaço reservado a ela:
  /// vale o menor entre a largura disponível e a altura máxima do painel.
  double _escalaPreview(double larguraDisponivel, double alturaDisponivel) {
    final porLargura = larguraDisponivel / _config.larguramm;
    final porAltura = alturaDisponivel / _config.alturamm;
    final escala = porLargura < porAltura ? porLargura : porAltura;
    return escala.clamp(0.8, 6.0).toDouble();
  }

  Widget _cartao({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _tituloSecao(String texto, ColorScheme cs) {
    return Text(
      texto,
      style: TextStyle(
        color: cs.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _cartaoProduto(ColorScheme cs) {
    final produto = _produto;
    final codigo = (produto.codigo ?? '').replaceAll('COD-', '');

    return _cartao(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _ehLote
                  ? '${widget.produtos.length}'
                  : (codigo.isEmpty ? '?' : codigo),
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                fontSize: _ehLote ? 18 : 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ehLote
                      ? '${widget.produtos.length} produtos selecionados'
                      : produto.nome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _ehLote
                      ? 'Todos com este layout • 1º: ${produto.nome}'
                      : 'Preço: ${_moeda.format(produto.precoAtual)}'
                            '${produto.promocaoAtiva && produto.precoAtual < produto.preco ? ' (promoção)' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoModelos(ColorScheme cs) {
    return _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSecao('Modelo da etiqueta', cs),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tamanho in EtiquetaTamanho.todos)
                ChoiceChip(
                  label: Text(tamanho.rotulo),
                  selected:
                      _config.larguramm == tamanho.larguramm &&
                      _config.alturamm == tamanho.alturamm,
                  onSelected: (_) => _aplicarTamanho(tamanho),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Modelos nomeados guardados pelo operador: toque para carregar, apague
  /// o que não usa mais e salve o layout atual com um nome.
  Widget _secaoModelosSalvos(ColorScheme cs) {
    return _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _tituloSecao('Modelos salvos', cs)),
              TextButton.icon(
                onPressed: widget.empresa == null ? null : _salvarModelo,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Salvar'),
              ),
            ],
          ),
          if (widget.empresa == null)
            Text(
              'Abra uma empresa para salvar e usar modelos.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else if (_modelos.isEmpty)
            Text(
              'Nenhum modelo salvo ainda. Ajuste a etiqueta e toque em '
              'Salvar para reutilizar este layout depois.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            )
          else ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final modelo in _modelos)
                  InputChip(
                    label: Text(modelo.nome),
                    selected: _modeloAtivo == modelo.nome,
                    avatar: Icon(
                      Icons.bookmark_outline,
                      size: 16,
                      color: _modeloAtivo == modelo.nome
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    onSelected: (_) => _aplicarModelo(modelo),
                    onDeleted: () => _removerModelo(modelo),
                    deleteButtonTooltipMessage: 'Apagar modelo',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _modeloAtivo == null
                  ? 'Toque em um modelo para carregar o layout dele.'
                  : 'Usando o modelo "$_modeloAtivo".',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _secaoAjustes(ColorScheme cs) {
    return _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSecao('Ajustes finos', cs),
          const SizedBox(height: 8),
          _slider(
            cs,
            rotulo: 'Largura',
            valor: _config.larguramm,
            min: _larguraMin,
            max: _larguraMax,
            passo: 1,
            onChanged: (v) => _configAlterada(_config.copyWith(larguramm: v)),
          ),
          _slider(
            cs,
            rotulo: 'Altura',
            valor: _config.alturamm,
            min: _alturaMin,
            max: _alturaMax,
            passo: 1,
            onChanged: (v) => _configAlterada(_config.copyWith(alturamm: v)),
          ),
          _slider(
            cs,
            rotulo: 'Margem esquerda',
            valor: _config.margemEsqmm,
            min: _margemMin,
            max: _margemMax,
            passo: 1,
            onChanged: (v) => _configAlterada(_config.copyWith(margemEsqmm: v)),
          ),
          _slider(
            cs,
            rotulo: 'Margem direita',
            valor: _config.margemDirmm,
            min: _margemMin,
            max: _margemMax,
            passo: 1,
            onChanged: (v) => _configAlterada(_config.copyWith(margemDirmm: v)),
          ),
          _slider(
            cs,
            rotulo: 'Margem superior/inferior',
            valor: _config.margemVmm,
            min: _margemMin,
            max: _margemMax,
            passo: 1,
            onChanged: (v) => _configAlterada(_config.copyWith(margemVmm: v)),
          ),
          _slider(
            cs,
            rotulo: 'Fonte do nome',
            valor: _config.fonteTitulo,
            min: _fonteMin,
            max: _fonteMax,
            passo: 1,
            sufixo: 'pt',
            onChanged: (v) => _configAlterada(_config.copyWith(fonteTitulo: v)),
          ),
          _slider(
            cs,
            rotulo: 'Fonte dos detalhes',
            valor: _config.fonteCorpo,
            min: _fonteMin,
            max: _fonteMax,
            passo: 1,
            sufixo: 'pt',
            onChanged: (v) => _configAlterada(_config.copyWith(fonteCorpo: v)),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cópias por produto',
                      style: TextStyle(color: cs.onSurface, fontSize: 13),
                    ),
                    if (_ehLote)
                      Text(
                        'Total: $_totalEtiquetas etiquetas',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Menos uma',
                onPressed: _config.quantidade > 1
                    ? () => _alterarQuantidade(-1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${_config.quantidade}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Mais uma',
                onPressed: _config.quantidade < 99
                    ? () => _alterarQuantidade(1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider(
    ColorScheme cs, {
    required String rotulo,
    required double valor,
    required double min,
    required double max,
    required double passo,
    required ValueChanged<double> onChanged,
    String sufixo = 'mm',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                rotulo,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Text(
              '${valor.toStringAsFixed(1)} $sufixo',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: valor.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: ((max - min) / passo).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _secaoPreview(ColorScheme cs, {double? alturaMaxima}) {
    return _cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSecao('Pré-visualização', cs),
          if (_ehLote) ...[
            const SizedBox(height: 2),
            Text(
              'Usando o 1º produto como referência',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final escala = _escalaPreview(
                constraints.maxWidth,
                alturaMaxima ?? 320,
              );
              return Center(child: _previewEtiqueta(escala));
            },
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '${_config.larguramm.toStringAsFixed(0)} × '
              '${_config.alturamm.toStringAsFixed(0)} mm  •  '
              '$_totalEtiquetas etiqueta(s)',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewEtiqueta(double escala) {
    final produto = _produto;
    final preco = produto.precoAtual;
    final temPromocao = produto.promocaoAtiva && preco < produto.preco;
    final unidade = produto.unidadeVenda.trim();
    final nomeEmpresa = widget.empresa?.nomeExibicao.trim();
    final codigo = EtiquetaService.codigoDeBarras(produto);

    // 1 pt = 0,3528 mm; converte para px do preview na escala atual.
    double px(double pt) => pt * 0.3528 * escala;

    final precoTexto = produto.vendaFracionada && unidade.isNotEmpty
        ? '${_moeda.format(preco)} / $unidade'
        : _moeda.format(preco);

    final alturaCodigo =
        ((_config.alturamm - _config.margemVmm * 2) * 0.28).clamp(3.0, 10.0) *
        escala;
    final larguraCodigo =
        (_config.larguramm - _config.margemEsqmm - _config.margemDirmm) *
        escala;

    return Container(
      width: _config.larguramm * escala,
      height: _config.alturamm * escala,
      padding: EdgeInsets.symmetric(
        horizontal: _config.margemEsqmm * escala,
        vertical: _config.margemVmm * escala,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black26),
      ),
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                produto.nome.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: px(_config.fonteTitulo),
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              if (temPromocao)
                Text(
                  'de ${_moeda.format(produto.preco)}',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: px(_config.fonteCorpo - 2),
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                precoTexto,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: px(_config.fonteCorpo * 2),
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              if (codigo != null)
                SizedBox(
                  width: larguraCodigo,
                  height: alturaCodigo,
                  child: CustomPaint(
                    painter: _BarcodePainter(
                      simbolo: codigo.simbolo,
                      dados: codigo.dados,
                    ),
                  ),
                ),
              if (codigo != null)
                Text(
                  codigo.dados,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: px(_config.fonteCorpo - 2),
                  ),
                ),
              if (nomeEmpresa != null && nomeEmpresa.isNotEmpty)
                Text(
                  nomeEmpresa,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: px(_config.fonteCorpo - 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desenha no preview o mesmo símbolo que vai para o PDF.
class _BarcodePainter extends CustomPainter {
  final Barcode simbolo;
  final String dados;

  _BarcodePainter({required this.simbolo, required this.dados});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || dados.isEmpty) return;

    final tinta = Paint()..color = Colors.black;
    final elementos = simbolo.make(
      dados,
      width: size.width,
      height: size.height,
      drawText: false,
    );

    for (final elemento in elementos) {
      if (elemento is! BarcodeBar || !elemento.black) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          elemento.left,
          elemento.top,
          elemento.width,
          elemento.height,
        ),
        tinta,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter anterior) =>
      anterior.dados != dados || anterior.simbolo != simbolo;
}
