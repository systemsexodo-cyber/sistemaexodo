import 'package:flutter/material.dart';

import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/pages/selecionar_empresa_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sistema_exodo_novo/firebase_options.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'dart:async';
import 'package:sistema_exodo_novo/services/firebase_init_service.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  
  // Carregar dados em background (não bloqueia a UI)
  _carregarDadosEmBackground(dataService, authService);

  // Iniciar app IMEDIATAMENTE (não espera carregamento)
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dataService),
        ChangeNotifierProvider.value(value: authService),
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        // Obter cores da empresa atual
        final empresa = authService.empresaAtual;
        final cores = AppTheme.getCoresEmpresa(
          empresa?.corPrimaria,
          empresa?.corSecundaria,
        );
        
        return MaterialApp(
          title: 'Exodo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(
            corPrimaria: cores['primaria'],
            corSecundaria: cores['secundaria'],
          ),
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: const AuthWrapper(),
          // Tratamento de erros global
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
              child: child ?? const SizedBox(),
            );
          },
        );
      },
    );
  }
}

/// Widget que verifica autenticação e redireciona para a página correta
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  String _statusCarregamento = 'Inicializando...';

  @override
  void initState() {
    super.initState();
    // Aguardar apenas 300ms para mostrar a UI rapidamente
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 24),
              Text(
                _statusCarregamento,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aguarde alguns instantes...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    try {
      return Consumer2<AuthService, DataService>(
        builder: (context, authService, dataService, child) {
          try {
            // Se não está autenticado, mostra a página de login
            if (!authService.isAuthenticated) {
              // Limpar empresa do DataService se não estiver autenticado
              if (dataService.empresaIdAtual != null) {
                dataService.definirEmpresaAtual(null);
              }
              return const LoginPage();
            }

            // Se está autenticado mas não tem empresa selecionada, mostra seleção de empresa
            if (!authService.temEmpresaSelecionada) {
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
            }
            
            return const HomePage();
          } catch (e) {
            print('>>> ⚠ Erro no AuthWrapper: $e');
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
                  // Tentar novamente
                  setState(() {
                    _isLoading = false;
                  });
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
