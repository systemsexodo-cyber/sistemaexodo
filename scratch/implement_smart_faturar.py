import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Ajustar o TabController para length 4 no initState ---
target_initstate = """  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _popularDadosExistentes();
  }"""

replacement_initstate = """  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _popularDadosExistentes();
  }"""

if target_initstate in content:
    content = content.replace(target_initstate, replacement_initstate)
    print("INITSTATE_TAB_CONTROLLER_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_initstate.replace("\r\n", "\n")
    normalized_replacement = replacement_initstate.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("INITSTATE_TAB_CONTROLLER_CORRIGIDO_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_INITSTATE_TAB_CONTROLLER")


# --- 2. Adicionar campos no construtor de _EmissaoManualPage ---
target_class = """class _EmissaoManualPage extends StatefulWidget {
  final DataService dataService;
  final NFCe? nfeExistente;
  final TextEditingController numeroController;
  final TextEditingController serieController;
  final bool ambienteHomologacao;
  final VoidCallback onEmitida;

  const _EmissaoManualPage({
    required this.dataService,
    this.nfeExistente,
    required this.numeroController,
    required this.serieController,
    required this.ambienteHomologacao,
    required this.onEmitida,
  });"""

replacement_class = """class _EmissaoManualPage extends StatefulWidget {
  final DataService dataService;
  final NFCe? nfeExistente;
  final Map<String, dynamic>? vendaFaturar;
  final Map<String, dynamic>? pedidoFaturar;
  final List<Map<String, dynamic>>? loteFaturar; // Para quando selecionar multiplos e consolidar
  final TextEditingController numeroController;
  final TextEditingController serieController;
  final bool ambienteHomologacao;
  final VoidCallback onEmitida;

  const _EmissaoManualPage({
    required this.dataService,
    this.nfeExistente,
    this.vendaFaturar,
    this.pedidoFaturar,
    this.loteFaturar,
    required this.numeroController,
    required this.serieController,
    required this.ambienteHomologacao,
    required this.onEmitida,
  });"""

if target_class in content:
    content = content.replace(target_class, replacement_class)
    print("CONSTRUTOR_EMISSAO_MANUAL_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_class.replace("\r\n", "\n")
    normalized_replacement = replacement_class.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("CONSTRUTOR_EMISSAO_MANUAL_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_CONSTRUTOR")


# --- 3. Atualizar _popularDadosExistentes para preencher dados de Faturamento ---
target_popular = """  void _popularDadosExistentes() {
    final nfe = widget.nfeExistente;
    if (nfe == null) return;"""

replacement_popular = """  void _popularDadosExistentes() {
    // ─── CASO 1: FATURAR UMA VENDA OU PEDIDO ───
    if (widget.vendaFaturar != null || widget.pedidoFaturar != null || widget.loteFaturar != null) {
      final String? clienteId = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['clienteId'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['clienteId'] : null);
          
      final String? clienteNome = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['cliente'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['cliente'] : null);

      final String? clienteCpfCnpj = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['clienteCpfCnpj'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['clienteCpfCnpj'] : null);

      if (clienteId != null) {
        try {
          _clienteSelecionado = widget.dataService.clientes.firstWhere((c) => c.id == clienteId);
        } catch (_) {}
      }

      _nomeDestCtrl.text = clienteNome ?? 'Consumidor Final';
      _docDestCtrl.text = clienteCpfCnpj ?? '';

      if (_clienteSelecionado != null) {
        _logradouroCtrl.text = _clienteSelecionado!.endereco ?? '';
        _numEndCtrl.text = _clienteSelecionado!.numero ?? '';
        _complCtrl.text = _clienteSelecionado!.complemento ?? '';
        _bairroCtrl.text = _clienteSelecionado!.bairro ?? '';
        _municipioCtrl.text = _clienteSelecionado!.cidade ?? '';
        _ufCtrl.text = _clienteSelecionado!.estado ?? '';
        _cepCtrl.text = _clienteSelecionado!.cep ?? '';
        _emailDestCtrl.text = _clienteSelecionado!.email ?? '';
        _foneCtrl.text = _clienteSelecionado!.telefone;
      }

      // Adicionar itens da venda/pedido
      List<dynamic> itensOriginais = [];
      if (widget.vendaFaturar != null) {
        final idVenda = widget.vendaFaturar!['id'];
        try {
          final v = widget.dataService.vendasBalcao.firstWhere((v) => v.id == idVenda);
          itensOriginais = v.itens;
        } catch (_) {}
      } else if (widget.pedidoFaturar != null) {
        final idPed = widget.pedidoFaturar!['id'];
        try {
          final p = widget.dataService.pedidos.firstWhere((p) => p.id == idPed);
          itensOriginais = p.itens;
        } catch (_) {}
      } else if (widget.loteFaturar != null) {
        // Consolidação em lote
        for (var itemLote in widget.loteFaturar!) {
          final idLote = itemLote['id'];
          if (itemLote['tipo'] == 'Venda') {
            try {
              final v = widget.dataService.vendasBalcao.firstWhere((v) => v.id == idLote);
              itensOriginais.addAll(v.itens);
            } catch (_) {}
          } else {
            try {
              final p = widget.dataService.pedidos.firstWhere((p) => p.id == idLote);
              itensOriginais.addAll(p.itens);
            } catch (_) {}
          }
        }
      }

      // Mapear itens para a listagem da UI
      for (final item in itensOriginais) {
        Produto? prod;
        try {
          prod = widget.dataService.produtos.firstWhere((p) => p.id == item.produtoId);
        } catch (_) {
          prod = Produto(
            id: item.produtoId,
            nome: item.nome,
            preco: item.precoUnitario,
            unidade: 'UN',
            grupo: 'Geral',
            estoque: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            exibirNaLoja: false,
            emDestaque: false,
            fotosUrls: [],
            codigosFornecedor: [],
          );
        }
        
        _itens.add({
          'produto': prod,
          'qtd': item.quantidade,
          'preco': item.precoUnitario,
          'ncm': prod.ncm ?? '00000000',
          'cfop': _cfopCtrl.text,
          'unidade': prod.unidade ?? 'UN',
          'descricao': item.nome,
        });
      }
      return;
    }

    // ─── CASO 2: REEMISSÃO DE NOTA EXISTENTE ───
    final nfe = widget.nfeExistente;
    if (nfe == null) return;"""

if target_popular in content:
    content = content.replace(target_popular, replacement_popular)
    print("POPULAR_DADOS_ATUALIZADO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_target = target_popular.replace("\r\n", "\n")
    normalized_replacement = replacement_popular.replace("\r\n", "\n")
    if normalized_target in normalized_content:
        normalized_content = normalized_content.replace(normalized_target, normalized_replacement)
        content = normalized_content
        print("POPULAR_DADOS_NORMALIZADO")
    else:
        print("FALHA_AO_ATUALIZAR_POPULAR_DADOS")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
