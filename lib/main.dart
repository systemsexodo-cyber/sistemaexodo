import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/pages/selecionar_empresa_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sistema_exodo_novo/firebase_options.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';

import 'dart:async';
import 'package:sistema_exodo_novo/services/firebase_init_service.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/widgets/exodo_loading.dart';
import 'package:sistema_exodo_novo/pages/loja_publica_wrapper.dart';
import 'package:flutter/foundation.dart';
import 'dart:html' as html show window;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kIsWeb) {
    try {
      print('>>> [SISTEMA] Iniciando Boot em modo Web');
    } catch (e) {
      print('>>> [SISTEMA] Erro no Boot: $e');
    }
  }

  print('>>> [APLICATIVO] Iniciando Versão 1.0.8 (Fix: Cache & Sync)...');
  
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  // Inicializar Firebase com timeout curto e tratamento de erro
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print('>>> ⚠ Timeout ao inicializar Firebase (5s)');
        throw TimeoutException('Firebase timeout');
      },
    );
    print('>>> ✓ Firebase inicializado com sucesso');
    
    // Inicializar estrutura do Firebase em background (não bloqueia)
    FirebaseInitService.inicializarEstrutura().catchError((e) {
      print('>>> ⚠ Erro ao inicializar estrutura do Firebase: $e');
    });
  } catch (e) {
    print('>>> ⚠ Erro ao inicializar Firebase: $e');
    // Continua mesmo se o Firebase falhar - app funciona offline
  }

  // Inicializa os serviços
  final dataService = DataService();
  final authService = AuthService();
  final clienteAuthService = ClienteAuthService();
  final carrinhoService = CarrinhoService();

  
  // Carregar dados em background (não bloqueia a UI)
  _carregarDadosEmBackground(dataService, authService);

  // Iniciar app IMEDIATAMENTE (não espera carregamento)
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dataService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: clienteAuthService),
        ChangeNotifierProvider.value(value: carrinhoService),

      ],
      child: const MyApp(),
    ),
  );
}

/// Carrega dados em background sem bloquear a UI
void _carregarDadosEmBackground(DataService dataService, AuthService authService) {
  // Executa em background
  Future.microtask(() async {
    try {
      // Inicializar sincronização com timeout curto
      await dataService.iniciarSincronizacao().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('>>> ⚠ Timeout na sincronização (10s) - continuando offline...');
        },
      );
    } catch (e) {
      print('>>> ⚠ Erro ao sincronizar: $e - continuando offline...');
    }
    
    try {
      await authService.carregarUsuarios().timeout(
        const Duration(seconds: 3),
        onTimeout: () => print('>>> ⚠ Timeout ao carregar usuários'),
      );
      await authService.carregarEmpresas().timeout(
        const Duration(seconds: 3),
        onTimeout: () => print('>>> ⚠ Timeout ao carregar empresas'),
      );
    } catch (e) {
      print('>>> ⚠ Erro ao carregar usuários/empresas: $e');
    }

    // Migrar pedidos em background
    try {
      dataService.migrarPedidosSemNumero();
    } catch (e) {
      print('>>> ⚠ Erro ao migrar pedidos: $e');
    }
  });
}

class AppRouter {
  static const internos = {
    'login', 'home', 'dashboard', 'admin', 'auth', 'selecionar-empresa', 'debug',
    'clientes', 'produtos', 'servicos', 'servico', 'pedidos', 'venda-direta', 'pdv',
    'entrada-mercadorias', 'contas-pagar', 'agenda-contas', 'cozinha-bar',
    'mesas', 'links-vendedores', 'vendedor-dashboard', 'funcionarios',
    'personalizar-loja', 'agenda-pet', 'gerenciar-imagens', 'caixa',
    'comissoes', 'entregas', 'historico-vendas', 'historico-operacoes',
    'gerenciar-usuarios', 'trocas-devolucoes', 'configuracoes-agenda',
    'taxas-entrega', 'empresas', 'gerenciar-permissoes'
  };

  static Map<String, dynamic> analisarUrl() {
    if (!kIsWeb) return {'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': null};
    
    try {
      final String href = html.window.location.href.toLowerCase();
      final String path = (html.window.location.pathname ?? '').toLowerCase();
      final String hash = html.window.location.hash.toLowerCase();
      
      debugPrint('>>> [AppRouter] ANÁLISE URL:');
      debugPrint('    href: $href');
      debugPrint('    path: $path');
      debugPrint('    hash: $hash');
      
      final List<String> segments = [];
      segments.addAll(path.split('/').where((s) => s.isNotEmpty));
      
      String cleanHash = hash.replaceAll(RegExp(r'^[#!/? ]+'), '');
      if (cleanHash.isNotEmpty) {
        segments.addAll(cleanHash.split('/').where((s) => s.isNotEmpty));
      }

      debugPrint('    segments: $segments');

      if (segments.isEmpty) {
        debugPrint('    RESULTADO: Home (sem segmentos)');
        return {
          'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': 'home', 'href': href
        };
      }

      // Detecção de Agendamento
      if (segments.contains('agendamento')) {
        int idx = segments.indexOf('agendamento');
        String? slug = (idx != -1 && idx + 1 < segments.length) ? segments[idx + 1] : null;
        debugPrint('    RESULTADO: Agendamento Público | Slug: $slug');
        return {
          'publico': true, 'slug': slug, 'agenda': true, 'loja': false, 'interna': null, 'href': href
        };
      }

      // Detecção de Loja
      if (segments.contains('loja') || segments.contains('shop')) {
        int idx = segments.indexOf('loja');
        if (idx == -1) idx = segments.indexOf('shop');
        String? slug = (idx != -1 && idx + 1 < segments.length) ? segments[idx + 1] : null;
        debugPrint('    RESULTADO: Loja Pública | Slug: $slug');
        return {
          'publico': true, 'slug': slug, 'agenda': false, 'loja': true, 'interna': null, 'href': href
        };
      }

      // Rota Interna
      final first = segments[0];
      if (internos.contains(first)) {
        debugPrint('    RESULTADO: Rota Interna | Rota: $first');
        return {
          'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': first, 'href': href
        };
      }

      // Fallback para Loja por Slug Direto (ex: /petshop)
      debugPrint('    RESULTADO: Loja Pública por Slug Direto | Slug: $first');
      return {
        'publico': true, 'slug': first, 'agenda': false, 'loja': true, 'interna': null, 'href': href
      };
    } catch (e) {
      debugPrint('>>> [AppRouter] Erro ao analisar URL: $e');
      return {'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': null};
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _hashChangeSubscription;
  StreamSubscription? _popStateSubscription;

  // CACHE da análise de rota inicial - evita recalcular a cada rebuild do Consumer
  Map<String, dynamic>? _rotaInicialCache;

  @override
  void initState() {
    super.initState();
    
    // Analisar a rota APENAS UMA VEZ no início
    if (kIsWeb) {
      _rotaInicialCache = AppRouter.analisarUrl();
      debugPrint('>>> [MyApp] Rota inicial cacheada: $_rotaInicialCache');
    }

    if (kIsWeb) {
      // 1. Ouvir mudanças no Hash (#)
      _hashChangeSubscription = html.window.onHashChange.listen((event) {
        debugPrint('>>> [Routing] Hash alterado: ${html.window.location.hash}');
        // Reanalisar a URL somente se a mudança veio de navegação real do browser
        _rotaInicialCache = AppRouter.analisarUrl();
        if (mounted) setState(() {});
      });

      // 2. Ouvir mudanças no Path (sem #) - Necessário para usePathUrlStrategy
      _popStateSubscription = html.window.onPopState.listen((event) {
        debugPrint('>>> [Routing] PopState alterado: ${html.window.location.pathname}');
        // Reanalisar a URL somente quando o usuário navega pelo browser (back/forward)
        _rotaInicialCache = AppRouter.analisarUrl();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _hashChangeSubscription?.cancel();
    _popStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        // 1. USAR ROTA CACHEADA - Não recalcular a cada rebuild do Consumer!
        final rotaMap = _rotaInicialCache ?? AppRouter.analisarUrl();
        
        final bool mostrarPublico = rotaMap['publico'] ?? false;
        final String? slugEmpresa = rotaMap['slug'];
        final bool isAgendamentoRoute = rotaMap['agenda'] ?? false;
        final String? subRotaInterna = rotaMap['interna'];
        final String? codigoLink = null;

        // 2. CONFIGURAR TEMA (Baseado na empresa se disponível)
        final empresaCores = authService.empresaAtual;
        final cores = AppTheme.getCoresEmpresa(empresaCores?.corPrimaria, empresaCores?.corSecundaria);

        // LOG DE DIAGNÓSTICO FINAL
        debugPrint('>>> [SISTEMA-ROTA] Montando MaterialApp (cache):');
        debugPrint('    Público: $mostrarPublico');
        debugPrint('    Slug: $slugEmpresa');
        debugPrint('    Agendamento: $isAgendamentoRoute');
        debugPrint('    Rota Interna: $subRotaInterna');

        return MaterialApp(
          title: isAgendamentoRoute ? 'Agendamento Online' : 'Exodo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(
            corPrimaria: cores['primaria'],
            corSecundaria: cores['secundaria'],
          ),
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: mostrarPublico
              ? LojaPublicaWrapper(
                  codigoLink: codigoLink ?? '',
                  slugEmpresa: slugEmpresa,
                  forceAgendamento: isAgendamentoRoute,
                )
              : AuthWrapper(subRota: subRotaInterna),
          builder: (context, child) {
            if (child == null) return const Center(child: CircularProgressIndicator());
            
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
              child: child,
            );
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final String? subRota;
  const AuthWrapper({super.key, this.subRota});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final rotaMap = AppRouter.analisarUrl();
      if (rotaMap['publico'] == true) {
        return LojaPublicaWrapper(
          codigoLink: '',
          slugEmpresa: rotaMap['slug'],
          forceAgendamento: rotaMap['agenda'] == true,
        );
      }
    }

    final String? rotaInicial = widget.subRota;

    try {
      return Consumer2<AuthService, DataService>(
        builder: (context, authService, dataService, child) {
          try {
            // Se o AuthService está carregando dados iniciais, mostrar loading
            if (authService.isCarregandoDados == true) {
              return const ExodoLoading(mensagem: 'Carregando dados de autenticação...');
            }
            
            // Se o DataService está carregando, mostrar loading
            if (dataService.isLoading == true) {
              return ExodoLoading(mensagem: dataService.mensagemLoading);
            }
            
            // Se não está autenticado, mostra a página de login
            if (authService.isAuthenticated != true) {
              // Limpar empresa do DataService se não estiver autenticado
              if (dataService.empresaIdAtual != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              return const LoginPage();
            }

            // Se está autenticado mas não tem empresa selecionada, mostra seleção de empresa
            if (authService.temEmpresaSelecionada != true) {
              // Limpar empresa do DataService se não tiver empresa selecionada
              if (dataService.empresaIdAtual != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              // Importar SelecionarEmpresaPage aqui
              return const SelecionarEmpresaPage();
            }

            // Se está autenticado e tem empresa, definir empresa no DataService e mostrar home
            final empresaAtual = authService.empresaAtual;
            if (empresaAtual != null && dataService.empresaIdAtual != empresaAtual.id) {
              // Definir empresa no DataService de forma assíncrona
              Future.microtask(() {
                 dataService.definirEmpresaAtual(empresaAtual.id);
                 dataService.setEmpresaAtual(empresaAtual);
              });
              // Mostrar loading enquanto carrega
              return ExodoLoading(mensagem: 'Carregando dados da empresa...');
            }
            
            // Garantir que a empresa está sempre atualizada no DataService
            if (empresaAtual != null && dataService.empresaAtual != empresaAtual) {
              Future.microtask(() => dataService.setEmpresaAtual(empresaAtual));
            }

            
            return HomePage(initialPage: rotaInicial);
          } catch (e, stackTrace) {
            print('>>> ⚠ Erro no AuthWrapper: $e');
            print('>>> StackTrace: $stackTrace');
            // Em caso de erro, mostra login
            return const LoginPage();
          }
        },
      );
    } catch (e, stackTrace) {
      print('>>> ⚠ ERRO CRÍTICO no AuthWrapper: $e');
      print('>>> StackTrace: $stackTrace');
      // Sempre mostra algo, nunca tela branca
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Erro ao carregar',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // Tentar novamente - recarregar a página
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const AuthWrapper()),
                  );
                },
                child: const Text('Tentar Novamente', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      );
    }
  }
}
