import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
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
import 'package:sistema_exodo_novo/services/app_update_service.dart';
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
import '../services/fiscal_automation_service.dart';
import '../services/bridge_manager_service.dart';
import '../services/sincronizador_manager_service.dart';
import 'motoristas_page.dart';
import 'romaneios_page.dart';


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
  bool? _wasOffline;

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
        'id': 'entregas',
        'title': 'Entregas',
        'subtitle': 'Despachos Individuais',
        'icon': Icons.local_shipping_outlined,
        'color': const Color(0xFF3F51B5),
        'page': (BuildContext context) => const EntregasPage(),
      },
      {
        'id': 'romaneios',
        'title': 'Romaneios',
        'subtitle': 'Rotas de Entrega',
        'icon': Icons.map_outlined,
        'color': const Color(0xFF009688),
        'page': (BuildContext context) => const RomaneiosPage(),
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
      await authService.logout();
      
      if (context.mounted) {
        // Redirecionamento forçado e absoluto limpando todo o histórico
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (Route<dynamic> route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você saiu do sistema. Até logo!'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExodoLogoCompact(fontSize: 28),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Text(
                  'V${AppUpdateService.currentAppVersion}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ), // Restaurado 'ê' conforme pedido
          centerTitle: true,
          actions: [
            const SyncStatusWidget(),

            // ========= BOTÕES DE TESTE (TEMPORÁRIOS) - APENAS USUÁRIO MASTER =========
            Consumer<AuthService>(
              builder: (context, auth, _) {
                final isMaster = auth.usuarioAtual?.isMaster == true || auth.usuarioAtual?.email == 'user';
                if (!isMaster) return const SizedBox.shrink();

                return Row(
                  children: [
                    _buildCapsuleActionButton(
                      icon: Icons.delete_sweep,
                      label: 'Limpar Local',
                      color: Colors.redAccent,
                      tooltip: 'TESTE: Limpar Local (Nuvem Fica)',
                      onTap: () async {
                        final dataService = Provider.of<DataService>(context, listen: false);
                        await dataService.resetLocalCacheOnly();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Local limpo! Verifique se as listas sumiram.'))
                        );
                      },
                    ),
                    _buildCapsuleActionButton(
                      icon: Icons.download_for_offline,
                      label: 'Puxar Nuvem',
                      color: Colors.greenAccent,
                      tooltip: 'TESTE: Puxar da Nuvem Agora',
                      onTap: () async {
                        final dataService = Provider.of<DataService>(context, listen: false);
                        final confirmar = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2E),
                            title: const Text('⬇️ Puxar Dados da Nuvem?', style: TextStyle(color: Colors.white)),
                            content: const Text(
                              'Atenção! Isso vai apagar o cache local do seu computador para baixar uma versão limpa da nuvem.\n\n'
                              '⚠️ Se você tiver dados criados offline (vendas, clientes, pedidos) que ainda não foram sincronizados para a nuvem, ELES SERÃO PERDIDOS.\n\n'
                              'Certifique-se de estar conectado à internet antes de prosseguir.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Sim, Puxar', style: TextStyle(color: Colors.greenAccent)),
                              ),
                            ],
                          ),
                        );

                        if (confirmar == true) {
                          try {
                            await dataService.recarregarTudoDoSupabase();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Dados puxados da nuvem!'))
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ Erro ao puxar da nuvem: $e'))
                            );
                          }
                        }
                      },
                    ),
                    _buildCapsuleActionButton(
                      icon: Icons.medical_services,
                      label: 'Restaurar Nuvem',
                      color: Colors.cyanAccent,
                      tooltip: '🚑 RESTAURAR: Enviar dados locais → Nuvem',
                      onTap: () async {
                        final dataService = Provider.of<DataService>(context, listen: false);
                        final confirmar = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2E),
                            title: const Text('🚑 Restaurar Dados na Nuvem?', style: TextStyle(color: Colors.white)),
                            content: const Text('Isso vai enviar os dados que estão no SEU COMPUTADOR para a nuvem.\n\nUse isso para recuperar dados apagados acidentalmente.', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sim, Restaurar', style: TextStyle(color: Colors.cyan))),
                            ],
                          ),
                        );
                        if (confirmar == true) {
                          try {
                            await dataService.restaurarLocalParaNuvem();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('🚑 Dados restaurados na nuvem com sucesso!'))
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('❌ Erro ao restaurar: $e'))
                            );
                          }
                        }
                      },
                    ),
                    _buildCapsuleActionButton(
                      icon: Icons.cloud_off,
                      label: 'Zerar Nuvem',
                      color: Colors.amberAccent,
                      tooltip: 'Zerar Nuvem desta Empresa (CUIDADO)',
                      onTap: () async {
                        final dataService = Provider.of<DataService>(context, listen: false);
                        // Mostrar diálogo de confirmação extra
                        final confirmar = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1E2E),
                            title: const Text('⚠️ APAGAR NUVEM?', style: TextStyle(color: Colors.white)),
                            content: const Text('Isso vai apagar TODOS os dados desta empresa no servidor. Tem certeza?', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Não', style: TextStyle(color: Colors.white54))),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sim, Apagar Tudo', style: TextStyle(color: Colors.red))),
                            ],
                          )
                        );

                        if (confirmar == true) {
                          await dataService.deletarTudoNoSupabaseDestaEmpresa();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('🔥 Nuvem limpada com sucesso!'))
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
            // ===============================================

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
    
    // Escutar alterações de conectividade no DataService para exibir alerta offline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final dataService = Provider.of<DataService>(context, listen: false);
        _wasOffline = dataService.isOffline;
        dataService.addListener(_onDataServiceChanged);
        
        // Se já inicializar offline, exibir o alerta imediatamente
        if (dataService.isOffline) {
          _mostrarAlertaOffline();
        }
      } catch (e) {
        debugPrint('>>> [HomePage] Erro ao registrar listener de conectividade: $e');
      }
    });
    
    // Verificar se o Sincronizador e o Bridge estão rodando e tentar iniciá-los se for Desktop Windows
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb && Platform.isWindows) {
        // 1. Verificar Sincronizador Nuvem
        final syncRunning = await SincronizadorManagerService.isSincronizadorRunning();
        if (!syncRunning) {
          final syncStarted = await SincronizadorManagerService.startSincronizador();
          if (!syncStarted && mounted) {
            _mostrarAlertaSincronizadorFechado();
          }
        }

        // 2. Verificar Bridge (Nuvemzinha)
        final installed = await BridgeManagerService.isBridgeInstalled();
        if (installed) {
          final running = await BridgeManagerService.isBridgeRunning();
          if (!running) {
            // Tentar iniciar automaticamente
            final started = await BridgeManagerService.startBridge();
            if (!started && mounted) {
              _mostrarAlertaNuvemFechada();
            }
          }
        } else {
          // Se não estiver instalado mas o usuário precisa da nuvemzinha
          if (mounted) {
            _mostrarAlertaNuvemNaoInstalada();
          }
        }
      }
    });

    // Verificar automação fiscal (envio mensal para contabilidade)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FiscalAutomationService.verificarEEnviar(context);
    });

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
      case 'romaneios': page = const RomaneiosPage(); urlPath = '/romaneios'; break;
      case 'motoboys': page = const MotoristasPage(); urlPath = '/motoboys'; break;
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

  String? _ultimoErroSync;

  void _onDataServiceChanged() {
    if (!mounted) return;
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final isOffline = dataService.isOffline;
      final erroSync = dataService.ultimoErroSync;
      
      if (_wasOffline == null) {
        _wasOffline = isOffline;
        if (isOffline) {
          _mostrarAlertaOffline();
        }
      } else if (_wasOffline != isOffline) {
        _wasOffline = isOffline;
        if (isOffline) {
          _mostrarAlertaOffline();
        } else {
          // Conexão voltou - mostrar alerta
          _mostrarAlertaOnline();
        }
      }

      // Alerta se o ícone da nuvenzinha der erro (transição de null/diferente para um novo erro)
      if (erroSync != null && erroSync != _ultimoErroSync) {
        _ultimoErroSync = erroSync;
        _mostrarAlertaErroSync(erroSync);
      } else if (erroSync == null) {
        _ultimoErroSync = null;
      }
    } catch (_) {}
  }

  void _mostrarAlertaErroSync(String erro) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Erro na Sincronização',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Scrollbar(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ocorreu uma falha ao tentar sincronizar os dados com a nuvem:',
                  style: TextStyle(color: Colors.white70, height: 1.4, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Text(
                    erro,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'O sistema continuará tentando sincronizar em segundo plano de forma automática.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.redAccent.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Fechar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaOffline() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // Força o clique no Ok
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Você está sem internet',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Os seus dados não serão salvos na nuvem temporariamente.\n\n'
          'Fique tranquilo! Você pode continuar trabalhando offline normalmente. '
          'Assim que a conexão for restabelecida, os seus dados locais serão sincronizados com a nuvem de forma segura.',
          style: TextStyle(color: Colors.white70, height: 1.4, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.redAccent.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Ok, entendi',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaNuvemFechada() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.orangeAccent, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Emissor NFC-e Fechado',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'O sincronizador local da nuvemzinha (NFC-e Bridge) não está respondendo.\n\n'
          'Por favor, abra o aplicativo "ExodoNfceBridge.exe" na pasta C:\\ExodoNFCe\\ ou '
          'no seu Desktop para garantir a emissão correta de notas e sincronização.',
          style: TextStyle(color: Colors.white70, height: 1.4, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final started = await BridgeManagerService.startBridge();
              if (started && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Emissor local iniciado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.blueAccent.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Tentar Iniciar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Fechar',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaNuvemNaoInstalada() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amber, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.amber, size: 28),
            SizedBox(width: 12),
            Text(
              'Sincronizador Não Instalado',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'O Emissor local NFC-e (Bridge) não foi localizado no caminho padrão.\n\n'
          '${BridgeManagerService.getInstallationInstructions()}',
          style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.amber.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Entendido',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaSincronizadorFechado() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        title: const Row(
          children: [
            Icon(Icons.sync_problem, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Sincronizador Fechado',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'O "SincronizadorNuvem.exe" não está rodando.\n\n'
          'Este serviço é indispensável para enviar e receber dados com a nuvem (Supabase).\n'
          'Deseja tentar abrir o sincronizador agora?',
          style: TextStyle(color: Colors.white70, height: 1.4, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final started = await SincronizadorManagerService.startSincronizador();
              if (started && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Sincronizador de Nuvem iniciado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.blueAccent.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Abrir Agora',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Fechar',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarAlertaOnline() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.wifi, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sua internet voltou! Sincronizando dados locais com a nuvem...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  void dispose() {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      dataService.removeListener(_onDataServiceChanged);
    } catch (_) {}
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildCapsuleActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    bool isHovered = false;
    return Tooltip(
      message: tooltip,
      child: StatefulBuilder(
        builder: (context, setState) {
          return MouseRegion(
            onEnter: (_) => setState(() => isHovered = true),
            onExit: (_) => setState(() => isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: isHovered ? color.withOpacity(0.18) : color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isHovered ? color.withOpacity(0.5) : color.withOpacity(0.2),
                  width: 1.2,
                ),
                boxShadow: isHovered
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
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
      ),
    );
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
