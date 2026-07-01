import 'package:flutter/material.dart';

import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/pages/selecionar_empresa_page.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';

import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/widgets/exodo_loading.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sistema_exodo_novo/services/native_db_init_stub.dart'
    if (dart.library.io) 'package:sistema_exodo_novo/services/native_db_init.dart';
import 'package:sistema_exodo_novo/pages/loja_publica_wrapper.dart';
import 'package:sistema_exodo_novo/pages/html_helper_stub.dart'
    if (dart.library.html) 'package:sistema_exodo_novo/pages/html_helper_web.dart' as html_helper;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicialização do Banco Local Nativo se for Desktop
  NativeDbInit.initialize();
  
  // Inicialização do Supabase
  await SupabaseService.initialize();
  
  if (kIsWeb) {
    try {
      print('>>> [SISTEMA] Iniciando Boot em modo Web');
      await Hive.initFlutter();
      print('>>> ✓ Hive inicializado com sucesso no Web');
    } catch (e) {
      print('>>> [SISTEMA] Erro no Boot / Hive: $e');
    }
  } else {
     await Hive.initFlutter();
  }

  print('>>> [APLICATIVO] Iniciando Versão ${AppUpdateService.currentAppVersion} (Fix: Cache & Sync)...');
  
  if (kIsWeb) {
    // No Web, podemos tentar usar o pathUrlStrategy se necessário,
    // mas para evitar crash nativo, vamos apenas comentar ou remover 
    // até que esteja corretamente isolado.
    // usePathUrlStrategy();
  }
  
  debugPrint('>>> [SISTEMA] Sistema inicializado com Supabase');

  // Inicializa os serviços
  final dataService = DataService();
  final authService = AuthService();
  final clienteAuthService = ClienteAuthService();
  final carrinhoService = CarrinhoService();

  


  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dataService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: clienteAuthService),
        ChangeNotifierProvider.value(value: carrinhoService),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const MyApp(),
    ),
  );
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
      final String href = html_helper.getWindowOrigin(); 
      final String pathOrig = html_helper.getWindowPathname();
      final String path = pathOrig.toLowerCase();
      final String hashOrig = ""; // Simplificado para Windows
      final String hash = ""; 
      
      debugPrint('>>> [AppRouter] ANÁLISE URL:');
      debugPrint('    href: $href');
      debugPrint('    path: $pathOrig');
      
      final List<String> segmentsOrig = [];
      segmentsOrig.addAll(pathOrig.split('/').where((s) => s.isNotEmpty));
      
      String cleanHashOrig = hashOrig.replaceAll(RegExp(r'^[#!/? ]+'), '');
      if (cleanHashOrig.isNotEmpty) {
        segmentsOrig.addAll(cleanHashOrig.split('/').where((s) => s.isNotEmpty));
      }

      final List<String> segmentsLower = segmentsOrig.map((s) => s.toLowerCase()).toList();

      debugPrint('    segments: $segmentsOrig');

      if (segmentsOrig.isEmpty) {
        debugPrint('    RESULTADO: Home (sem segmentos)');
        return {
          'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': 'home', 'href': href
        };
      }

      // Detecção de Agendamento
      if (segmentsLower.contains('agendamento')) {
        int idx = segmentsLower.indexOf('agendamento');
        String? slug = (idx != -1 && idx + 1 < segmentsOrig.length) ? segmentsOrig[idx + 1] : null;
        debugPrint('    RESULTADO: Agendamento Público | Slug: $slug');
        return {
          'publico': true, 'slug': slug, 'agenda': true, 'loja': false, 'interna': null, 'href': href
        };
      }

      // Detecção de Loja
      if (segmentsLower.contains('loja') || segmentsLower.contains('shop')) {
        int idx = segmentsLower.indexOf('loja');
        if (idx == -1) idx = segmentsLower.indexOf('shop');
        String? slug = (idx != -1 && idx + 1 < segmentsOrig.length) ? segmentsOrig[idx + 1] : null;
        debugPrint('    RESULTADO: Loja Pública | Slug: $slug');
        return {
          'publico': true, 'slug': slug, 'agenda': false, 'loja': true, 'interna': null, 'href': href
        };
      }

      // Rota Interna
      final firstLower = segmentsLower[0];
      if (internos.contains(firstLower)) {
        debugPrint('    RESULTADO: Rota Interna | Rota: $firstLower');
        return {
          'publico': false, 'slug': null, 'agenda': false, 'loja': false, 'interna': firstLower, 'href': href
        };
      }

      // Fallback para Loja por Slug Direto (ex: /petshop)
      final firstOrig = segmentsOrig[0];
      debugPrint('    RESULTADO: Loja Pública por Slug Direto | Slug: $firstOrig');
      return {
        'publico': true, 'slug': firstOrig, 'agenda': false, 'loja': true, 'interna': null, 'href': href
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
    _rotaInicialCache = AppRouter.analisarUrl();
    debugPrint('>>> [MyApp] Rota inicial cacheada: $_rotaInicialCache');

    if (kIsWeb) {
      // 1. Ouvir mudanças no Hash (#)
      _hashChangeSubscription = html_helper.onWindowFocus.listen((event) {
        debugPrint('>>> [Routing] Navegação detectada');
        // Reanalisar a URL somente se a mudança veio de navegação real do browser
        _rotaInicialCache = AppRouter.analisarUrl();
        if (mounted) setState(() {});
      });

      // 2. Ouvir mudanças no Path (sem #) - Necessário para usePathUrlStrategy
      _popStateSubscription = html_helper.onWindowFocus.listen((event) {
        debugPrint('>>> [Routing] Navegação detectada');
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
    return Consumer2<AuthService, ThemeService>(
      builder: (context, authService, themeService, _) {
        // 1. USAR ROTA CACHEADA - Não recalcular a cada rebuild do Consumer!
        final rotaMap = _rotaInicialCache ?? AppRouter.analisarUrl();
        
        final bool mostrarPublico = rotaMap['publico'] ?? false;
        final String? slugEmpresa = rotaMap['slug'];
        final bool isAgendamentoRoute = rotaMap['agenda'] ?? false;
        final String? subRotaInterna = rotaMap['interna'];
        final String? codigoLink = null;

        // 2. CONFIGURAR TEMA (Baseado no ThemeService e empresa)
        final empresaCores = authService.empresaAtual;
        final config = themeService.getThemeConfig(
          AppTheme.getCoresEmpresa(empresaCores?.corPrimaria, empresaCores?.corSecundaria)['primaria'],
          AppTheme.getCoresEmpresa(empresaCores?.corPrimaria, empresaCores?.corSecundaria)['secundaria'],
        );

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
            corPrimaria: config['primaria'],
            corSecundaria: config['secundaria'],
            corFundo: config['fundo'],
            brightness: config['brightness'] ?? Brightness.dark,
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
  bool _verificandoAtualizacao = false;
  bool _baixandoAtualizacao = false;
  double _progressoAtualizacao = 0.0;
  String _versaoRemota = '';
  String _erroAtualizacao = '';

  @override
  void initState() {
    super.initState();
    _checarAtualizacoes();
  }

  Future<void> _checarAtualizacoes() async {
    if (kIsWeb) return;
    if (!Platform.isWindows) return;

    setState(() {
      _verificandoAtualizacao = true;
      _erroAtualizacao = '';
    });

    try {
      final config = await AppUpdateService.verificarAtualizacao();
      if (config != null) {
        final String downloadUrl = config['download_url'] ?? '';
        final String version = config['version'] ?? '';
        if (downloadUrl.isNotEmpty && version.isNotEmpty) {
          setState(() {
            _verificandoAtualizacao = false;
            _baixandoAtualizacao = true;
            _versaoRemota = version;
            _progressoAtualizacao = 0.0;
          });

          final success = await AppUpdateService.baixarEAplicarAtualizacao(
            downloadUrl,
            (progress) {
              if (mounted) {
                setState(() {
                  _progressoAtualizacao = progress;
                });
              }
            },
          );

          if (!success && mounted) {
            setState(() {
              _baixandoAtualizacao = false;
              _erroAtualizacao = 'Falha ao baixar ou aplicar a atualização.';
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _verificandoAtualizacao = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _verificandoAtualizacao = false;
          });
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthWrapper] Erro no fluxo de atualizacao: $e');
      if (mounted) {
        setState(() {
          _verificandoAtualizacao = false;
          _baixandoAtualizacao = false;
          _erroAtualizacao = 'Erro de conexão ao buscar atualizações.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAtualizacao) {
      return AppTheme.appBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ExodoLogo(fontSize: 60, showSubtitle: true, showPhoenix: true),
              const SizedBox(height: 48),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                  backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Buscando novas atualizações...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_baixandoAtualizacao) {
      return AppTheme.appBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ExodoLogo(fontSize: 60, showSubtitle: true, showPhoenix: true),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
                ),
                child: Text(
                  'Nova Versão Disponível: $_versaoRemota',
                  style: const TextStyle(
                    color: Color(0xFFFF9800),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Baixando atualização do sistema...',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 300,
                  height: 8,
                  child: LinearProgressIndicator(
                    value: _progressoAtualizacao,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                    backgroundColor: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(_progressoAtualizacao * 100).toStringAsFixed(0)}% concluído',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'O aplicativo será reiniciado automaticamente.',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _baixandoAtualizacao = false;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.white60, size: 16),
                label: const Text(
                  'Cancelar e Entrar',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_erroAtualizacao.isNotEmpty) {
      return AppTheme.appBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800),
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ops! Não foi possível atualizar.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _erroAtualizacao,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: _checarAtualizacoes,
                      child: const Text('Tentar Novamente'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _erroAtualizacao = '';
                        });
                      },
                      child: const Text(
                        'Continuar sem Atualizar',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

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
              if (dataService.currentEmpresaId != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              return const LoginPage();
            }

            // Se está autenticado mas não tem empresa selecionada, mostra seleção de empresa
            if (authService.temEmpresaSelecionada != true) {
              // Limpar empresa do DataService se não tiver empresa selecionada
              if (dataService.currentEmpresaId != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              // Importar SelecionarEmpresaPage aqui
              return const SelecionarEmpresaPage();
            }

            // Se está autenticado e tem empresa, definir empresa no DataService e mostrar home
            final empresaAtual = authService.empresaAtual;
            if (empresaAtual != null && dataService.currentEmpresaId != empresaAtual.id) {
              // Só dispara o setup se realmente a empresa mudou
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dataService.currentEmpresaId != empresaAtual.id) {
                  dataService.definirEmpresaAtual(empresaAtual.id);
                  dataService.setEmpresaAtual(empresaAtual);
                }
              });
              // Retornar loading enquanto o setup acontece (evita flash de tela)
              return const ExodoLoading(mensagem: 'Sincronizando empresa...');
            }
            
            // Garantir que a empresa está sincronizada sem disparar rebuild infinito
            if (empresaAtual != null && dataService.empresaAtual?.id != empresaAtual.id) {
               WidgetsBinding.instance.addPostFrameCallback((_) {
                 dataService.setEmpresaAtual(empresaAtual);
               });
            }

            // Sincronizar o usuário logado no DataService para auditoria
            if (authService.isAuthenticated && authService.usuarioAtual != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                dataService.setUsuarioAtual(authService.usuarioAtual);
              });
            }

            
            
            // SE ESTÁ TUDO OK, MOSTRA A HOME PAGE
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
