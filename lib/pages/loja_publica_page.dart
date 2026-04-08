import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/carrinho_item.dart';
import 'package:sistema_exodo_novo/models/variacao_produto.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/frete_service.dart';
import 'package:sistema_exodo_novo/models/opcao_frete.dart';
import 'package:sistema_exodo_novo/models/zona_entrega.dart';
import 'package:sistema_exodo_novo/widgets/loja/produto_card.dart';
import 'package:sistema_exodo_novo/widgets/loja/banner_carrossel.dart';
import 'package:sistema_exodo_novo/widgets/loja/categoria_filtro.dart';
import 'package:sistema_exodo_novo/widgets/loja/carrinho_drawer.dart';
import 'package:sistema_exodo_novo/pages/loja_checkout_page.dart';
import 'package:sistema_exodo_novo/pages/cliente_login_page.dart';
import 'package:sistema_exodo_novo/pages/cliente_cadastro_page.dart';
import 'package:intl/intl.dart';

class LojaPublicaPage extends StatefulWidget {
  final String? codigoLink; // Código do link do vendedor (ex: ABC123)

  const LojaPublicaPage({super.key, this.codigoLink});

  @override
  State<LojaPublicaPage> createState() => _LojaPublicaPageState();
}

class _LojaPublicaStyle {
  static const primaryColor = Color(0xFF6366F1); // Indigo
  static const secondaryColor = Color(0xFF8B5CF6); // Violet
  static const accentColor = Color(0xFF10B981); // Emerald
  static const backgroundColor = Color(0xFF0F172A); // Slate 900
  static const cardColor = Color(0xFF1E293B); // Slate 800
  static const textColor = Color(0xFFF8FAFC); // Slate 50
  static const textSecondaryColor = Color(0xFF94A3B8); // Slate 400
}

class _LojaPublicaPageState extends State<LojaPublicaPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  LinkVendedor? _linkVendedor;
  String _abaSelecionada = 'produtos'; // Removido 'servicos'
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  String? _categoriaSelecionada;
  bool _mostrarApenasPromocoes = false;
  // Filtro de preço removido
  final ScrollController _scrollController = ScrollController();
  bool _mostrarHeader = true;
  bool _isDark = true; // Tema Premium padrão é escuro
  
  // Carrossel de banners
  final PageController _bannerPageController = PageController();
  Timer? _bannerTimer;
  int _bannerIndexAtual = 0;
  OpcaoFrete? _freteSelecionadoProduto;
  String? _modoLojaOverride; // Para teste em tempo real

  @override
  void initState() {
    super.initState();
    _carregarLinkVendedor();
    _scrollController.addListener(_onScroll);
    // Iniciar carrossel após o primeiro frame para garantir que o PageController está pronto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _iniciarCarrosselBanners();
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _buscaController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _iniciarCarrosselBanners() {
    // Cancelar timer anterior se existir
    _bannerTimer?.cancel();
    
    // Trocar banner a cada 4 segundos (mais rápido para melhor visualização)
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && _bannerPageController.hasClients) {
        final configEcommerce = _obterConfigEcommerce();
        final banners = _obterBanners(configEcommerce);
        if (banners.length > 1) {
          setState(() {
            _bannerIndexAtual = (_bannerIndexAtual + 1) % banners.length;
          });
          _bannerPageController.animateToPage(
            _bannerIndexAtual,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          );
        } else if (banners.length == 1) {
          // Se houver apenas 1 banner, garantir que está na página 0
          if (_bannerIndexAtual != 0) {
            setState(() {
              _bannerIndexAtual = 0;
            });
            _bannerPageController.jumpToPage(0);
          }
        }
      }
    });
  }

  List<Map<String, dynamic>> _obterBanners(Map<String, dynamic>? configEcommerce) {
    final banners = <Map<String, dynamic>>[];
    
    // Banner principal
    final bannerUrl = configEcommerce?['bannerUrl'] as String?;
    final textoBanner = configEcommerce?['textoBanner'] as String? ?? '';
    if (bannerUrl != null && bannerUrl.isNotEmpty) {
      banners.add({
        'url': bannerUrl,
        'texto': textoBanner,
        'link': configEcommerce?['linkBanner'] as String?,
      });
    }
    
    // Banners promocionais (imagens) - priorizar URLs de imagem
    final bannerPromocional1Url = configEcommerce?['bannerPromocional1Url'] as String?;
    final bannerPromocional2Url = configEcommerce?['bannerPromocional2Url'] as String?;
    final bannerPromocional3Url = configEcommerce?['bannerPromocional3Url'] as String?;
    
    if (bannerPromocional1Url != null && bannerPromocional1Url.isNotEmpty) {
      banners.add({
        'url': bannerPromocional1Url,
        'texto': configEcommerce?['textoPromocional1'] as String? ?? '',
        'tipo': 'promocional',
        'numero': 1,
      });
    }
    if (bannerPromocional2Url != null && bannerPromocional2Url.isNotEmpty) {
      banners.add({
        'url': bannerPromocional2Url,
        'texto': configEcommerce?['textoPromocional2'] as String? ?? '',
        'tipo': 'promocional',
        'numero': 2,
      });
    }
    if (bannerPromocional3Url != null && bannerPromocional3Url.isNotEmpty) {
      banners.add({
        'url': bannerPromocional3Url,
        'texto': configEcommerce?['textoPromocional3'] as String? ?? '',
        'tipo': 'promocional',
        'numero': 3,
      });
    }
    
    // Fallback: Se não houver URLs de imagem, usar textos (compatibilidade)
    if (bannerPromocional1Url == null || bannerPromocional1Url.isEmpty) {
      final textoPromocional1 = configEcommerce?['textoPromocional1'] as String? ?? '';
      if (textoPromocional1.isNotEmpty) {
        banners.add({
          'texto': textoPromocional1,
          'tipo': 'promocional_texto',
          'cor': Colors.orange,
        });
      }
    }
    if (bannerPromocional2Url == null || bannerPromocional2Url.isEmpty) {
      final textoPromocional2 = configEcommerce?['textoPromocional2'] as String? ?? '';
      if (textoPromocional2.isNotEmpty) {
        banners.add({
          'texto': textoPromocional2,
          'tipo': 'promocional_texto',
          'cor': Colors.green,
        });
      }
    }
    if (bannerPromocional3Url == null || bannerPromocional3Url.isEmpty) {
      final textoPromocional3 = configEcommerce?['textoPromocional3'] as String? ?? '';
      if (textoPromocional3.isNotEmpty) {
        banners.add({
          'texto': textoPromocional3,
          'tipo': 'promocional_texto',
          'cor': Colors.blue,
        });
      }
    }
    
    return banners;
  }

  void _onScroll() {
    final posicaoAtual = _scrollController.offset;
    
    // Esconde o header quando desce mais de 50px
    if (posicaoAtual > 50 && _mostrarHeader) {
      setState(() {
        _mostrarHeader = false;
      });
    }
    // Mostra o header quando sobe ou está no topo
    else if (posicaoAtual <= 50 && !_mostrarHeader) {
      setState(() {
        _mostrarHeader = true;
      });
    }
  }

  // Método para obter o tamanho da imagem automaticamente
  Future<Size> _obterTamanhoImagem(String imageUrl) async {
    try {
      final imageProvider = NetworkImage(imageUrl);
      final completer = Completer<Size>();
      
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      
      listener = ImageStreamListener((ImageInfo info, bool _) {
        completer.complete(Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ));
        imageStream.removeListener(listener);
      }, onError: (exception, stackTrace) {
        completer.complete(const Size(120, 120)); // Tamanho padrão em caso de erro
        imageStream.removeListener(listener);
      });
      
      imageStream.addListener(listener);
      
      return completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const Size(120, 120), // Tamanho padrão se timeout
      );
    } catch (e) {
      return const Size(120, 120); // Tamanho padrão em caso de erro
    }
  }

  Future<void> _carregarLinkVendedor() async {
    if (widget.codigoLink == null) return;

    final dataService = Provider.of<DataService>(context, listen: false);
    final links = dataService.linksVendedores;
    final link = links.firstWhere(
      (l) => l.codigoLink == widget.codigoLink && l.ativo,
      orElse: () => LinkVendedor(
        id: '',
        funcionarioId: '',
        funcionarioNome: '',
        codigoLink: '',
        urlCompleta: '',
      ),
    );

    if (link.id.isNotEmpty) {
      setState(() {
        _linkVendedor = link;
      });
    }
  }

  /// Verifica se cliente está logado e navega para checkout
  Future<void> _irParaCheckout() async {
    final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
    
    // Verificar se cliente está logado
    if (!clienteAuthService.isAuthenticated) {
      // Mostrar diálogo para login
      final resultado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Login Necessário'),
          content: const Text('Você precisa estar logado para finalizar a compra. Deseja fazer login agora?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Fazer Login'),
            ),
          ],
        ),
      );

      if (resultado == true) {
        // Navegar para login
        final loginSucesso = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const ClienteLoginPage(),
          ),
        );

        // Se login foi bem-sucedido, continuar para checkout
        if (loginSucesso == true && clienteAuthService.isAuthenticated) {
          _navegarParaCheckout();
        }
      }
    } else {
      // Cliente já está logado, ir direto para checkout
      _navegarParaCheckout();
    }
  }

  /// Navega para a página de checkout
  void _navegarParaCheckout() {
    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LojaCheckoutPage(
          linkVendedor: _linkVendedor,
          opcaoFreteInicial: _freteSelecionadoProduto,
        ),
      ),
    ).then((_) {
      // Opcional: Limpar carrinho após compra se desejar
      // carrinhoService.limparCarrinho();
    });
  }


  // Métodos de gerenciamento local do carrinho removidos (agora no CarrinhoService)

  
  // Adiciona produto ao carrinho, verificando se tem variações
  void _adicionarProdutoAoCarrinho(Produto produto) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    
    if (produto.temVariacoes && produto.variacoes.isNotEmpty) {
      // Produto tem variações - mostrar diálogo de seleção
      _mostrarDialogSelecaoVariacoes(produto, formatoMoeda);
    } else {
      // Produto sem variações - adicionar diretamente
      carrinhoService.adicionarProduto(produto);
      
      // Feedback visual
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${produto.nome} adicionado ao carrinho'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'VER CARRINHO',
            textColor: Colors.white,
            onPressed: () => _mostrarCarrinhoDrawer(formatoMoeda),
          ),
        ),
      );
    }
  }

  
  // Mostra diálogo para selecionar variações do produto
  void _mostrarDialogSelecaoVariacoes(Produto produto, NumberFormat formatoMoeda) {
    // Agrupar variações por atributo (Tamanho, Cor, Sabor, etc.)
    final Map<String, List<VariacaoProduto>> variacoesPorAtributo = {};
    for (var variacao in produto.variacoes.where((v) => v.ativo)) {
      if (!variacoesPorAtributo.containsKey(variacao.nomeAtributo)) {
        variacoesPorAtributo[variacao.nomeAtributo] = [];
      }
      variacoesPorAtributo[variacao.nomeAtributo]!.add(variacao);
    }
    
    // Estado para armazenar seleções
    Map<String, VariacaoProduto?> selecoes = {};
    for (var atributo in variacoesPorAtributo.keys) {
      selecoes[atributo] = null;
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Icon(
                Icons.tune,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Selecione as Opções',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produto.nome,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 20),
                ...variacoesPorAtributo.entries.map((entry) {
                  final nomeAtributo = entry.key;
                  final opcoes = entry.value;
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeAtributo,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: opcoes.map((variacao) {
                          final isSelected = selecoes[nomeAtributo]?.id == variacao.id;
                          final temEstoque = variacao.estoque > 0;
                          
                          return InkWell(
                            onTap: temEstoque
                                ? () {
                                    setDialogState(() {
                                      selecoes[nomeAtributo] = isSelected ? null : variacao;
                                    });
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (Theme.of(context).colorScheme.primary)
                                    : (temEstoque ? Colors.grey[100] : Colors.grey[200]),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : (temEstoque ? Colors.grey[300]! : Colors.grey[400]!),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Exibir círculo colorido se for variação de cor
                                      if (nomeAtributo.toLowerCase().contains('cor') || nomeAtributo.toLowerCase().contains('color')) ...[
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: _corFromString(variacao.valor) ?? Colors.grey,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.white
                                                  : (temEstoque ? Colors.grey[400]! : Colors.grey[500]!),
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        variacao.valor,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? Colors.white
                                              : (temEstoque ? Colors.grey[800] : Colors.grey[500]),
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (variacao.precoAdicional != null && variacao.precoAdicional != 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        variacao.precoAdicional! > 0
                                            ? '+ ${formatoMoeda.format(variacao.precoAdicional!)}'
                                            : '${formatoMoeda.format(variacao.precoAdicional!)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? Colors.white70
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  if (!temEstoque)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Indisponível',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.red[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                // Verificar se todas as variações obrigatórias foram selecionadas
                final variacoesSelecionadas = selecoes.values
                    .where((v) => v != null)
                    .cast<VariacaoProduto>()
                    .toList();
                
                if (variacoesSelecionadas.isEmpty && produto.temVariacoes) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione pelo menos uma opção'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                
                // Adicionar ao carrinho com as variações selecionadas
                Navigator.pop(context);
                // Adicionar ao carrinho com as variações selecionadas
                Navigator.pop(context);
                final item = CarrinhoItem.fromProduto(
                  produto,
                  variacoesSelecionadas: variacoesSelecionadas.isNotEmpty
                      ? variacoesSelecionadas
                      : null,
                );
                
                Provider.of<CarrinhoService>(context, listen: false).adicionarProduto(
                  produto,
                  variacoes: variacoesSelecionadas.isNotEmpty 
                      ? variacoesSelecionadas
                      : null,
                );
                
                // Feedback visual
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${produto.nome} adicionado ao carrinho'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: const Text('Adicionar ao Carrinho'),
            ),
          ],
        ),
      ),
    );
  }

  List<Produto> _filtrarProdutos(List<Produto> produtos) {
    // Debug: log total de produtos recebidos
    debugPrint('>>> [Loja] ========================================');
    debugPrint('>>> [Loja] FILTRANDO PRODUTOS PARA E-COMMERCE');
    debugPrint('>>> [Loja] Total de produtos recebidos: ${produtos.length}');
    
    // Debug: Listar TODOS os produtos e seus valores de exibirNaLoja
    int produtosComExibirNaLoja = 0;
    int produtosComEstoque = 0;
    for (var p in produtos) {
      if (p.exibirNaLoja) produtosComExibirNaLoja++;
      if (p.estoqueTotal > 0) produtosComEstoque++;
      debugPrint('>>> [Loja] Produto: "${p.nome}" | exibirNaLoja: ${p.exibirNaLoja} (tipo: ${p.exibirNaLoja.runtimeType}) | estoque: ${p.estoque} | estoqueTotal: ${p.estoqueTotal}');
    }
    debugPrint('>>> [Loja] RESUMO: $produtosComExibirNaLoja produtos com exibirNaLoja=true, $produtosComEstoque com estoque > 0');
    
    // Filtrar produtos que devem ser exibidos na loja
    // Incluir produtos com exibirNaLoja=true (mesmo com estoque zero)
    var filtrados = produtos.where((p) {
      final estoqueTotal = p.estoqueTotal;
      final exibirNaLoja = p.exibirNaLoja;
      
      // DEBUG DETALHADO: Verificar tipo e valor
      debugPrint('>>> [Loja] Verificando "${p.nome}":');
      debugPrint('>>> [Loja]   exibirNaLoja = $exibirNaLoja (tipo: ${exibirNaLoja.runtimeType})');
      debugPrint('>>> [Loja]   exibirNaLoja == true? ${exibirNaLoja == true}');
      debugPrint('>>> [Loja]   estoqueTotal = $estoqueTotal');
      
      // Verificar se deve exibir
      final deveExibir = exibirNaLoja == true; // Verificação explícita
      
      if (deveExibir) {
        if (estoqueTotal > 0) {
          debugPrint('>>> [Loja] ✅ "${p.nome}" SERÁ EXIBIDO (exibirNaLoja=$exibirNaLoja, estoque=$estoqueTotal) - DISPONÍVEL');
        } else {
          debugPrint('>>> [Loja] ✅ "${p.nome}" SERÁ EXIBIDO (exibirNaLoja=$exibirNaLoja, estoque=$estoqueTotal) - SEM ESTOQUE');
        }
        return true;
      }
      
      debugPrint('>>> [Loja] ✗ "${p.nome}" NÃO aparece: exibirNaLoja=$exibirNaLoja (tipo: ${exibirNaLoja.runtimeType})');
      return false;
    }).toList();
    
    debugPrint('>>> [Loja] Total de produtos filtrados: ${filtrados.length}');
    if (filtrados.isEmpty) {
      debugPrint('>>> [Loja] ⚠️⚠️⚠️ NENHUM PRODUTO SERÁ EXIBIDO! ⚠️⚠️⚠️');
      debugPrint('>>> [Loja] Verifique:');
      debugPrint('>>> [Loja]   1. Produtos têm exibirNaLoja=true?');
      debugPrint('>>> [Loja]   2. Produtos têm estoque > 0?');
    } else {
      debugPrint('>>> [Loja] Produtos que serão exibidos:');
      for (var p in filtrados) {
        debugPrint('>>> [Loja]   - "${p.nome}" (exibirNaLoja: ${p.exibirNaLoja}, estoque: ${p.estoqueTotal})');
      }
    }
    debugPrint('>>> [Loja] ========================================');

    // Filtro de busca inteligente e precisa
    if (_termoBusca.isNotEmpty) {
      final termo = _termoBusca.trim();
      if (termo.isEmpty) {
        return filtrados;
      }
      
      final termoLower = termo.toLowerCase();
      final termoSemAcentos = _removerAcentos(termoLower);
      final ehNumero = RegExp(r'^[0-9]+$').hasMatch(termo);
      
      // Se for número, permite busca com 1 caractere
      // Se for texto, mínimo 2 caracteres
      if (!ehNumero && termo.length < 2) {
        return filtrados;
      }
      
      // Separar termo em palavras para busca mais precisa
      final palavrasTermo = termoLower.split(RegExp(r'\s+')).where((p) => p.length >= 2).toList();
      
      filtrados = filtrados.where((p) {
        final nomeLower = p.nome.toLowerCase();
        final nomeSemAcentos = _removerAcentos(nomeLower);
        final descricaoLower = (p.descricao ?? '').toLowerCase();
        final descricaoSemAcentos = _removerAcentos(descricaoLower);
        final codigoLower = (p.codigo ?? '').toLowerCase();
        final grupoLower = p.grupo.toLowerCase();
        final grupoSemAcentos = _removerAcentos(grupoLower);
        
        // 1. BUSCA POR CÓDIGO EXATO (se for número)
        if (ehNumero && p.codigo != null) {
          final numCodigo = p.codigo!.replaceAll(RegExp(r'[^0-9]'), '');
          if (numCodigo == termo) {
            return true; // Match exato no código
          }
          // Também verifica se o código contém o número
          if (numCodigo.contains(termo) || codigoLower.contains(termoLower)) {
            return true;
          }
        }
        
        // 2. BUSCA POR CÓDIGO (texto ou número)
        if (codigoLower.contains(termoLower) || codigoLower.startsWith(termoLower)) {
          return true;
        }
        
        // 3. BUSCA EXATA NO NOME (prioridade máxima)
        if (nomeLower == termoLower || nomeSemAcentos == termoSemAcentos) {
          return true;
        }
        
        // 4. NOME COMEÇA COM O TERMO (alta prioridade)
        if (nomeLower.startsWith(termoLower) || nomeSemAcentos.startsWith(termoSemAcentos)) {
          return true;
        }
        
        // 5. BUSCA POR MÚLTIPLAS PALAVRAS NO NOME
        if (palavrasTermo.isNotEmpty) {
          final palavrasNome = nomeLower.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
          final todasPalavrasEncontradas = palavrasTermo.every((palavra) {
            final palavraSemAcento = _removerAcentos(palavra);
            return palavrasNome.any((pn) {
              final pnSemAcento = _removerAcentos(pn);
              return pn.startsWith(palavra) || 
                     pnSemAcento.startsWith(palavraSemAcento) ||
                     pn.contains(palavra) ||
                     pnSemAcento.contains(palavraSemAcento);
            });
          });
          if (todasPalavrasEncontradas) {
            return true;
          }
        }
        
        // 6. NOME CONTÉM O TERMO (com ou sem acentos)
        if (nomeLower.contains(termoLower) || nomeSemAcentos.contains(termoSemAcentos)) {
          return true;
        }
        
        // 7. DESCRIÇÃO CONTÉM O TERMO (com ou sem acentos)
        if (descricaoLower.isNotEmpty) {
          if (descricaoLower.contains(termoLower) || descricaoSemAcentos.contains(termoSemAcentos)) {
            return true;
          }
        }
        
        // 8. GRUPO/CATEGORIA CONTÉM O TERMO
        if (grupoLower.contains(termoLower) || grupoSemAcentos.contains(termoSemAcentos)) {
          return true;
        }
        
        return false;
      }).toList();
      
      // Ordenar por relevância: matches exatos primeiro, depois por início, depois por contém
      filtrados.sort((a, b) {
        final termoLower = _termoBusca.toLowerCase().trim();
        final termoSemAcentos = _removerAcentos(termoLower);
        
        final aNome = a.nome.toLowerCase();
        final aNomeSemAcentos = _removerAcentos(aNome);
        final bNome = b.nome.toLowerCase();
        final bNomeSemAcentos = _removerAcentos(bNome);
        
        // Prioridade 1: Nome exato
        final aExato = aNome == termoLower || aNomeSemAcentos == termoSemAcentos;
        final bExato = bNome == termoLower || bNomeSemAcentos == termoSemAcentos;
        if (aExato && !bExato) return -1;
        if (!aExato && bExato) return 1;
        
        // Prioridade 2: Nome começa com o termo
        final aComeca = aNome.startsWith(termoLower) || aNomeSemAcentos.startsWith(termoSemAcentos);
        final bComeca = bNome.startsWith(termoLower) || bNomeSemAcentos.startsWith(termoSemAcentos);
        if (aComeca && !bComeca) return -1;
        if (!aComeca && bComeca) return 1;
        
        // Prioridade 3: Código exato (se for número)
        if (ehNumero) {
          final aCodigo = a.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final bCodigo = b.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          if (aCodigo == termo && bCodigo != termo) return -1;
          if (aCodigo != termo && bCodigo == termo) return 1;
        }
        
        // Prioridade 4: Ordenar alfabeticamente
        return aNome.compareTo(bNome);
      });
    }

    // Filtro de categoria
    if (_categoriaSelecionada != null) {
      filtrados = filtrados.where((p) => p.grupo == _categoriaSelecionada).toList();
    }

    // Filtro de promoções
    if (_mostrarApenasPromocoes) {
      filtrados = filtrados.where((p) => p.promocaoAtiva).toList();
    }

    // Filtro por preço removido

    return filtrados;
  }

  // Métodos de serviços removidos - serviços não são mais exibidos no e-commerce

  List<String> _obterCategorias(List<Produto> produtos) {
    final categorias = produtos.map((p) => p.grupo).toSet().toList();
    categorias.sort();
    return categorias;
  }

  // Função auxiliar para remover acentos (busca inteligente)
  String _removerAcentos(String texto) {
    const acentos = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c',
      'Á': 'A', 'À': 'A', 'Ã': 'A', 'Â': 'A', 'Ä': 'A',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
      'Ó': 'O', 'Ò': 'O', 'Õ': 'O', 'Ô': 'O', 'Ö': 'O',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'Ç': 'C',
    };
    
    String resultado = texto;
    acentos.forEach((acento, semAcento) {
      resultado = resultado.replaceAll(acento, semAcento);
    });
    return resultado;
  }

  Map<String, dynamic>? _obterConfigEcommerce() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    if (empresa == null) {
      debugPrint('>>> [LojaPublica] Empresa é null');
      return null;
    }
    
    if (empresa.configuracoes == null) {
      debugPrint('>>> [LojaPublica] Configurações são null');
      return null;
    }
    
    final ecommerce = empresa.configuracoes!['ecommerce'] as Map<String, dynamic>?;
    debugPrint('>>> [LojaPublica] Configurações de e-commerce: ${ecommerce != null ? "presente" : "null"}');
    if (ecommerce != null) {
      debugPrint('>>> [LojaPublica] ecommerce keys: ${ecommerce.keys.toList()}');
      debugPrint('>>> [LojaPublica] logoUrl: ${ecommerce['logoUrl']}');
      debugPrint('>>> [LojaPublica] bannerUrl: ${ecommerce['bannerUrl']}');
    }
    
    return ecommerce;
  }

  bool _bannerDeveSerExibido() {
    final config = _obterConfigEcommerce();
    if (config == null) return false;
    
    final bannerAtivo = config['bannerAtivo'] as bool? ?? false;
    if (!bannerAtivo) return false;
    
    final agora = DateTime.now();
    final dataInicio = config['bannerDataInicio'] != null
        ? DateTime.parse(config['bannerDataInicio'])
        : null;
    final dataFim = config['bannerDataFim'] != null
        ? DateTime.parse(config['bannerDataFim'])
        : null;
    
    if (dataInicio != null && agora.isBefore(dataInicio)) return false;
    if (dataFim != null && agora.isAfter(dataFim)) return false;
    
    return config['bannerUrl'] != null && (config['bannerUrl'] as String).isNotEmpty;
  }

  Color _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.green;
    try {
      return Color(int.parse(hex.replaceFirst('#', ''), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.green;
    }
  }

  /// Converte um nome de cor ou código hex em uma cor Flutter
  Color? _corFromString(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    
    // Tenta converter código hex primeiro
    if (valor.startsWith('#') || RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(valor)) {
      return _hexToColor(valor);
    }
    
    // Mapeamento de nomes de cores comuns
    final coresMap = {
      'azul': Colors.blue,
      'blue': Colors.blue,
      'vermelho': Colors.red,
      'red': Colors.red,
      'verde': Colors.green,
      'green': Colors.green,
      'amarelo': Colors.yellow,
      'yellow': Colors.yellow,
      'laranja': Colors.orange,
      'orange': Colors.orange,
      'roxo': Colors.purple,
      'purple': Colors.purple,
      'rosa': Colors.pink,
      'pink': Colors.pink,
      'preto': Colors.black,
      'black': Colors.black,
      'branco': Colors.white,
      'white': Colors.white,
      'cinza': Colors.grey,
      'grey': Colors.grey,
      'gray': Colors.grey,
      'marrom': Colors.brown,
      'brown': Colors.brown,
      'ciano': Colors.cyan,
      'cyan': Colors.cyan,
      'indigo': Colors.indigo,
      'teal': Colors.teal,
      'lima': Colors.lime,
      'lime': Colors.lime,
      'dourado': const Color(0xFFFFD700),
      'gold': const Color(0xFFFFD700),
      'prata': const Color(0xFFC0C0C0),
      'silver': const Color(0xFFC0C0C0),
    };
    
    final valorLower = valor.toLowerCase().trim();
    return coresMap[valorLower];
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: true); // Escutar mudanças no DataService
    final authService = Provider.of<AuthService>(context, listen: true); // Escutar mudanças no AuthService
    
    // DEBUG: Verificar produtos ANTES do filtro
    debugPrint('>>> [Loja] ========================================');
    debugPrint('>>> [Loja] BUILD - ANTES DO FILTRO');
    debugPrint('>>> [Loja] Total de produtos no DataService: ${dataService.produtos.length}');
    for (var p in dataService.produtos) {
      debugPrint('>>> [Loja]   - "${p.nome}": exibirNaLoja=${p.exibirNaLoja}, estoque=${p.estoque}, estoqueTotal=${p.estoqueTotal}');
    }
    debugPrint('>>> [Loja] ========================================');
    
    final produtos = _filtrarProdutos(dataService.produtos);
    // Serviços removidos do e-commerce
    final categorias = _obterCategorias(dataService.produtos.where((p) => p.estoque > 0).toList());
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final empresa = authService.empresaAtual;
    final configEcommerce = _obterConfigEcommerce();
    final logoUrl = configEcommerce?['logoUrl'] as String? ?? empresa?.logoUrl;
    final bannerUrl = configEcommerce?['bannerUrl'] as String?;
    final textoBanner = configEcommerce?['textoBanner'] as String? ?? '';
    final linkBanner = configEcommerce?['linkBanner'] as String?;
    final corBanner = _hexToColor(configEcommerce?['corBanner'] as String?);
    final corTextoBanner = _hexToColor(configEcommerce?['corTextoBanner'] as String?);
    final textoPromocional1 = configEcommerce?['textoPromocional1'] as String? ?? '';
    final textoPromocional2 = configEcommerce?['textoPromocional2'] as String? ?? '';
    final textoPromocional3 = configEcommerce?['textoPromocional3'] as String? ?? '';
    final descontoPixAtivo = configEcommerce?['descontoPixAtivo'] as bool? ?? true;
    final percentualDescontoPix = (configEcommerce?['percentualDescontoPix'] as num?)?.toDouble() ?? 5.0;
    
    // Configurações de frete grátis
    final valorMinimoFreteGratis = (configEcommerce?['valorFreteGratis'] as num?)?.toDouble() ?? 399.90;
    final bannerFreteGratisAtivo = configEcommerce?['bannerFreteGratisAtivo'] as bool? ?? true;
    final textoBannerFreteGratis = configEcommerce?['textoBannerFreteGratis'] as String? ?? 'Frete Grátis acima de R\$ {valor}';
    final posicaoBannerFreteGratis = configEcommerce?['posicaoBannerFreteGratis'] as String? ?? 'topo';
    
    // Calcular total do carrinho
    final totalCarrinho = Provider.of<CarrinhoService>(context, listen: false).valorTotal;
    final deveExibirBannerFreteGratis = bannerFreteGratisAtivo && totalCarrinho > 0 && totalCarrinho < valorMinimoFreteGratis;
    final faltaParaFreteGratis = valorMinimoFreteGratis - totalCarrinho;
    
    final configModo = configEcommerce?['modoExibicao'] as String? ?? 'ecommerce';
    final modoLoja = _modoLojaOverride ?? configModo;
    
    // Personalizações visuais
    final corPrimariaLoja = _hexToColor(configEcommerce?['corPrimariaLoja'] as String?);
    final corSecundariaLoja = _hexToColor(configEcommerce?['corSecundariaLoja'] as String?);
    
    // Cores Premium - Baseadas no Tema e nas Cores da Empresa
    final primaryColor = _isDark ? _LojaPublicaStyle.primaryColor : (corPrimariaLoja ?? _LojaPublicaStyle.primaryColor);
    final secondaryColor = _isDark ? _LojaPublicaStyle.secondaryColor : (corSecundariaLoja ?? _LojaPublicaStyle.secondaryColor);
    final cardColor = _isDark ? _LojaPublicaStyle.cardColor : Colors.white;
    final textColor = _isDark ? _LojaPublicaStyle.textColor : const Color(0xFF1E293B);
    final textSecondaryColor = _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.black54;

    final temaPersonalizado = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        primary: corPrimariaLoja ?? Theme.of(context).colorScheme.primary,
        secondary: corSecundariaLoja ?? Theme.of(context).colorScheme.secondary,
      ),
    );

    // Design moderno e limpo
    return Theme(
      data: temaPersonalizado,
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: CarrinhoDrawer(
          formatoMoeda: formatoMoeda,
          corPrimaria: primaryColor,
          onCheckout: _irParaCheckout,
        ),
        body: Stack(
          children: [
            // Background Decor (Premium)
            _buildAnimatedBackground(primaryColor, secondaryColor),
            
            Column(
              children: [
                // Header Flutuante (Premium Glassmorphism)
                _buildHeaderPremium(
                  logoUrl: logoUrl,
                  empresaNome: empresa?.nomeExibicao ?? 'Loja',
                  primaryColor: primaryColor,
                  cardColor: cardColor,
                  textColor: textColor,
                  configEcommerce: configEcommerce,
                ),
                
                // Lista de Produtos
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Column(
                      children: [
                        // Banners Premium (Apenas no E-commerce por padrão)
                        if (_bannerDeveSerExibido() && modoLoja == 'ecommerce')
                          _buildBannersPremium(configEcommerce, primaryColor),
                        
                        // Busca e Filtros Premium
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildBuscaEFiltrosPremium(
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            textColor: textColor,
                            textSecondaryColor: textSecondaryColor,
                            categorias: categorias,
                          ),
                        ),
                        
                        // Grid ou Lista Dependendo do Modo
                        if (modoLoja == 'delivery')
                          _buildListaProdutosDelivery(
                            produtos: produtos,
                            formatoMoeda: formatoMoeda,
                            descontoPixAtivo: descontoPixAtivo,
                            percentualDescontoPix: percentualDescontoPix,
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            textColor: textColor,
                          )
                        else
                          _buildGridProdutosPremium(
                            produtos: produtos,
                            formatoMoeda: formatoMoeda,
                            descontoPixAtivo: descontoPixAtivo,
                            percentualDescontoPix: percentualDescontoPix,
                            primaryColor: primaryColor,
                            cardColor: cardColor,
                            textColor: textColor,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground(Color primaryColor, Color secondaryColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F172A), // Slate 900
            const Color(0xFF1E293B), // Slate 800
            primaryColor.withOpacity(0.2),
            secondaryColor.withOpacity(0.1),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -150,
            right: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryColor.withOpacity(0.3), // Mais opacidade
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    secondaryColor.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPremium({
    required String? logoUrl,
    required String empresaNome,
    required Color primaryColor,
    required Color cardColor,
    required Color textColor,
    required Map<String, dynamic>? configEcommerce,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: _mostrarHeader ? null : 0,
      child: _mostrarHeader ? ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.8),
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: Row(
              children: [
                if (logoUrl != null)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(image: NetworkImage(logoUrl), fit: BoxFit.cover),
                    ),
                  )
                else
                  Icon(Icons.store, color: primaryColor, size: 32),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    empresaNome,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ),

                // Botão de Troca de Tema
                IconButton(
                  icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode, color: primaryColor),
                  onPressed: () => setState(() => _isDark = !_isDark),
                ),
                
                // Carrinho Badge
                _buildCarrinhoBadge(primaryColor),
              ],
            ),
          ),
        ),
      ) : const SizedBox.shrink(),
    );
  }

  Widget _buildCarrinhoBadge(Color primaryColor) {
    return Consumer<CarrinhoService>(
      builder: (context, carrinho, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.shopping_bag_outlined, color: primaryColor),
              onPressed: () {
                if (carrinho.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carrinho vazio')));
                } else {
                  _mostrarCarrinhoDrawer(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$'));
                }
              },
            ),
            if (!carrinho.isEmpty)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text(
                    '${carrinho.totalItens}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBannersPremium(Map<String, dynamic>? config, Color primaryColor) {
    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: BannerCarrossel(
        banners: _obterBanners(config),
        controller: _bannerPageController,
        currentIndex: _bannerIndexAtual,
        onPageChanged: (index) {
          if (mounted) {
            setState(() => _bannerIndexAtual = index);
          }
        },
        corTextoBanner: Colors.white,
      ),
    );
  }

  Widget _buildBuscaEFiltrosPremium({
    required Color primaryColor,
    required Color cardColor,
    required Color textColor,
    required Color textSecondaryColor,
    required List<String> categorias,
  }) {
    return Column(
      children: [
        // Barra de Busca Glassmorphism
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                controller: _buscaController,
                style: TextStyle(color: textColor),
                onChanged: (v) => setState(() => _termoBusca = v),
                decoration: InputDecoration(
                  hintText: 'O que você está procurando?',
                  hintStyle: TextStyle(color: textSecondaryColor),
                  prefixIcon: Icon(Icons.search, color: primaryColor),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
        ),
        
        // Filtros de Categoria Premium (Horizontal Scroll)
        CategoriaFiltro(
          categorias: categorias,
          categoriaSelecionada: _categoriaSelecionada,
          mostrarApenasPromocoes: _mostrarApenasPromocoes,
          corPrimaria: primaryColor,
          onCategoriaSelected: (cat) => setState(() => _categoriaSelecionada = cat),
          onPromocoesToggled: () => setState(() => _mostrarApenasPromocoes = !_mostrarApenasPromocoes),
        ),
      ],
    );
  }

  Widget _buildGridProdutosPremium({
    required List<Produto> produtos,
    required NumberFormat formatoMoeda,
    required bool descontoPixAtivo,
    required double percentualDescontoPix,
    required Color primaryColor,
    required Color cardColor,
    required Color textColor,
  }) {
    if (produtos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 60, color: primaryColor.withOpacity(0.5)),
              const SizedBox(height: 20),
              Text('Nenhum produto encontrado', style: TextStyle(color: textColor, fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.65, // Ajustado para não cortar o botão
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: produtos.length,
        itemBuilder: (context, index) {
          final produto = produtos[index];
          return ProdutoCard(
            produto: produto,
            formatoMoeda: formatoMoeda,
            descontoPixAtivo: descontoPixAtivo,
            percentualDescontoPix: percentualDescontoPix,
            corPrimaria: primaryColor,
            onAddToCart: _adicionarProdutoAoCarrinho,
            onShowDetails: (p) => _mostrarDetalhesProduto(context, p, formatoMoeda, primaryColor, cardColor, textColor),
          );
        },
      ),
    );
  }

  Widget _buildListaProdutosDelivery({
    required List<Produto> produtos,
    required NumberFormat formatoMoeda,
    required bool descontoPixAtivo,
    required double percentualDescontoPix,
    required Color primaryColor,
    required Color cardColor,
    required Color textColor,
  }) {
    if (produtos.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: produtos.length,
      itemBuilder: (context, index) {
        final produto = produtos[index];
        final temDesconto = produto.promocaoAtiva;
        final precoFinal = produto.precoAtual;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: InkWell(
            onTap: () => _mostrarDetalhesProduto(context, produto, formatoMoeda, primaryColor, cardColor, textColor),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Imagem do Produto
                  ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      width: 90,
                      height: 90,
                      color: Colors.white.withOpacity(0.05),
                      child: Image.network(
                        produto.fotoPrincipalUrl ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Detalhes do Produto
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.nome,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (produto.descricao != null && produto.descricao!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              produto.descricao!,
                              style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              formatoMoeda.format(precoFinal),
                              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (temDesconto)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  formatoMoeda.format(produto.preco),
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.3),
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Botão Adicionar Rápido
                  const SizedBox(width: 10),
                  Material(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _adicionarProdutoAoCarrinho(produto),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.add_shopping_cart, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _mostrarDetalhesProduto(BuildContext context, Produto produto, NumberFormat moeda, Color primary, Color card, Color text) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: card.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: text.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Image.network(
                                  produto.fotoPrincipalUrl ?? (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : ''),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(color: text.withOpacity(0.05), child: Icon(Icons.image_not_supported, size: 64, color: text.withOpacity(0.2))),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(produto.nome, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: text)),
                            const SizedBox(height: 8),
                            Text(produto.grupo, style: TextStyle(fontSize: 14, color: primary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            if (produto.descricao?.isNotEmpty ?? false)
                              Text(produto.descricao!, style: TextStyle(fontSize: 16, color: text.withOpacity(0.7), height: 1.5)),
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (produto.promocaoAtiva)
                                      Text(moeda.format(produto.preco), style: TextStyle(fontSize: 16, color: text.withOpacity(0.4), decoration: TextDecoration.lineThrough)),
                                    Text(moeda.format(produto.precoAtual), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primary)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                                  child: Text(produto.estoqueTotal > 0 ? 'Em Estoque' : 'Indisponível', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                decoration: BoxDecoration(
                  color: card,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: produto.estoqueTotal > 0 ? () {
                          _adicionarProdutoAoCarrinho(produto);
                          Navigator.pop(context);
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text('Adicionar ao Carrinho', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Métodos de construção removidos (substituídos por widgets externos)


  Alignment _obterAlinhamentoImagem(Map<String, dynamic>? config) {
    final posicaoImagem = config?['posicaoImagem'] as String? ?? 'centro';
    switch (posicaoImagem) {
      case 'topo':
        return Alignment.topCenter;
      case 'fundo':
        return Alignment.bottomCenter;
      case 'esquerda':
        return Alignment.centerLeft;
      case 'direita':
        return Alignment.centerRight;
      case 'centro':
      default:
        return Alignment.center;
    }
  }

  Widget _buildImagemComHover({
    required String? fotoUrl,
    required double borderRadius,
    required Map<String, dynamic>? configEcommerce,
    required Produto produto,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: fotoUrl != null && fotoUrl.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Imagem principal com zoom suave e brilho
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        transform: Matrix4.identity()
                          ..scale(isHovered ? 1.2 : 1.0),
                        decoration: BoxDecoration(
                          boxShadow: isHovered ? [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ] : null,
                        ),
                        child: Container(
                          width: double.infinity,
                          height: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.network(
                            fotoUrl,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            cacheWidth: 300,
                            cacheHeight: 300,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 32,
                                  color: Colors.grey[300],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Overlay elegante no hover com efeito de brilho
                      AnimatedOpacity(
                        opacity: isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.0),
                                Colors.black.withOpacity(0.4),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: AnimatedScale(
                              scale: isHovered ? 1.0 : 0.8,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.elasticOut,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.98),
                                      Colors.white.withOpacity(0.95),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(25),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                      offset: Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                      blurRadius: 20,
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedRotation(
                                      turns: isHovered ? 0.25 : 0.0,
                                      duration: const Duration(milliseconds: 400),
                                      curve: Curves.easeOutCubic,
                                      child: Icon(
                                        Icons.zoom_in,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Ver detalhes',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Badge de promoção
                      if (produto.promocaoAtiva)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              '${produto.percentualDesconto.toStringAsFixed(0)}% OFF',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      // Badge de estoque baixo
                      if (produto.estoque <= 5 && produto.estoque > 0)
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Text(
                              'Últimas ${produto.estoque}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Icon(
                      Icons.image,
                      size: 40,
                      color: Colors.grey[300],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildCardProduto(Produto produto, NumberFormat formatoMoeda, bool descontoPixAtivo, double percentualDescontoPix, String estiloCards, {bool isCompacto = false}) {
    final estoqueTotal = produto.estoqueTotal;
    final temEstoque = estoqueTotal > 0;
    final estoqueBaixo = estoqueTotal <= 5 && estoqueTotal > 0;
    final fotoUrl = produto.fotoPrincipalUrl ?? 
                    (produto.fotosUrls.isNotEmpty ? produto.fotosUrls.first : null);
    
    // Obter cor primária da configuração
    final configEcommerce = _obterConfigEcommerce();
    final corPrimariaLoja = _hexToColor(configEcommerce?['corPrimariaLoja'] as String?);
    final corSecundariaLoja = _hexToColor(configEcommerce?['corSecundariaLoja'] as String?);
    
    // Border radius padrão moderno
    const borderRadius = 12.0;

    return StatefulBuilder(
      builder: (context, setState) {
        bool isCardHovered = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isCardHovered = true),
          onExit: (_) => setState(() => isCardHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..scale(isCardHovered ? 1.02 : 1.0)
              ..translate(0.0, isCardHovered ? -2.0 : 0.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: isCardHovered
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          (corPrimariaLoja ?? Theme.of(context).colorScheme.primary).withOpacity(0.02),
                        ],
                      )
                    : null,
                color: isCardHovered ? null : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCardHovered 
                      ? (corPrimariaLoja ?? Theme.of(context).colorScheme.primary).withOpacity(0.4)
                      : Colors.grey[200]!,
                  width: isCardHovered ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCardHovered
                        ? (corPrimariaLoja ?? Theme.of(context).colorScheme.primary).withOpacity(0.2)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: isCardHovered ? 8 : 3,
                    offset: Offset(0, isCardHovered ? 2 : 0.5),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                        // Imagem do produto - altura reduzida e moderna com efeitos
                        MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: () => _mostrarDetalhesProduto(
                        context,
                        produto,
                        formatoMoeda,
                        corPrimariaLoja ?? _LojaPublicaStyle.primaryColor,
                        _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
                        _isDark ? _LojaPublicaStyle.textColor : const Color(0xFF1E293B),
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: SizedBox(
                          height: 150, // Altura da imagem aumentada
                          width: double.infinity,
                          child: _buildImagemComHover(
                            fotoUrl: fotoUrl,
                            borderRadius: 0,
                            configEcommerce: configEcommerce,
                            produto: produto,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Informações do produto com padding minimalista
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: EdgeInsets.fromLTRB(
                      isCompacto ? 6.0 : 8.0,
                      isCompacto ? 4.0 : 4.0,
                      isCompacto ? 6.0 : 8.0,
                      isCompacto ? 0.0 : 0.0,
                    ),
                    decoration: BoxDecoration(
                      gradient: isCardHovered
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.95),
                                Colors.white,
                              ],
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Nome e categoria com tooltip e animação sutil
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isCompacto ? 13 : 13,
                            color: isCardHovered ? Colors.black : Colors.black87,
                            height: 1.1,
                            letterSpacing: 0.0,
                          ),
                          child: Text(
                            produto.nome,
                            maxLines: isCompacto ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(height: isCompacto ? 0.5 : 1),
                        // Preço - estilo profissional premium
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (produto.promocaoAtiva) ...[
                              Row(
                                children: [
                                  Text(
                                    formatoMoeda.format(produto.preco),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${produto.percentualDesconto.toStringAsFixed(0)}% OFF',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 0.5),
                            ],
                            // Preço atual com animação
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 300),
                          style: TextStyle(
                            fontSize: isCompacto ? 13 : 16,
                            fontWeight: FontWeight.bold,
                            color: produto.promocaoAtiva 
                                ? Colors.red[700]
                                : corPrimariaLoja ?? Theme.of(context).colorScheme.primary,
                                shadows: isCardHovered ? [
                                  Shadow(
                                    color: (corPrimariaLoja ?? Theme.of(context).colorScheme.primary).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ] : null,
                              ),
                              child: Text(
                                formatoMoeda.format(produto.precoAtual),
                              ),
                            ),
                            // Preço no PIX (desconto configurável) - ocultar em modo compacto
                            if (descontoPixAtivo && percentualDescontoPix > 0 && !isCompacto) ...[
                              const SizedBox(height: 0.5),
                              Row(
                                children: [
                                  Icon(
                                    Icons.pix,
                                    size: 14,
                                    color: Colors.green[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${formatoMoeda.format(produto.precoAtual * (1 - percentualDescontoPix / 100))} no PIX',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        // Indicador de estoque zero (compacto)
                        if (!temEstoque) ...[
                          SizedBox(height: isCompacto ? 0.5 : 0.5),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: isCompacto ? 4 : 6, vertical: isCompacto ? 1 : 2),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red[200]!, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: isCompacto ? 10 : 12, color: Colors.red[700]),
                                SizedBox(width: isCompacto ? 2 : 3),
                                Text(
                                  'Esgotado',
                                  style: TextStyle(
                                    fontSize: isCompacto ? 9 : 10,
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Botão de compra moderno com efeitos inteligentes
                        Padding(
                          padding: EdgeInsets.only(
                            top: !temEstoque ? (isCompacto ? 2 : 2) : (isCompacto ? 2 : 3),
                            bottom: 0,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            transform: Matrix4.identity()..scale(isCardHovered && temEstoque ? 1.02 : 1.0),
                            child: SizedBox(
                              width: double.infinity,
                              height: isCompacto ? 26 : 30,
                              child: ElevatedButton(
                                onPressed: temEstoque
                                    ? () {
                                        _adicionarProdutoAoCarrinho(produto);
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: temEstoque 
                                      ? (corPrimariaLoja ?? Theme.of(context).colorScheme.primary)
                                      : Colors.grey[300],
                                  foregroundColor: temEstoque ? Colors.white : Colors.grey[600],
                                  elevation: isCardHovered && temEstoque ? 4 : (temEstoque ? 1 : 0),
                                  shadowColor: isCardHovered && temEstoque
                                      ? (corPrimariaLoja ?? Theme.of(context).colorScheme.primary).withOpacity(0.5)
                                      : null,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedRotation(
                                      turns: isCardHovered && temEstoque ? 0.1 : 0.0,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                      child: Icon(
                                        temEstoque ? Icons.shopping_cart_outlined : Icons.block,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 300),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.0,
                                      ),
                                      child: Text(
                                        temEstoque ? 'Adicionar' : 'Indisponível',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
        );
      },
    );
  }

  // Métodos de serviços removidos - serviços não são mais exibidos no e-commerce

  void _mostrarCarrinhoDrawer(NumberFormat formatoMoeda) {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  // Removido método duplicado _mostrarDetalhesProduto
  // Fim da limpeza

  // Método _mostrarDetalhesServico removido - serviços não são mais exibidos no e-commerce

  /// Widget para calcular frete antes da compra
  Widget _buildWidgetCalcularFrete(Produto produto, NumberFormat formatoMoeda, Color? corPrimariaLoja) {
    final cepController = TextEditingController();
    bool calculandoFrete = false;
    List<OpcaoFrete> opcoesFrete = [];
    bool freteCalculado = false;

    return StatefulBuilder(
      builder: (context, setBuilderState) {
        String? estadoLoja;
        String? cepLoja;

        // Carregar dados da loja
        final authService = Provider.of<AuthService>(context, listen: false);
        final empresa = authService.empresaAtual;
        if (empresa != null) {
          estadoLoja = empresa.estado;
          cepLoja = empresa.cep;
        }

        Future<void> calcularFrete() async {
          final cep = cepController.text.replaceAll(RegExp(r'[^\d]'), '');
          if (cep.length != 8) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('CEP inválido. Digite um CEP com 8 dígitos.'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          setBuilderState(() {
            calculandoFrete = true;
            freteCalculado = false;
            opcoesFrete = [];
          });

          try {
            // Buscar endereço pelo CEP
            final endereco = await FreteService.buscarEnderecoPorCEP(cep);
            final estadoDestino = endereco['estado'];
            
            if (estadoDestino == null || estadoLoja == null) {
              throw Exception('Não foi possível determinar o estado de origem ou destino');
            }

            // Calcular peso do produto (usar pesoGramas do produto ou padrão de 1kg)
            final pesoTotal = (produto.pesoGramas ?? 1000).toDouble(); // gramas
            final valorPedido = produto.precoAtual;

            // Obter valor mínimo para frete grátis
            final valorMinimoFreteGratis = empresa?.configuracoes?['ecommerce']?['valorFreteGratis'] as num? ?? 399.90;

            // Obter configurações de frete do e-commerce
            final configFrete = empresa?.configuracoes?['ecommerce']?['frete'] as Map<String, dynamic>?;
            
            // Carregar Zonas de Entrega Inteligentes
            final zonasData = configFrete?['zonasEntrega'] as List<dynamic>? ?? [];
            final List<ZonaEntrega> zonasEntrega = zonasData
                .map((z) => ZonaEntrega.fromMap(z as Map<String, dynamic>))
                .toList();

            // Configurar credenciais das transportadoras (se disponíveis)
            FreteService.configurarCorreios(
              codigoEmpresa: configFrete?['correiosCodigo'] as String?,
              senha: configFrete?['correiosSenha'] as String?,
            );
            FreteService.configurarCredenciaisTransportadoras(
              jadlogToken: configFrete?['jadlogToken'] as String?,
              totalExpressToken: configFrete?['totalExpressToken'] as String?,
              azulCargoToken: configFrete?['azulCargoToken'] as String?,
              loggiToken: configFrete?['loggiToken'] as String?,
              melhorEnvioToken: configFrete?['melhorEnvioToken'] as String?,
              melhorEnvioEmail: configFrete?['melhorEnvioEmail'] as String?,
            );

            // Calcular opções de frete
            final opcoes = await FreteService.calcularOpcoesFrete(
              estadoOrigem: estadoLoja!,
              estadoDestino: estadoDestino,
              pesoTotal: pesoTotal,
              valorPedido: valorPedido,
              cepOrigem: cepLoja != null && cepLoja!.replaceAll(RegExp(r'[^\d]'), '').length == 8
                  ? cepLoja!.replaceAll(RegExp(r'[^\d]'), '')
                  : null,
              cepDestino: cep,
              bairroDestino: endereco['bairro'],
              cidadeDestino: endereco['cidade'],
              valorMinimoFreteGratis: valorMinimoFreteGratis.toDouble(),
              configFrete: configFrete,
              zonasEntrega: zonasEntrega.isNotEmpty ? zonasEntrega : null,
            );

            setBuilderState(() {
              opcoesFrete = opcoes;
              freteCalculado = true;
              calculandoFrete = false;
            });

            if (opcoes.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Nenhuma opção de frete disponível para este CEP.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } catch (e) {
            setBuilderState(() {
              calculandoFrete = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao calcular frete: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }

        // Cor primária da loja ou cor padrão roxa/azul gradiente
        final corPrincipal = corPrimariaLoja ?? const Color(0xFF6366F1);
        final corSecundaria = corPrimariaLoja?.withOpacity(0.7) ?? const Color(0xFF8B5CF6);
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            // Gradiente escuro premium
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1A1D23),
                Color(0xFF2D3139),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: corPrincipal.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: corPrincipal.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header com ícone animado
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [corPrincipal, corSecundaria],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: corPrincipal.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Calcular Frete',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Descubra o valor da entrega',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Campo de CEP com design premium
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: cepController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Digite seu CEP',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 15,
                          ),
                          prefixIcon: Icon(
                            Icons.location_on_rounded,
                            color: corPrincipal,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          counterText: '',
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 9,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;
                            if (text.length <= 5) {
                              return newValue;
                            }
                            return TextEditingValue(
                              text: '${text.substring(0, 5)}-${text.substring(5)}',
                              selection: TextSelection.collapsed(offset: newValue.text.length + 1),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [corPrincipal, corSecundaria],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: corPrincipal.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: calculandoFrete ? null : calcularFrete,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (calculandoFrete)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                else
                                  const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  calculandoFrete ? 'Calculando...' : 'Calcular',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              // Resultados do frete com design premium
              if (freteCalculado && opcoesFrete.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [corPrincipal, corSecundaria],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Opções de entrega',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.9),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...opcoesFrete.map((opcao) {
                  final isGratis = opcao.valor == 0;
                  final isSelecionada = _freteSelecionadoProduto?.id == opcao.id;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelecionada 
                          ? corPrincipal.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelecionada
                            ? corPrincipal
                            : (isGratis 
                                ? Colors.green.withOpacity(0.4)
                                : Colors.white.withOpacity(0.1)),
                        width: isSelecionada ? 2 : 1,
                      ),
                      boxShadow: isSelecionada ? [
                        BoxShadow(
                          color: corPrincipal.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ] : [],
                    ),
                    child: InkWell(
                      onTap: () {
                        setBuilderState(() {
                          _freteSelecionadoProduto = opcao;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            // Radio button customizado
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelecionada ? corPrincipal : Colors.white38,
                                  width: isSelecionada ? 6 : 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Ícone da transportadora
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isGratis 
                                    ? Colors.green.withOpacity(0.15)
                                    : corPrincipal.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isGratis ? Icons.celebration_rounded : Icons.inventory_2_rounded,
                                size: 20,
                                color: isGratis ? Colors.green[400] : corPrincipal,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Informações da opção
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    opcao.nome,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isSelecionada ? Colors.white : Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  if (opcao.descricao != null)
                                    Text(
                                      opcao.descricao!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 14,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${opcao.prazo} dia${opcao.prazo > 1 ? 's' : ''} útil${opcao.prazo > 1 ? 'eis' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Preço com destaque
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: isGratis
                                    ? LinearGradient(
                                        colors: [Colors.green[600]!, Colors.green[500]!],
                                      )
                                    : LinearGradient(
                                        colors: [corPrincipal.withOpacity(0.2), corSecundaria.withOpacity(0.2)],
                                      ),
                                borderRadius: BorderRadius.circular(8),
                                border: isGratis
                                    ? null
                                    : Border.all(color: corPrincipal.withOpacity(0.3)),
                              ),
                              child: Text(
                                isGratis ? 'GRÁTIS' : formatoMoeda.format(opcao.valor),
                                style: TextStyle(
                                  fontSize: isGratis ? 13 : 15,
                                  fontWeight: FontWeight.bold,
                                  color: isGratis ? Colors.white : (isSelecionada ? Colors.white : corPrincipal),
                                  letterSpacing: isGratis ? 0.5 : 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }







  double _calcularTotal() {
    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    return carrinhoService.valorTotal;
  }

  void _atualizarQuantidade(String itemId, int novaQuantidade) {
    Provider.of<CarrinhoService>(context, listen: false).atualizarQuantidade(itemId, novaQuantidade);
  }

  void _removerDoCarrinho(String itemId) {
    Provider.of<CarrinhoService>(context, listen: false).removerItem(itemId);
  }


  Widget _buildBannerPromocional(String texto, Color cor1, Color cor2) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cor1, cor2]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildListaProdutos(
    List<Produto> produtos,
    NumberFormat formatoMoeda,
    bool descontoPixAtivo,
    double percentualDescontoPix,
    String estiloCards,
    bool deveExibirBannerFreteGratis,
    String posicaoBannerFreteGratis,
    String textoBannerFreteGratis,
    double valorMinimoFreteGratis,
    double faltaParaFreteGratis,
    Color corPrimaria,
  ) {
    if (produtos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Nenhum produto encontrado',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: produtos.length,
      itemBuilder: (context, index) {
        return ProdutoCard(
          produto: produtos[index],
          formatoMoeda: formatoMoeda,
          descontoPixAtivo: descontoPixAtivo,
          percentualDescontoPix: percentualDescontoPix,
          estiloCards: estiloCards,
          corPrimaria: corPrimaria,
          onAddToCart: (p) => _adicionarProdutoAoCarrinho(p),
          onShowDetails: (p) => _mostrarDetalhesProduto(
            context,
            p,
            formatoMoeda,
            corPrimaria,
            _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
            _isDark ? _LojaPublicaStyle.textColor : const Color(0xFF1E293B),
          ),
        );
      },
    );
  }
}
