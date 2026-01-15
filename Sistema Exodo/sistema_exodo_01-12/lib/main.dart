import 'package:flutter/material.dart';

import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sistema_exodo_novo/firebase_options.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se o erro do Firebase persistir, COMENTE a inicialização abaixo
  // e use o runApp simples, como explicado anteriormente.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Inicializa os serviços antes de mostrar a UI
  final dataService = DataService();
  final authService = AuthService();
  
  await dataService.iniciarSincronizacao();
  await authService.carregarUsuarios();
  await authService.carregarEmpresas();

  // Migrar pedidos antigos que não têm número válido
  dataService.migrarPedidosSemNumero();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exodo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthWrapper(),
    );
  }
}

/// Widget que verifica autenticação e redireciona para a página correta
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // Se não está autenticado, mostra a página de login
        if (!authService.isAuthenticated) {
          return const LoginPage();
        }

        // Se está autenticado mas não tem empresa selecionada, mostra seleção
        if (!authService.temEmpresaSelecionada) {
          return const LoginPage(); // Será redirecionado para seleção de empresa após login
        }

        // Se está autenticado e tem empresa, mostra a home
        return const HomePage();
      },
    );
  }
}
