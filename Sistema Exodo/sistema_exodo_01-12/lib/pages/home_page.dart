import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/clientes_page.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'produtos_page.dart';
import 'servicos_page.dart';
import 'pedidos_page.dart';
import 'venda_direta_page.dart';
import 'entrada_mercadorias_page.dart';
import 'contas_pagar_page.dart';
import 'agenda_contas_page.dart';
import 'dashboard_page.dart';
// import 'ordens_servico_page.dart';

// Import condicional para Web
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
          title: const ExodoLogoCompact(fontSize: 28),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          actions: [
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
            IconButton(
              icon: const Icon(Icons.calendar_today, color: Colors.blue),
              tooltip: 'Agenda de Contas',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AgendaContasPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.payment, color: Colors.red),
              tooltip: 'Contas a Pagar',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ContasPagarPage()),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo principal
                  const SizedBox(height: 20),
                  const ExodoLogo(
                    fontSize: 64,
                    showSubtitle: true,
                  ),
                  const SizedBox(height: 40),
                  
                  // Grid de botões de navegação
                  _buildNavigationGrid(context),
                ],
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
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildNavigationGrid(BuildContext context) {
    return Column(
      children: [
        // Primeira linha: Clientes e Produtos
        Row(
          children: [
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Clientes',
                icon: Icons.person,
                color: const Color(0xFF2196F3),
                page: const ClientesPage(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Produtos',
                icon: Icons.shopping_bag,
                color: const Color(0xFF4CAF50),
                page: ProdutosPage(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Segunda linha: Serviços e Pedidos
        Row(
          children: [
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Serviços',
                icon: Icons.build,
                color: const Color(0xFFFF9800),
                page: ServicosPage(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Pedidos',
                icon: Icons.receipt_long,
                color: const Color(0xFF9C27B0),
                page: const PedidosPage(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Terceira linha: Entrada de Mercadorias e PDV
        Row(
          children: [
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Entrada',
                subtitle: 'Mercadorias',
                icon: Icons.inventory,
                color: const Color(0xFFE91E63),
                page: const EntradaMercadoriasPage(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildNavButton(
                context,
                title: 'PDV',
                subtitle: 'Ponto de Venda',
                icon: Icons.point_of_sale,
                color: const Color(0xFF00BCD4),
                page: VendaDiretaPage(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Quarta linha: Contas a Pagar
        Row(
          children: [
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Contas a Pagar',
                subtitle: 'Despesas e Pagamentos',
                icon: Icons.payment,
                color: const Color(0xFFD32F2F),
                page: const ContasPagarPage(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildNavButton(
                context,
                title: 'Agenda',
                subtitle: 'Contas da Semana',
                icon: Icons.calendar_today,
                color: const Color(0xFF1976D2),
                page: const AgendaContasPage(),
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
    // Tamanhos maiores para o botão PDV
    final iconSize = isFullWidth ? 60.0 : 40.0;
    final iconPadding = isFullWidth ? 24.0 : 16.0;
    final titleFontSize = isFullWidth ? 28.0 : 18.0;
    final subtitleFontSize = isFullWidth ? 16.0 : 12.0;
    final containerPadding = isFullWidth ? 32.0 : 24.0;
    final spacing = isFullWidth ? 20.0 : 16.0;

    return Container(
      margin: EdgeInsets.only(bottom: isFullWidth ? 0 : 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.all(containerPadding),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E).withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: isFullWidth ? 2.0 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: isFullWidth ? 12 : 8,
                  offset: Offset(0, isFullWidth ? 6 : 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: color,
                  ),
                ),
                SizedBox(height: spacing),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  SizedBox(height: isFullWidth ? 8 : 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: Colors.white.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                SizedBox(height: isFullWidth ? 12 : 8),
                Icon(
                  Icons.arrow_forward_ios,
                  size: isFullWidth ? 20 : 16,
                  color: color.withOpacity(0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
