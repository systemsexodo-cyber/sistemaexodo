import 'package:flutter/material.dart';

/// Etapa atual da abertura do aplicativo.
///
/// É preenchida pelo `main.dart` e mostrada por [BootProgresso]. Serve para o
/// app NUNCA ficar parado no splash branco sem dizer o que está acontecendo.
final ValueNotifier<String> bootStatus = ValueNotifier<String>(
  'Preparando o sistema...',
);

/// Tela desenhada imediatamente no boot (antes de ler configuração, banco,
/// etc.). Ela aparece enquanto o sistema carrega e mostra a etapa atual.
class BootProgresso extends StatelessWidget {
  final ValueNotifier<String> status;
  final String versao;

  const BootProgresso({super.key, required this.status, required this.versao});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (context, texto, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      texto,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'SISTEMA ÊXODO V$versao',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela de erro de abertura: mostra a causa em vez de deixar o app mudo no
/// splash. O texto é selecionável para o cliente copiar e mandar ao suporte.
class AberturaFalhouPage extends StatelessWidget {
  final String erro;
  final String pilha;

  const AberturaFalhouPage({
    super.key,
    required this.erro,
    required this.pilha,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 26,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'O sistema não conseguiu abrir',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tire um print desta tela e envie para o suporte. '
                  'O detalhe abaixo diz exatamente o que falhou.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        '$erro\n\n$pilha',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11,
                          height: 1.35,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
