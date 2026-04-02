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
import '../services/data_service.dart';
import '../widgets/sync_status_widget.dart';

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

            // Bridge Monitor Global
            Consumer2<AuthService, DataService>(
              builder: (context, authService, dataService, _) {
                final bool isOnline = dataService.isEmpresaBridgeOnline(authService.empresaAtual?.cnpj);
                final int totalBridges = dataService.bridgeOnlineCount;
                if (totalBridges == 0 && !isOnline) return const SizedBox.shrink();
                
                return Tooltip(
                  message: isOnline 
                    ? 'Emissor NFC-e ONLINE' 
                    : '$totalBridges terminal(is) detectado(s)',
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isOnline 
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.print,
                      size: 20,
                      color: isOnline ? Colors.green : Colors.orange,
                    ),
                  ),
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
    // Inicializar locale
    
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildNavigationGrid(BuildContext context) {
    return Column(
      children: [
        // PRIMEIRA LINHA (OS PRINCIPAIS): PDV e Pedidos
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.pdv,
                child: PermissionWidget(
                  permissao: TipoPermissao.vendasVisualizar,
                  child: _buildNavButton(
                    context,
                    title: 'PDV',
                    subtitle: 'Ponto de Venda',
                    icon: Icons.point_of_sale,
                    color: const Color(0xFF00BCD4),
                    page: VendaDiretaPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.pedidos,
                child: _buildNavButton(
                  context,
                  title: 'Pedidos',
                  subtitle: 'Central de Pedidos',
                  icon: Icons.receipt_long,
                  color: const Color(0xFF9C27B0),
                  page: const PedidosPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // SEGUNDA LINHA (CADASTROS): Clientes e Produtos
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.clientes,
                child: PermissionWidget(
                  permissao: TipoPermissao.clientesVisualizar,
                  child: _buildNavButton(
                    context,
                    title: 'Clientes',
                    icon: Icons.person,
                    color: const Color(0xFF2196F3),
                    page: const ClientesPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.produtos,
                child: PermissionWidget(
                  permissao: TipoPermissao.produtosVisualizar,
                  child: _buildNavButton(
                    context,
                    title: 'Produtos',
                    icon: Icons.shopping_bag,
                    color: const Color(0xFF4CAF50),
                    page: ProdutosPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // TERCEIRA LINHA: Serviços e Funcionários (RAXADO NO MEIO)
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.servicos,
                child: _buildNavButton(
                  context,
                  title: 'Serviços',
                  icon: Icons.build,
                  color: const Color(0xFFFF9800),
                  page: ServicosPage(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.funcionarios,
                child: _buildNavButton(
                  context,
                  title: 'Funcionários',
                  subtitle: 'Vendedores',
                  icon: Icons.people,
                  color: const Color(0xFF607D8B),
                  page: const FuncionariosPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // QUARTA LINHA (OPERAÇÕES): Entrada e Caixa
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.entradaMercadorias,
                child: _buildNavButton(
                  context,
                  title: 'Entrada',
                  subtitle: 'Mercadorias',
                  icon: Icons.inventory,
                  color: const Color(0xFFE91E63),
                  page: const EntradaMercadoriasPage(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.caixa,
                child: _buildNavButton(
                  context,
                  title: 'Fluxo de Caixa',
                  subtitle: 'Entradas e Saídas',
                  icon: Icons.account_balance_wallet,
                  color: const Color(0xFF4DB6AC),
                  page: const CaixaPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // QUINTA LINHA: Contas a Pagar e Agenda
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.contasPagar,
                child: _buildNavButton(
                  context,
                  title: 'Contas a Pagar',
                  subtitle: 'Despesas',
                  icon: Icons.payment,
                  color: const Color(0xFFD32F2F),
                  page: const ContasPagarPage(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.agendaContas,
                child: _buildNavButton(
                  context,
                  title: 'Agenda',
                  subtitle: 'Contas Semanais',
                  icon: Icons.calendar_today,
                  color: const Color(0xFF1976D2),
                  page: const AgendaContasPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // SEXTA LINHA: Restaurante / Atendimento
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.cozinhaBar,
                child: PermissionWidget(
                  permissao: TipoPermissao.cozinhaVisualizar,
                  child: _buildNavButton(
                    context,
                    title: 'Cozinha e Bar',
                    subtitle: 'Pedidos',
                    icon: Icons.restaurant,
                    color: const Color(0xFFFF5722),
                    page: const CozinhaBarPage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.mesas,
                child: PermissionWidget(
                  permissao: TipoPermissao.cozinhaFuncionario,
                  child: _buildNavButton(
                    context,
                    title: 'Mesas/Comandas',
                    subtitle: 'Gerenciamento',
                    icon: Icons.table_restaurant,
                    color: const Color(0xFFFF9800),
                    page: CozinhaMesasFuncionarioPage(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // SÉTIMA LINHA: E-commerce
        Row(
          children: [
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.personalizarLoja,
                child: _buildNavButton(
                  context,
                  title: 'Personalizar',
                  subtitle: 'Loja Online',
                  icon: Icons.palette,
                  color: const Color(0xFFFF6B6B),
                  page: const PersonalizarLojaPage(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TelaAccessWidget(
                tela: TelaSistema.vendedorDashboard,
                child: _buildNavButton(
                  context,
                  title: 'Vendedor',
                  subtitle: 'Dashboard',
                  icon: Icons.dashboard_customize,
                  color: const Color(0xFF00BCD4),
                  page: const VendedorDashboardPage(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNavButton(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required Widget page,
    bool isFullWidth = false,
  }) {
    // Tamanhos reduzidos para economizar espaço
    final iconSize = isFullWidth ? 48.0 : 28.0;
    final iconPadding = isFullWidth ? 20.0 : 12.0;
    final titleFontSize = isFullWidth ? 24.0 : 15.0;
    final subtitleFontSize = isFullWidth ? 14.0 : 11.0;
    final containerPadding = isFullWidth ? 24.0 : 14.0;
    final spacing = isFullWidth ? 16.0 : 12.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 0),
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
          child: Container(
            padding: EdgeInsets.all(containerPadding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E1E2E).withOpacity(0.9),
                  const Color(0xFF161625).withOpacity(0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
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
                            color: Colors.white.withOpacity(0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.white.withOpacity(0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
