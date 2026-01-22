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

// VARIÁVEIS GLOBAIS PARA CAPTURAR A URL DE ENTRADA (Impedir limpeza do Flutter Web)
bool _entradaPublica = false;
bool _entradaAgenda = false;
String? _entradaSlug;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // CAPTURA IMEDIATA DA URL (Ponto mais crítico)
  if (kIsWeb) {
    try {
      final String href = html.window.location.href.toLowerCase();
      final String path = (html.window.location.pathname ?? '').toLowerCase();
      final String hash = html.window.location.hash.toLowerCase();
      
      print('>>> [SISTEMA] Captura de entrada: $href');
      
      _entradaAgenda = href.contains('agendamento');
      bool isLoja = href.contains('loja') || href.contains('shop') || href.contains('ecommerce');
      _entradaPublica = _entradaAgenda || isLoja;

      final List<String> segments = [];
      segments.addAll(path.split('/').where((s) => s.isNotEmpty));
      String cleanHash = hash.replaceAll(RegExp(r'^[#!/? ]+'), '');
      if (cleanHash.isNotEmpty) segments.addAll(cleanHash.split('/').where((s) => s.isNotEmpty));

      if (_entradaAgenda) {
        int idx = segments.indexOf('agendamento');
        if (idx != -1 && idx + 1 < segments.length) _entradaSlug = segments[idx + 1];
        else if (segments.isNotEmpty) _entradaSlug = segments.firstWhere((s) => s != 'agendamento', orElse: () => segments[0]);
      } else if (isLoja) {
        int idx = segments.indexOf('loja');
        if (idx == -1) idx = segments.indexOf('shop');
        if (idx != -1 && idx + 1 < segments.length) _entradaSlug = segments[idx + 1];
        else if (segments.isNotEmpty) _entradaSlug = segments.firstWhere((s) => s != 'loja' && s != 'shop', orElse: () => segments[0]);
      } else if (segments.isNotEmpty) {
        const internos = {'login', 'home', 'dashboard', 'admin', 'auth', 'selecionar-empresa'};
        if (!internos.contains(segments[0])) {
          isLoja = true;
          _entradaPublica = true;
          _entradaSlug = segments[0];
        }
      }
      print('>>> [SISTEMA] Rota detectada no BOOT: Publica=$_entradaPublica | Slug=$_entradaSlug');
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

/// Utilitário para centralizar a detecção de rotas
class AppRouter {
  static Map<String, dynamic> analisarUrl() {
    if (!kIsWeb) return {'publico': false, 'slug': null, 'agenda': false, 'loja': false};
    
    try {
      final rawHref = html.window.location.href.toLowerCase();
      final rawPath = (html.window.location.pathname ?? '').toLowerCase();
      final rawHash = html.window.location.hash.toLowerCase();
      
      // Detecção baseada no PATH ou HASH
      final String fullPath = "$rawPath$rawHash";
      
      bool isAgenda = fullPath.contains('agendamento');
      bool isLoja = fullPath.contains('loja') || fullPath.contains('shop');
      String? slug;

      final List<String> segments = [];
      segments.addAll(rawPath.split('/').where((s) => s.isNotEmpty));
      String cleanHash = rawHash.replaceAll(RegExp(r'^[#!/? ]+'), '');
      if (cleanHash.isNotEmpty) segments.addAll(cleanHash.split('/').where((s) => s.isNotEmpty));

      if (isAgenda) {
        int idx = segments.indexOf('agendamento');
        if (idx != -1 && idx + 1 < segments.length) slug = segments[idx + 1];
        else if (segments.isNotEmpty) slug = segments.firstWhere((s) => s != 'agendamento', orElse: () => segments[0]);
      } else if (isLoja) {
        int idx = segments.indexOf('loja');
        if (idx == -1) idx = segments.indexOf('shop');
        if (idx != -1 && idx + 1 < segments.length) slug = segments[idx + 1];
        else if (segments.isNotEmpty) slug = segments.firstWhere((s) => s != 'loja' && s != 'shop', orElse: () => segments[0]);
      } else if (segments.isNotEmpty) {
        // Se tem apenas um segmento e não é rota interna, tratar como LOJA por padrão
        // (Isso torna os links individuais: /loja/slug vs /agendamento/slug)
        final first = segments[0];
        const internos = {
          'login', 'home', 'dashboard', 'admin', 'auth', 'selecionar-empresa', 'debug',
          'clientes', 'produtos', 'servicos', 'pedidos', 'venda-direta', 'pdv',
          'entrada-mercadorias', 'contas-pagar', 'agenda-contas', 'cozinha-bar',
          'mesas', 'links-vendedores', 'vendedor-dashboard', 'funcionarios',
          'personalizar-loja', 'agenda-pet', 'gerenciar-imagens'
        };
        
        if (internos.contains(first)) {
           return {
            'publico': false,
            'slug': null,
            'agenda': false,
            'loja': false,
            'interna': first,
            'href': rawHref
          };
        } else {
          isLoja = true; // Root slug agora abre a loja
          slug = first;
        }
      }

      final res = {
        'publico': isAgenda || isLoja,
        'slug': slug,
        'agenda': isAgenda,
        'loja': isLoja,
        'interna': null,
        'href': rawHref
      };
      print('>>> [AppRouter] Analise: $res');
      return res;
    } catch (e) {
      print('>>> [AppRouter] Erro: $e');
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

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // 1. Ouvir mudanças no Hash (#)
      _hashChangeSubscription = html.window.onHashChange.listen((event) {
        debugPrint('>>> [Routing] Hash alterado: ${html.window.location.hash}');
        if (mounted) setState(() {});
      });

      // 2. Ouvir mudanças no Path (sem #) - Necessário para usePathUrlStrategy
      _popStateSubscription = html.window.onPopState.listen((event) {
        debugPrint('>>> [Routing] PopState alterado: ${html.window.location.pathname}');
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
        // 1. ANALISAR ROTA ATUAL DYNAMICAMENTE
        final rotaMap = AppRouter.analisarUrl();
        
        final bool mostrarPublico = rotaMap['publico'] || _entradaPublica;
        final String? slugEmpresa = rotaMap['slug'] ?? _entradaSlug;
        final bool isAgendamentoRoute = rotaMap['agenda'] || _entradaAgenda;
        final String? subRotaInterna = rotaMap['interna'];
        final String? codigoLink = null;

        // 2. CONFIGURAR TEMA (Baseado na empresa se disponível)
        final empresaCores = authService.empresaAtual;
        final cores = AppTheme.getCoresEmpresa(empresaCores?.corPrimaria, empresaCores?.corSecundaria);

        // LOG DE DIAGNÓSTICO FINAL
        if (kDebugMode) {
          print('>>> [SISTEMA-ROTA] Montando MaterialApp -> Público: $mostrarPublico');
        }

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
      if (_entradaPublica) {
        print('>>> [AuthWrapper] BYPASS SEGURO: Usando dados de Boot');
        return LojaPublicaWrapper(
          codigoLink: '',
          slugEmpresa: _entradaSlug,
          forceAgendamento: _entradaAgenda,
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
                dataService.definirEmpresaAtual(null);
              }
              return const LoginPage();
            }

            // Se está autenticado mas não tem empresa selecionada, mostra seleção de empresa
            if (authService.temEmpresaSelecionada != true) {
              // Limpar empresa do DataService se não tiver empresa selecionada
              if (dataService.empresaIdAtual != null) {
                dataService.definirEmpresaAtual(null);
              }
              // Importar SelecionarEmpresaPage aqui
              return const SelecionarEmpresaPage();
            }

            // Se está autenticado e tem empresa, definir empresa no DataService e mostrar home
            final empresaAtual = authService.empresaAtual;
            if (empresaAtual != null && dataService.empresaIdAtual != empresaAtual.id) {
              // Definir empresa no DataService (isso recarrega os dados)
              dataService.definirEmpresaAtual(empresaAtual.id);
              // Passar empresa completa para WhatsApp e outras funcionalidades
              dataService.setEmpresaAtual(empresaAtual);
              // Mostrar loading enquanto carrega
              return ExodoLoading(mensagem: 'Carregando dados da empresa...');
            }
            
            // Garantir que a empresa está sempre atualizada no DataService
            if (empresaAtual != null && dataService.empresaAtual != empresaAtual) {
              dataService.setEmpresaAtual(empresaAtual);
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
