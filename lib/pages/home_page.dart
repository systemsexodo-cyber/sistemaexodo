import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/clientes_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/widgets/permission_widget.dart';
import 'package:sistema_exodo_novo/models/permissao.dart';
import 'package:sistema_exodo_novo/widgets/tela_access_widget.dart';
import 'package:sistema_exodo_novo/models/tela_sistema.dart';
import 'produtos_page.dart';
import 'servicos_page.dart';
import 'pedidos_page.dart';
import 'venda_direta_page.dart';
import 'entrada_mercadorias_page.dart';
import 'contas_pagar_page.dart';
import 'agenda_contas_page.dart';
import 'dashboard_page.dart';
import 'gerenciar_permissoes_page.dart';
import 'cozinha_bar_page.dart';
import 'cozinha_mesas_funcionario_page.dart';
import 'gerenciar_links_vendedores_page.dart';
import 'vendedor_dashboard_page.dart';
import 'funcionarios_page.dart';
import 'personalizar_loja_page.dart';
import 'gerenciar_imagens_page.dart';
import 'agenda_servicos_page.dart';
import 'caixa_page.dart';
import 'comissoes_page.dart';
import 'entregas_page.dart';
import 'empresas_page.dart';
import 'taxas_entrega_page.dart';
import 'historico_vendas_page.dart';
import 'historico_operacoes_page.dart';
import 'gerenciar_usuarios_page.dart';
import 'trocas_devolucoes_page.dart';
import 'configuracoes_agenda_page.dart';
import 'whatsapp_gerenciamento_page.dart';
import '../services/data_service.dart';
import '../services/theme_service.dart';
import '../widgets/sync_status_widget.dart';
import 'adicionar_empresa_page.dart';

// Import condicional para Web
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;

class HomePage extends StatefulWidget {
  final String? initialPage;
  const HomePage({super.key, this.initialPage});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<String>? _customOrder;
  bool _isReordering = false;

  // Lista mestre de itens do menu (conforme estão hoje no grid)
  late final List<Map<String, dynamic>> _menuItems;

  void _inicializarMenu() {
    _menuItems = [
      {
        'id': 'pdv',
        'title': 'PDV',
        'subtitle': 'Ponto de Venda',
        'icon': Icons.point_of_sale,
        'color': const Color(0xFF00BCD4),
        'tela': TelaSistema.pdv,
        'permissao': TipoPermissao.vendasVisualizar,
        'page': (BuildContext context) => VendaDiretaPage(),
      },
      {
        'id': 'pedidos',
        'title': 'Pedidos',
        'subtitle': 'Central de Pedidos',
        'icon': Icons.receipt_long,
        'color': const Color(0xFF9C27B0),
        'tela': TelaSistema.pedidos,
        'page': (BuildContext context) => const PedidosPage(),
      },
      {
        'id': 'clientes',
        'title': 'Clientes',
        'icon': Icons.person,
        'color': const Color(0xFF2196F3),
        'tela': TelaSistema.clientes,
        'permissao': TipoPermissao.clientesVisualizar,
        'page': (BuildContext context) => const ClientesPage(),
      },
      {
        'id': 'produtos',
        'title': 'Produtos',
        'icon': Icons.shopping_bag,
        'color': const Color(0xFF4CAF50),
        'tela': TelaSistema.produtos,
        'permissao': TipoPermissao.produtosVisualizar,
        'page': (BuildContext context) => ProdutosPage(),
      },
      {
        'id': 'servicos',
        'title': 'Serviços',
        'icon': Icons.build,
        'color': const Color(0xFFFF9800),
        'tela': TelaSistema.servicos,
        'page': (BuildContext context) => ServicosPage(),
      },
      {
        'id': 'funcionarios',
        'title': 'Funcionários',
        'subtitle': 'Vendedores',
        'icon': Icons.people,
        'color': const Color(0xFF607D8B),
        'tela': TelaSistema.funcionarios,
        'page': (BuildContext context) => const FuncionariosPage(),
      },
      {
        'id': 'entrada',
        'title': 'Entrada',
        'subtitle': 'Mercadorias',
        'icon': Icons.inventory,
        'color': const Color(0xFFE91E63),
        'tela': TelaSistema.entradaMercadorias,
        'page': (BuildContext context) => const EntradaMercadoriasPage(),
      },
      {
        'id': 'caixa',
        'title': 'Fluxo de Caixa',
        'subtitle': 'Entradas e Saídas',
        'icon': Icons.account_balance_wallet,
        'color': const Color(0xFF4DB6AC),
        'tela': TelaSistema.caixa,
        'page': (BuildContext context) => const CaixaPage(),
      },
      {
        'id': 'contas_pagar',
        'title': 'Contas a Pagar',
        'subtitle': 'Despesas',
        'icon': Icons.payment,
        'color': const Color(0xFFD32F2F),
        'tela': TelaSistema.contasPagar,
        'page': (BuildContext context) => const ContasPagarPage(),
      },
      {
        'id': 'agenda_contas',
        'title': 'Agenda',
        'subtitle': 'Contas Semanais',
        'icon': Icons.calendar_today,
        'color': const Color(0xFF1976D2),
        'tela': TelaSistema.agendaContas,
        'page': (BuildContext context) => const AgendaContasPage(),
      },
      {
        'id': 'cozinha',
        'title': 'Cozinha e Bar',
        'subtitle': 'Pedidos',
        'icon': Icons.restaurant,
        'color': const Color(0xFFFF5722),
        'tela': TelaSistema.cozinhaBar,
        'permissao': TipoPermissao.cozinhaVisualizar,
        'page': (BuildContext context) => const CozinhaBarPage(),
      },
      {
        'id': 'mesas',
        'title': 'Mesas/Comandas',
        'subtitle': 'Gerenciamento',
        'icon': Icons.table_restaurant,
        'color': const Color(0xFFFF9800),
        'tela': TelaSistema.mesas,
        'permissao': TipoPermissao.cozinhaFuncionario,
        'page': (BuildContext context) => CozinhaMesasFuncionarioPage(),
      },
      {
        'id': 'personalizar',
        'title': 'Personalizar',
        'subtitle': 'Loja Online',
        'icon': Icons.palette,
        'color': const Color(0xFFFF6B6B),
        'tela': TelaSistema.personalizarLoja,
        'page': (BuildContext context) => const PersonalizarLojaPage(),
      },
      {
        'id': 'whatsapp',
        'title': 'WhatsApp',
        'subtitle': 'Automação',
        'icon': Icons.chat_bubble_outline,
        'color': const Color(0xFF25D366),
        'page': (BuildContext context) => const WhatsAppGerenciamentoPage(),
      },
      {
        'id': 'vendedor_dash',
        'title': 'Vendedor',
        'subtitle': 'Dashboard',
        'icon': Icons.dashboard_customize,
        'color': const Color(0xFF00BCD4),
        'tela': TelaSistema.vendedorDashboard,
        'page': (BuildContext context) => const VendedorDashboardPage(),
      },
    ];
  }

  Future<void> _carregarOrdem() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final savedOrder = await dataService.storage.carregarLista('home_button_order');
    if (savedOrder.isNotEmpty) {
      setState(() {
        _customOrder = savedOrder.map((e) => e.toString()).toList();
      });
    }
  }

  Future<void> _salvarOrdem() async {
    if (_customOrder == null) return;
    final dataService = Provider.of<DataService>(context, listen: false);
    await dataService.storage.salvar('home_button_order', _customOrder);
  }

  List<Map<String, dynamic>> get _orderedMenuItems {
    if (_customOrder == null || _customOrder!.isEmpty) return _menuItems;
    
    // Ordenar baseado no customOrder, mantendo novos itens no final se surgirem
    List<Map<String, dynamic>> ordered = [];
    for (var id in _customOrder!) {
      final item = _menuItems.where((i) => i['id'] == id).firstOrNull;
      if (item != null) ordered.add(item);
    }
    
    for (var item in _menuItems) {
      if (!ordered.any((i) => i['id'] == item['id'])) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  void _fazerHardRefresh(BuildContext context) {
    if (kIsWeb) {
      // Mostrar diálogo de confirmação
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.refresh, color: Colors.blueAccent),
                SizedBox(width: 12),
                Text(
                  'Hard Refresh',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            content: const Text(
              'Isso irá recarregar a página e limpar o cache do navegador. Deseja continuar?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Fazer hard refresh usando JavaScript
                  html_helper.fazerHardRefresh();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Recarregar'),
              ),
            ],
          );
        },
      );
    } else {
      // Se não for Web, apenas mostra mensagem
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hard Refresh disponível apenas no navegador'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _fazerLogout(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Mostrar diálogo de confirmação
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Saída'),
          content: const Text('Deseja realmente sair do sistema?'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      // Fazer logout
      await authService.logout();
      
      // Mostrar mensagem de saída
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você saiu do sistema. Até logo!'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Redirecionar para login após um breve delay
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const ExodoLogoCompact(fontSize: 28), // Restaurado 'ê' conforme pedido
          centerTitle: true,
          actions: [
            const SyncStatusWidget(),

            // Botão de Reordenar (Feedback Visual)
            if (_customOrder != null)
              IconButton(
                icon: const Icon(Icons.restore, color: Colors.orangeAccent),
                tooltip: 'Votar Ordem Padrão',
                onPressed: () {
                  setState(() {
                    _customOrder = null;
                  });
                  _salvarOrdem();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ordem dos botões resetada para o padrão')),
                  );
                },
              ),

            // Botão de Troca de Tema
            Consumer<ThemeService>(
              builder: (context, themeService, _) {
                return IconButton(
                  icon: Icon(themeService.getThemeIcon(themeService.currentTheme), color: Colors.blueAccent),
                  tooltip: 'Trocar Tema Visual',
                  onPressed: () => _mostrarSeletorTema(context, themeService),
                );
              },
            ),



            IconButton(
              icon: Icon(
                _currentPage == 0 ? Icons.dashboard : Icons.home,
                color: _currentPage == 0 ? const Color(0xFFFF6B35) : Colors.white70,
              ),
              tooltip: _currentPage == 0 ? 'Arraste para direita ou clique para Dashboard' : 'Voltar para Home',
              onPressed: () {
                if (_currentPage == 0) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
            ),
            if (_currentPage == 1)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar Dashboard',
                onPressed: () {
                  // Forçar atualização do dashboard
                  setState(() {});
                },
              ),
            PermissionWidget(
              permissao: TipoPermissao.financeiroVisualizar,
              child: IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.blue),
                tooltip: 'Agenda de Contas',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AgendaContasPage()),
                  );
                },
              ),
            ),
            PermissionWidget(
              permissao: TipoPermissao.financeiroVisualizar,
              child: IconButton(
                icon: const Icon(Icons.payment, color: Colors.red),
                tooltip: 'Contas a Pagar',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ContasPagarPage()),
                  );
                },
              ),
            ),
            // Botão de Gerenciar Permissões - apenas para usuário master ou "user"
            Builder(
              builder: (context) {
                final authService = Provider.of<AuthService>(context);
                final usuarioAtual = authService.usuarioAtual;
                
                // Só mostra se for master ou "user"
                final podeGerenciar = usuarioAtual != null && 
                    (usuarioAtual.isMaster || usuarioAtual.email.toLowerCase() == 'user');
                
                if (!podeGerenciar) {
                  return const SizedBox.shrink();
                }
                
                final isUser = usuarioAtual.email.toLowerCase() == 'user';
                
                return IconButton(
                  icon: Icon(
                    Icons.security,
                    color: isUser ? Colors.blue : Colors.amber,
                  ),
                  tooltip: isUser 
                      ? 'Gerenciar Permissões (User - Todas as Empresas)'
                      : 'Gerenciar Permissões (Master - Todas as Empresas)',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GerenciarPermissoesPage()),
                    );
                  },
                );
              },
            ),
            if (kIsWeb)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Hard Refresh (Limpar Cache)',
                onPressed: () => _fazerHardRefresh(context),
              ),
            // Botão Configuração da Empresa (Atalho Rápido)
            Builder(
              builder: (context) {
                final authService = Provider.of<AuthService>(context);
                final dataService = Provider.of<DataService>(context);
                final usuarioAtual = authService.usuarioAtual;
                
                final podeAcessar = usuarioAtual != null && 
                    (usuarioAtual.email.toLowerCase() == 'user' || usuarioAtual.isMaster);
                
                if (!podeAcessar || dataService.empresaAtual == null) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  icon: const Icon(Icons.business, color: Colors.amber),
                  tooltip: 'Configurações de Impressão e Empresa',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdicionarEmpresaPage(empresa: dataService.empresaAtual),
                      ),
                    );
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sair do sistema',
              onPressed: () => _fazerLogout(context),
            ),
          ],
        ),
        body: PageView(
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentPage = index;
            });
          },
          children: [
            // Página 0: Home (menu principal)
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(left: 24, right: 24, top: 0, bottom: 24),
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo principal
                    const ExodoLogo(
                      fontSize: 54, // Reduzido de 64
                      showSubtitle: true,
                    ),
                    const SizedBox(height: 16),
                    
                    // Grid de botões de navegação
                    _buildNavigationGrid(context),
                  ],
                ),
              ),
            ),
            // Página 1: Dashboard
            const DashboardPage(showAppBar: false),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _inicializarMenu();
    _carregarOrdem();
    
    // Se temos uma página inicial via URL, navegar para ela após o build
    if (widget.initialPage != null && widget.initialPage != 'home' && widget.initialPage != '') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navegarParaPaginaInicial(widget.initialPage!);
      });
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se a página inicial mudar via URL (ex: navegação back/forward no browser)
    if (widget.initialPage != oldWidget.initialPage && 
        widget.initialPage != null && 
        widget.initialPage != 'home' && 
        widget.initialPage != '') {
      debugPrint('>>> [HomePage] Rota mudou via Widget Update: ${widget.initialPage}');
      _navegarParaPaginaInicial(widget.initialPage!);
    }
  }

  void _navegarParaPaginaInicial(String route) {
    Widget? page;
    String? urlPath;

    switch (route) {
      case 'clientes': page = const ClientesPage(); urlPath = '/clientes'; break;
      case 'produtos': page = ProdutosPage(); urlPath = '/produtos'; break;
      case 'servico':
      case 'servicos': page = ServicosPage(); urlPath = '/servicos'; break;
      case 'pedidos': page = const PedidosPage(); urlPath = '/pedidos'; break;
      case 'venda-direta': 
      case 'pdv': page = VendaDiretaPage(); urlPath = '/pdv'; break;
      case 'entrada-mercadorias': page = const EntradaMercadoriasPage(); urlPath = '/entrada-mercadorias'; break;
      case 'contas-pagar': page = const ContasPagarPage(); urlPath = '/contas-pagar'; break;
      case 'agenda-contas': page = const AgendaContasPage(); urlPath = '/agenda-contas'; break;
      case 'cozinha-bar': page = const CozinhaBarPage(); urlPath = '/cozinha-bar'; break;
      case 'mesas': page = CozinhaMesasFuncionarioPage(); urlPath = '/mesas'; break;
      case 'links-vendedores': page = const GerenciarLinksVendedoresPage(); urlPath = '/links-vendedores'; break;
      case 'vendedor-dashboard': page = const VendedorDashboardPage(); urlPath = '/vendedor-dashboard'; break;
      case 'funcionarios': page = const FuncionariosPage(); urlPath = '/funcionarios'; break;
      case 'personalizar-loja': page = const PersonalizarLojaPage(); urlPath = '/personalizar-loja'; break;
      case 'agenda-pet': page = AgendaServicosPage(); urlPath = '/agenda-pet'; break;
      case 'gerenciar-imagens': page = const GerenciarImagensPage(); urlPath = '/gerenciar-imagens'; break;
      case 'caixa': page = const CaixaPage(); urlPath = '/caixa'; break;
      case 'comissoes': page = const ComissoesPage(); urlPath = '/comissoes'; break;
      case 'entregas': page = const EntregasPage(); urlPath = '/entregas'; break;
      case 'empresas': page = const EmpresasPage(); urlPath = '/empresas'; break;
      case 'taxas-entrega': page = const TaxasEntregaPage(); urlPath = '/taxas-entrega'; break;
      case 'gerenciar-permissoes': page = const GerenciarPermissoesPage(); urlPath = '/gerenciar-permissoes'; break;
      case 'historico-vendas': page = const HistoricoVendasPage(); urlPath = '/historico-vendas'; break;
      case 'historico-operacoes': page = const HistoricoOperacoesPage(); urlPath = '/historico-operacoes'; break;
      case 'gerenciar-usuarios': 
        final empresa = Provider.of<DataService>(context, listen: false).empresaAtual;
        if (empresa != null) {
          page = GerenciarUsuariosPage(empresa: empresa);
        }
        urlPath = '/gerenciar-usuarios'; 
        break;
      case 'trocas-devolucoes': page = const TrocasDevolucoesBuscarPage(); urlPath = '/trocas-devolucoes'; break;
      case 'configuracoes-agenda': page = const ConfiguracoesAgendaPage(); urlPath = '/configuracoes-agenda'; break;
      case 'whatsapp': page = const WhatsAppGerenciamentoPage(); urlPath = '/whatsapp'; break;
    }

    if (page != null) {
      debugPrint('>>> [HomePage] Navegação automática para: $route');
      
      // Se for Web, garantir que o link original seja mantido/atualizado
      if (kIsWeb && urlPath != null) {
         html_helper.updateUrl(urlPath, replace: true);
      }

      // Usar push mas verificar se já não estamos nela
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page!),
      ).then((_) {
        // Ao voltar, garante que a URL volte para home (/)
        if (kIsWeb) {
          html_helper.updateUrl('/');
        }
      });
    }
  }

  void _mostrarSeletorTema(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Column(
          children: [
            Icon(Icons.palette_outlined, color: Colors.blueAccent, size: 40),
            SizedBox(height: 12),
            Text('Escolha o Visual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('Selecione uma paleta para o sistema', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.normal)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: AppThemeType.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final type = AppThemeType.values[index];
              final isSelected = themeService.currentTheme == type;
              
              final config = themeService.getThemeConfig(Colors.blue, Colors.blueGrey);
              
              // Cores estáticas para o preview para evitar recursão ou complexidade desnecessária no loop
              Color prim, sec, bg;
              bool isLight = false;
              
              if (type == AppThemeType.purple) { prim = const Color(0xFF6200EE); sec = const Color(0xFF9575CD); bg = const Color(0xFF0F0E17); }
              else if (type == AppThemeType.ocean) { prim = const Color(0xFF00BFA5); sec = const Color(0xFF01579B); bg = const Color(0xFF010B13); }
              else if (type == AppThemeType.emerald) { prim = const Color(0xFF43A047); sec = const Color(0xFFC0CA33); bg = const Color(0xFF0A140B); }
              else if (type == AppThemeType.snow) { prim = const Color(0xFF2196F3); sec = const Color(0xFF64B5F6); bg = const Color(0xFFF8F9FA); isLight = true; }
              else if (type == AppThemeType.sand) { prim = const Color(0xFF795548); sec = const Color(0xFFA1887F); bg = const Color(0xFFF5F5F0); isLight = true; }
              else if (type == AppThemeType.diamond) { prim = const Color(0xFF1976D2); sec = const Color(0xFF0D47A1); bg = const Color(0xFF010A1A); }
              else { prim = Colors.blue; sec = Colors.blueGrey; bg = const Color(0xFF10151B); }

              return InkWell(
                onTap: () {
                  themeService.setTheme(type);
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white10, width: 2),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [bg, prim, sec]),
                          borderRadius: BorderRadius.circular(12),
                          border: isLight ? Border.all(color: Colors.black12) : null,
                        ),
                        child: Icon(themeService.getThemeIcon(type), color: isLight ? Colors.black54 : Colors.white70, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              themeService.getThemeName(type),
                              style: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              isLight ? 'Claro / Minimalista' : 'Escuro / Moderno',
                              style: TextStyle(color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, color: Colors.blueAccent),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildNavigationGrid(BuildContext context) {
    final items = _orderedMenuItems;
    
    return Column(
      children: [
        // Instrução rápida se estiver em modo de reordenação (pc)
        if (_isReordering)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Pressione e segure para arrastar os botões. Clique em 'Concluir' no topo para salvar.",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Grid com ReorderableWrap (simulado via ReorderableListView em grid se possível, ou Wrap customizado)
        // Para simplificar e garantir estabilidade sem pacotes externos, usaremos uma estratégia de troca
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;
            const double spacing = 16.0;
            final double itemWidth = (width - spacing) / 2;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(items.length, (index) {
                final item = items[index];
                
                return DragTarget<int>(
                  onWillAccept: (data) => data != index,
                  onAccept: (fromIndex) {
                    setState(() {
                      final movedItem = items.removeAt(fromIndex);
                      items.insert(index, movedItem);
                      _customOrder = items.map((i) => i['id'] as String).toList();
                    });
                    _salvarOrdem();
                  },
                  builder: (context, candidateData, rejectedData) {
                    return LongPressDraggable<int>(
                      data: index,
                      feedback: SizedBox(
                        width: itemWidth,
                        child: Opacity(
                          opacity: 0.8,
                          child: _buildItemWidget(context, item, isFullWidth: false, dragFeedback: true),
                        ),
                      ),
                      childWhenDragging: SizedBox(
                        width: itemWidth,
                        child: Opacity(
                          opacity: 0.1,
                          child: _buildItemWidget(context, item, isFullWidth: false),
                        ),
                      ),
                      onDragStarted: () => setState(() => _isReordering = true),
                      onDragEnd: (_) => setState(() => _isReordering = false),
                      child: SizedBox(
                        width: itemWidth,
                        child: _buildItemWidget(context, item, isFullWidth: false),
                      ),
                    );
                  },
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildItemWidget(BuildContext context, Map<String, dynamic> item, {bool isFullWidth = false, bool dragFeedback = false}) {
    Widget content = _buildNavButton(
      context,
      title: item['title'],
      subtitle: item['subtitle'],
      icon: item['icon'],
      color: item['color'],
      page: item['page'](context),
      isFullWidth: isFullWidth,
      isDragging: dragFeedback,
    );

    if (item['tela'] != null) {
      content = TelaAccessWidget(tela: item['tela'], child: content);
    }
    
    if (item['permissao'] != null) {
      content = PermissionWidget(permissao: item['permissao'], child: content);
    }

    return content;
  }

  Widget _buildNavButton(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    bool isFullWidth = false,
    bool isDragging = false,
  }) {
    // Tamanhos reduzidos para economizar espaço
    final iconSize = isFullWidth ? 48.0 : 28.0;
    final iconPadding = isFullWidth ? 20.0 : 12.0;
    final titleFontSize = isFullWidth ? 24.0 : 15.0;
    final subtitleFontSize = isFullWidth ? 14.0 : 11.0;
    final containerPadding = isFullWidth ? 24.0 : 14.0;
    final spacing = isFullWidth ? 16.0 : 12.0;

    bool isHovered = false;

    return StatefulBuilder(
      builder: (context, setState) {
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(isHovered ? 4.0 : 0.0, isHovered ? -2.0 : 0.0) // Leve movimento
              ..scale(isDragging ? 1.05 : (isHovered ? 1.02 : 1.0)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  // Sincronizar URL se estiver no Web
                  String? urlPath;
                  if (page is ClientesPage) urlPath = '/clientes';
                  else if (page is ProdutosPage) urlPath = '/produtos';
                  else if (page is ServicosPage) urlPath = '/servicos';
                  else if (page is PedidosPage) urlPath = '/pedidos';
                  else if (page is VendaDiretaPage) urlPath = '/pdv';
                  else if (page is EntradaMercadoriasPage) urlPath = '/entrada-mercadorias';
                  else if (page is ContasPagarPage) urlPath = '/contas-pagar';
                  else if (page is AgendaContasPage) urlPath = '/agenda-contas';
                  else if (page is CozinhaBarPage) urlPath = '/cozinha-bar';
                  else if (page is CozinhaMesasFuncionarioPage) urlPath = '/mesas';
                  else if (page is GerenciarLinksVendedoresPage) urlPath = '/links-vendedores';
                  else if (page is VendedorDashboardPage) urlPath = '/vendedor-dashboard';
                  else if (page is FuncionariosPage) urlPath = '/funcionarios';
                  else if (page is PersonalizarLojaPage) urlPath = '/personalizar-loja';
                  else if (page is AgendaServicosPage) urlPath = '/agenda-pet';
                  else if (page is GerenciarImagensPage) urlPath = '/gerenciar-imagens';
                  else if (page is TrocasDevolucoesBuscarPage) urlPath = '/trocas-devolucoes';
                  else if (page is HistoricoVendasPage) urlPath = '/historico-vendas';

                  if (kIsWeb && urlPath != null) {
                    html_helper.updateUrl(urlPath);
                  }

                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => page),
                  );

                  // Ao retornar, volta a URL para a home (/)
                  if (kIsWeb) {
                     html_helper.updateUrl('/');
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.all(containerPadding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        (isHovered ? color.withOpacity(0.15) : const Color(0xFF1E1E2E).withOpacity(0.9)),
                        (isHovered ? const Color(0xFF1E1E2E).withOpacity(0.95) : const Color(0xFF161625).withOpacity(0.95)),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isHovered ? color : color.withOpacity(0.2),
                      width: isHovered ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isHovered ? color.withOpacity(0.2) : color.withOpacity(0.05),
                        blurRadius: isHovered ? 15 : 10,
                        spreadRadius: isHovered ? 2 : 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        padding: EdgeInsets.all(iconPadding),
                        decoration: BoxDecoration(
                          color: isHovered ? color.withOpacity(0.2) : color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isHovered ? [
                            BoxShadow(
                              color: color.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                            )
                          ] : [],
                        ),
                        child: Icon(
                          icon,
                          size: iconSize,
                          color: color,
                        ),
                      ),
                      SizedBox(width: spacing),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: subtitleFontSize,
                                  color: isHovered ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.5),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: isHovered ? 1.0 : 0.2,
                        child: Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: isHovered ? color : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
