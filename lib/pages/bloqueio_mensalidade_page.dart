import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:intl/intl.dart';

class BloqueioMensalidadePage extends StatefulWidget {
  final Map<String, dynamic> configs;
  final MotivoBloqueioEmpresa motivoBloqueio;
  const BloqueioMensalidadePage({
    super.key,
    required this.configs,
    this.motivoBloqueio = MotivoBloqueioEmpresa.inadimplente,
  });

  @override
  State<BloqueioMensalidadePage> createState() => _BloqueioMensalidadePageState();
}

class _BloqueioMensalidadePageState extends State<BloqueioMensalidadePage> {
  bool _sincronizando = false;
  bool _liberandoCortesia = false;
  String? _mensagemSync;

  // Payload Pix estático estruturado da chave celular 12996435372
  final String _pixCopiaCola = "00020101021126360014br.gov.bcb.pix0111129964353725204000053039865802BR5910Charles%20P6009Sao%20Paulo62070503***6304ED22";

  void _copiarPixCopiaCola() {
    Clipboard.setData(ClipboardData(text: _pixCopiaCola));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pix Copia e Cola copiado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _fazerLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    
    try {
      await dataService.definirEmpresaAtual(null);
      await authService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Erro ao deslogar: $e');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => LoginPage()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _darOkPagamentoMesAtual() async {
    setState(() {
      _sincronizando = true;
      _mensagemSync = 'Registrando OK de pagamento do mês...';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);

      final emp = dataService.empresaAtual ?? authService.empresaAtual ?? (authService.empresas.isNotEmpty ? authService.empresas.first : null);
      if (emp != null) {
        final agora = DateTime.now();
        final mesAtualStr = '${agora.year}-${agora.month.toString().padLeft(2, '0')}';

        final Map<String, dynamic> novasConfigs = Map<String, dynamic>.from(emp.configuracoes ?? {});
        novasConfigs['status_pagamento'] = 'pago';
        novasConfigs['bloqueado'] = false;
        novasConfigs['ultimo_mes_pago'] = mesAtualStr;

        final empAtualizada = emp.copyWith(configuracoes: novasConfigs);
        await authService.atualizarEmpresa(empAtualizada);
        dataService.setEmpresaAtual(empAtualizada);
        await dataService.resetarSimulacoesLicenca();
        authService.notificarMudancas();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ OK de pagamento do mês $mesAtualStr confirmado com sucesso! Licença liberada.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao registrar OK: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sincronizando = false;
        });
      }
    }
  }

  Future<void> _verificarStatusPagamento() async {
    setState(() {
      _sincronizando = true;
      _mensagemSync = 'Consultando liberação no servidor...';
    });

    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Reseta qualquer simulação e sincroniza dados da empresa
      await dataService.resetarSimulacoesLicenca();
      await dataService.recarregarDados(modoLeve: false);
      
      // Força recarga no AuthService se necessário
      if (authService.empresaAtual != null) {
        await authService.recarregarEmpresaAtual();
      }

      if (mounted) {
        setState(() {
          _sincronizando = false;
          _mensagemSync = 'Status atualizado!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status de licença atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sincronizando = false;
          _mensagemSync = 'Erro ao sincronizar. Tente novamente.';
        });
      }
    }
  }

  Future<void> _liberarPorUmDia() async {
    setState(() {
      _liberandoCortesia = true;
    });

    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);

      // Salva a liberação temporária local por mais 1 dia
      final dataAmanha = DateTime.now().add(const Duration(days: 1));
      await dataService.storage.salvarLiberacaoTemporaria(dataAmanha.toIso8601String());
      
      // Atualiza a liberação provisória em tempo de execução no DataService
      await dataService.carregarLiberacaoProvisoria();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Acesso liberado temporariamente até ${DateFormat('dd/MM/yyyy HH:mm').format(dataAmanha)}'),
            backgroundColor: Colors.blueAccent,
          ),
        );
        // Notifica e redesenha a tela de rotas
        authService.notificarMudancas();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao liberar cortesia: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _liberandoCortesia = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    final email = usuarioAtual?.email.toLowerCase() ?? '';
    final isMaster = usuarioAtual != null && (email == 'user' || email == 'admin' || email == 'suporte');

    final dataCobrancaStr = widget.configs['data_cobranca'] ?? widget.configs['dataCobranca'];
    String vencimentoFormatado = 'Não Informado';
    if (dataCobrancaStr != null) {
      final date = DateTime.tryParse(dataCobrancaStr.toString());
      if (date != null) {
        vencimentoFormatado = DateFormat('dd/MM/yyyy').format(date);
      }
    }

    // Gerando URL do QR Code da API qrserver passando o payload do Pix
    final String qrCodeUrl = "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(_pixCopiaCola)}";

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            tooltip: 'Sair e trocar de conta',
            onPressed: _fazerLogout,
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: _fazerLogout,
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Sair da Conta', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 32.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.12),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExodoLogo(fontSize: 40, showSubtitle: true),
                  const SizedBox(height: 16),
                  
                  // Icone de Alerta Vermelho
                  Builder(
                    builder: (context) {
                      IconData iconData = Icons.lock_clock_outlined;
                      String titulo = 'Acesso Bloqueado';
                      String mensagem = 'A mensalidade do sistema está pendente. Realize o pagamento via Pix abaixo para liberar o seu acesso.';

                      if (widget.motivoBloqueio == MotivoBloqueioEmpresa.excessoDiasOffline) {
                        iconData = Icons.wifi_off_rounded;
                        titulo = 'Sincronização Offline Necessária';
                        mensagem = 'O sistema esteve sem conexão com a internet por mais de 5 dias. Conecte-se à internet para sincronizar os dados e validar sua licença.';
                      } else if (widget.motivoBloqueio == MotivoBloqueioEmpresa.relogioAdulterado) {
                        iconData = Icons.access_time_filled_rounded;
                        titulo = 'Data do Computador Incorreta';
                        mensagem = 'Detectamos que a data ou horário do sistema foi alterado. Por favor, ajuste o relógio do dispositivo para o horário correto e conecte-se à internet.';
                      }

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              iconData,
                              color: Colors.redAccent,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            titulo,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            mensagem,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Info Box de Vencimento
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF161624) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Data de Vencimento:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        Text(
                          vencimentoFormatado,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Box do Pix com QR Code
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.withOpacity(0.25)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.pix_rounded, color: Colors.green, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'PAGAR COM PIX',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Exibição do QR Code
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              qrCodeUrl,
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  width: 180,
                                  height: 180,
                                  child: Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 180,
                                  height: 180,
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.wifi_off_rounded, color: Colors.black38, size: 36),
                                        SizedBox(height: 8),
                                        Text('Erro ao carregar QR Code', style: TextStyle(color: Colors.black54, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Botão de Copiar Pix
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _copiarPixCopiaCola,
                            icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                            label: const Text(
                              'COPIAR PIX COPIA E COLA',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Ações de Liberação (APENAS PARA USUÁRIO MASTER / SUPORTE)
                  if (isMaster) ...[
                    // Botão de Dar OK de Pagamento do Mês Atual
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: _sincronizando ? null : _darOkPagamentoMesAtual,
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text(
                          '✅ DAR OK DE PAGAMENTO (LIBERAR MÊS ATUAL)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Botão de Verificar Status de Pagamento
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _sincronizando ? null : _verificarStatusPagamento,
                      child: _sincronizando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'VERIFICAR SE JÁ FOI LIBERADO',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                    ),
                  ),
                  if (_mensagemSync != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _mensagemSync!,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  
                  if (isMaster) ...[
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 16),
                    
                    // Botão Liberar por mais 1 Dia (Cortesia)
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _liberandoCortesia ? null : _liberarPorUmDia,
                        icon: const Icon(Icons.av_timer_rounded, color: Colors.white, size: 18),
                        label: _liberandoCortesia
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'LIBERAR POR MAIS 1 DIA (CORTESIA)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
