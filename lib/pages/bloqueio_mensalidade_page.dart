import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/historico_mensalidade.dart';
import 'package:sistema_exodo_novo/services/mercado_pago_mensalidade_service.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/pages/selecionar_empresa_page.dart';
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
  State<BloqueioMensalidadePage> createState() =>
      _BloqueioMensalidadePageState();
}

class _BloqueioMensalidadePageState extends State<BloqueioMensalidadePage> {
  bool _sincronizando = false;
  bool _liberandoCortesia = false;
  String? _mensagemSync;
  final _codigoOfflineController = TextEditingController();
  final _mercadoPago = MercadoPagoMensalidadeService();
  String? _erroCodigoOffline;
  bool _criandoPix = false;
  bool _checandoPix = false;
  PixMensalidade? _pixMensalidade;
  String? _erroPix;
  Timer? _timerConfirmacaoPix;

  void _copiarPixCopiaCola() {
    final codigo = _pixMensalidade?.codigoCopiaCola;
    if (codigo == null) return;
    Clipboard.setData(ClipboardData(text: codigo));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código Pix do Mercado Pago copiado.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _emailValido(String? valor) {
    final email = (valor ?? '').trim();
    if (email.isEmpty || !_emailRegex.hasMatch(email)) return null;
    return email;
  }

  Future<String?> _resolverEmailPagador(Empresa empresa) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final configs = empresa.configuracoes ?? const <String, dynamic>{};
    final candidatos = <String?>[
      authService.usuarioAtual?.email,
      empresa.email,
      configs['email_pagador']?.toString(),
      configs['email']?.toString(),
      empresa.emailContabilidade,
    ];
    for (final candidato in candidatos) {
      final email = _emailValido(candidato);
      if (email != null) return email;
    }
    return _solicitarEmailPagador();
  }

  Future<String?> _solicitarEmailPagador() async {
    final controller = TextEditingController();
    String? erro;
    final email = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text(
            'E-mail para a cobrança',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Não encontrei um e-mail cadastrado. Informe um e-mail '
                'para gerar o Pix da mensalidade.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'E-mail',
                  hintText: 'seuemail@exemplo.com',
                  errorText: erro,
                ),
                onSubmitted: (_) {
                  final valor = controller.text.trim();
                  if (!_emailRegex.hasMatch(valor)) {
                    setDialogState(() => erro = 'Informe um e-mail válido.');
                    return;
                  }
                  Navigator.pop(dialogContext, valor);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                final valor = controller.text.trim();
                if (!_emailRegex.hasMatch(valor)) {
                  setDialogState(() => erro = 'Informe um e-mail válido.');
                  return;
                }
                Navigator.pop(dialogContext, valor);
              },
              child: const Text(
                'GERAR PIX',
                style: TextStyle(color: Colors.greenAccent),
              ),
            ),
          ],
        ),
      ),
    );
    return email;
  }

  Future<void> _gerarPixMensalidade() async {
    setState(() {
      _criandoPix = true;
      _erroPix = null;
      _pixMensalidade = null;
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresa = authService.empresaAtual ?? dataService.empresaAtual;
      if (empresa == null) {
        throw Exception('Não encontrei a empresa desta cobrança.');
      }
      final email = await _resolverEmailPagador(empresa);
      if (email == null) {
        throw Exception('Informe um e-mail válido para gerar a cobrança.');
      }
      final pix = await _mercadoPago.criarPix(
        empresaId: empresa.id,
        emailPagador: email,
      );
      if (!mounted) return;
      setState(() => _pixMensalidade = pix);
      _iniciarVerificacaoAutomatica(empresa.id, pix.pagamentoId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erroPix = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _criandoPix = false);
    }
  }

  void _iniciarVerificacaoAutomatica(String empresaId, String pagamentoId) {
    _timerConfirmacaoPix?.cancel();
    var tentativas = 0;
    _timerConfirmacaoPix = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      if (!mounted || _checandoPix) return;
      _checandoPix = true;
      tentativas++;
      try {
        final status = await _mercadoPago.pagamentoAprovado(
          empresaId: empresaId,
          pagamentoId: pagamentoId,
        );
        if (status.aprovado && mounted) {
          timer.cancel();
          await _liberarAposPagamento(
            pix: _pixMensalidade!,
            pagoEm: status.pagoEm,
          );
        }
      } catch (e) {
        debugPrint('Erro ao confirmar pagamento Pix: $e');
      } finally {
        _checandoPix = false;
      }
      if (tentativas >= 30) timer.cancel();
    });
  }

  Future<void> _liberarAposPagamento({
    required PixMensalidade pix,
    required String? pagoEm,
  }) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual ?? authService.empresaAtual;
    if (empresa == null) {
      setState(() {
        _sincronizando = false;
        _mensagemSync =
            'Pagamento confirmado, mas não encontrei a empresa '
            'para atualizar a licença. Saia e entre novamente.';
      });
      return;
    }

    setState(() {
      _sincronizando = true;
      _mensagemSync = 'Pagamento confirmado. Liberando o sistema...';
    });
    try {
      final configs =
          HistoricoMensalidade.registrar(
              Map<String, dynamic>.from(empresa.configuracoes ?? {}),
              competencia: pix.mesReferencia,
              valor: pix.valor,
              pagamentoId: pix.pagamentoId,
              pagoEm: DateTime.tryParse(pagoEm ?? ''),
            )
            ..['status_pagamento'] = 'pago'
            ..['bloqueado'] = false
            ..['ultimo_mes_pago'] = pix.mesReferencia
            ..['mercado_pago_payment_id'] = pix.pagamentoId
            ..['mercado_pago_pago_em'] =
                pagoEm ?? DateTime.now().toUtc().toIso8601String();
      final atualizada = empresa.copyWith(configuracoes: configs);
      await authService.atualizarEmpresa(atualizada);
      dataService.setEmpresaAtual(atualizada);
      await dataService.storage.salvarConfiguracoesMensalidadeLocal(
        atualizada.id,
        configs,
      );
      await dataService.resetarSimulacoesLicenca();
      authService.notificarMudancas();
      if (!mounted) return;
      _timerConfirmacaoPix?.cancel();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SelecionarEmpresaPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sincronizando = false;
        _mensagemSync =
            'Pagamento confirmado, mas não consegui atualizar '
            'a licença local: $e';
      });
    }
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

      final emp =
          dataService.empresaAtual ??
          authService.empresaAtual ??
          (authService.empresas.isNotEmpty ? authService.empresas.first : null);
      if (emp != null) {
        final agora = DateTime.now();
        final mesAtualStr =
            '${agora.year}-${agora.month.toString().padLeft(2, '0')}';

        final Map<String, dynamic> novasConfigs =
            HistoricoMensalidade.registrar(
              Map<String, dynamic>.from(emp.configuracoes ?? {}),
              competencia: mesAtualStr,
              valor: double.tryParse(
                (emp.configuracoes?['valor_mensalidade'] ??
                        emp.configuracoes?['valorMensalidade'] ??
                        '')
                    .toString()
                    .replaceAll(',', '.'),
              ),
              origem: 'manual',
            );
        novasConfigs['status_pagamento'] = 'pago';
        novasConfigs['bloqueado'] = false;
        novasConfigs['ultimo_mes_pago'] = mesAtualStr;

        final empAtualizada = emp.copyWith(configuracoes: novasConfigs);
        await authService.atualizarEmpresa(empAtualizada);
        dataService.setEmpresaAtual(empAtualizada);
        // Salvar backup dedicado de mensalidade para proteger contra sobrescrever
        await dataService.storage.salvarConfiguracoesMensalidadeLocal(
          empAtualizada.id,
          novasConfigs,
        );
        await dataService.resetarSimulacoesLicenca();
        authService.notificarMudancas();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ OK de pagamento do mês $mesAtualStr confirmado com sucesso! Licença liberada.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Navegar para a seleção de empresas após sucesso
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const SelecionarEmpresaPage(),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar OK: $e'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _verificarStatusPagamento({bool silencioso = false}) async {
    setState(() {
      _sincronizando = true;
      _mensagemSync = silencioso
          ? 'Pagamento confirmado. Liberando o sistema...'
          : 'Consultando liberação no servidor...';
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
        final empresa = dataService.empresaAtual ?? authService.empresaAtual;
        final motivoAtual = empresa?.verificarMotivoBloqueio(
          ultimaValidacaoOnline: dataService.ultimaValidacaoOnline,
          ultimaDataExecucao: dataService.ultimaDataExecucao,
        );
        if (motivoAtual == MotivoBloqueioEmpresa.nenhum) {
          _timerConfirmacaoPix?.cancel();
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const SelecionarEmpresaPage(),
            ),
            (route) => false,
          );
          return;
        }
        setState(() {
          _sincronizando = false;
          _mensagemSync =
              'Pagamento ainda não confirmado. Tente novamente '
              'após concluir o Pix.';
        });
        if (!silencioso) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ainda não recebemos a confirmação do pagamento.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
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
      await dataService.storage.salvarLiberacaoTemporaria(
        dataAmanha.toIso8601String(),
      );

      // Atualiza a liberação provisória em tempo de execução no DataService
      await dataService.carregarLiberacaoProvisoria();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Acesso liberado temporariamente até ${DateFormat('dd/MM/yyyy HH:mm').format(dataAmanha)}',
            ),
            backgroundColor: Colors.blueAccent,
          ),
        );
        // Notifica e redesenha a tela de rotas
        authService.notificarMudancas();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao liberar cortesia: $e'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _liberarComCodigoOffline() async {
    setState(() {
      _liberandoCortesia = true;
      _erroCodigoOffline = null;
    });
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final aplicada = await dataService.aplicarLicencaEmergencia(
        _codigoOfflineController.text.trim(),
      );
      if (!aplicada) {
        setState(() {
          _erroCodigoOffline =
              'Licença inválida, expirada ou emitida para outra empresa/computador.';
        });
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Licença emergencial validada neste computador.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const SelecionarEmpresaPage(),
          ),
          (route) => false,
        );
        authService.notificarMudancas();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erroCodigoOffline = 'Não foi possível validar a licença: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _liberandoCortesia = false;
        });
      }
    }
  }

  /// Extrai o DIA do vencimento mensal a partir de `data_cobranca`.
  ///
  /// Aceita tanto a data ISO completa (`'2026-07-05'` → 5) quanto o número do
  /// dia puro (`'5'` → 5), do mesmo jeito que `Empresa.isInadimplenteRecorrente`.
  static int? _diaVencimentoDe(Object? dataCobranca) {
    final bruto = dataCobranca?.toString().trim();
    if (bruto == null || bruto.isEmpty) return null;
    final data = DateTime.tryParse(bruto);
    return data?.day ?? int.tryParse(bruto);
  }

  /// Vencimento da competência que está sendo cobrada AGORA.
  ///
  /// Mesma regra de `Empresa.isInadimplenteRecorrente`:
  ///   * hoje >= dia de vencimento → a competência exigida é o mês ATUAL;
  ///   * hoje <  dia de vencimento → a competência exigida é o mês ANTERIOR
  ///     (a tela de bloqueio só aparece depois que a competência anterior
  ///     venceu e não foi paga).
  static DateTime _vencimentoDaCompetenciaCobrada(int diaVencimento) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final base = hoje.day < diaVencimento
        ? DateTime(hoje.year, hoje.month - 1, 1)
        : hoje;
    // Vencimento 31 em meses de 30 dias: usa o último dia do mês.
    final ultimoDia = DateTime(base.year, base.month + 1, 0).day;
    final dia = diaVencimento > ultimoDia ? ultimoDia : diaVencimento;
    return DateTime(base.year, base.month, dia);
  }

  @override
  void dispose() {
    _timerConfirmacaoPix?.cancel();
    _mercadoPago.dispose();
    _codigoOfflineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    final email = usuarioAtual?.email.toLowerCase() ?? '';
    final isMaster =
        usuarioAtual != null &&
        (email == 'user' || email == 'admin' || email == 'suporte');

    // O que está gravado em `data_cobranca` é o PRIMEIRO vencimento do
    // contrato (ex.: 2026-07-05) e ele não anda sozinha — o bloqueio usa só o
    // DIA do mês. Exibir a data crua faz a tela mostrar uma data velha do
    // início do contrato para sempre, então aqui recalculamos o vencimento da
    // competência que está sendo cobrada agora, com a mesma regra de
    // `Empresa.isInadimplenteRecorrente`.
    final dataCobrancaStr =
        widget.configs['data_cobranca'] ?? widget.configs['dataCobranca'];
    String vencimentoFormatado = 'Não Informado';
    final diaVencimento = _diaVencimentoDe(dataCobrancaStr);
    if (diaVencimento != null) {
      vencimentoFormatado = DateFormat(
        'dd/MM/yyyy',
      ).format(_vencimentoDaCompetenciaCobrada(diaVencimento));
    }

    final valorMensalidade = double.tryParse(
      (widget.configs['valor_mensalidade'] ??
              widget.configs['valorMensalidade'] ??
              '')
          .toString()
          .replaceAll(',', '.'),
    );

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
              label: const Text(
                'Sair da Conta',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              left: 24.0,
              right: 24.0,
              bottom: 32.0,
            ),
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
                      String mensagem =
                          'A mensalidade do sistema está pendente. Realize o pagamento via Pix abaixo para liberar o seu acesso.';

                      if (widget.motivoBloqueio ==
                          MotivoBloqueioEmpresa.excessoDiasOffline) {
                        iconData = Icons.wifi_off_rounded;
                        titulo = 'Sincronização Offline Necessária';
                        mensagem =
                            'O sistema esteve sem conexão com a internet por mais de 7 dias. Conecte-se à internet para sincronizar os dados e validar sua licença.';
                      } else if (widget.motivoBloqueio ==
                          MotivoBloqueioEmpresa.relogioAdulterado) {
                        iconData = Icons.access_time_filled_rounded;
                        titulo = 'Data do Computador Incorreta';
                        mensagem =
                            'Detectamos que a data ou horário do sistema foi alterado. Por favor, ajuste o relógio do dispositivo para o horário correto e conecte-se à internet.';
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF161624)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
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

                  if (widget.motivoBloqueio ==
                      MotivoBloqueioEmpresa.inadimplente) ...[
                    // Cobrança Pix dinâmica, criada na conta Mercado Pago do sistema.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.25),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.pix_rounded,
                                color: Colors.green,
                                size: 22,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'PAGAR COM PIX PELO MERCADO PAGO',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (valorMensalidade != null &&
                              valorMensalidade > 0) ...[
                            Text(
                              NumberFormat.currency(
                                locale: 'pt_BR',
                                symbol: 'R\$',
                              ).format(valorMensalidade),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            const Text(
                              'Valor da mensalidade não configurado. Fale com o suporte.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.orangeAccent),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_pixMensalidade?.qrCodeBase64 != null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(_pixMensalidade!.qrCodeBase64!),
                                  width: 180,
                                  height: 180,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const SizedBox(
                                      width: 180,
                                      height: 180,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.wifi_off_rounded,
                                              color: Colors.black38,
                                              size: 36,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Erro ao carregar QR Code',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (_pixMensalidade != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Aguardando confirmação automática • '
                              'competência '
                              '${HistoricoMensalidade.rotuloCompetencia(_pixMensalidade!.mesReferencia)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _pixMensalidade!.codigoCopiaCola,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 12),
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
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
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
                          ] else ...[
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed:
                                    _criandoPix ||
                                        valorMensalidade == null ||
                                        valorMensalidade <= 0
                                    ? null
                                    : _gerarPixMensalidade,
                                icon: _criandoPix
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.pix, size: 18),
                                label: Text(
                                  _criandoPix
                                      ? 'GERANDO PIX...'
                                      : 'GERAR PIX PARA PAGAR',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            if (_erroPix != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _erroPix!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.motivoBloqueio ==
                      MotivoBloqueioEmpresa.excessoDiasOffline) ...[
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: Provider.of<DataService>(
                        context,
                        listen: false,
                      ).identificadorMaquinaLicenca(),
                      builder: (context, snapshot) {
                        final idMaquina = snapshot.data;
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DADOS PARA O SUPORTE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Empresa: ${authService.empresaAtual?.id ?? 'não identificada'}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting)
                                const LinearProgressIndicator()
                              else if (idMaquina != null) ...[
                                SelectableText(
                                  'ID da máquina: $idMaquina',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: idMaquina),
                                    ),
                                    icon: const Icon(Icons.copy, size: 14),
                                    label: const Text('Copiar ID da máquina'),
                                  ),
                                ),
                              ] else
                                const Text(
                                  'Não foi possível identificar este computador.',
                                  style: TextStyle(color: Colors.redAccent),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _codigoOfflineController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'Licença emergencial (JSON)',
                        hintText:
                            'Cole aqui o conteúdo do arquivo enviado pelo suporte',
                        errorText: _erroCodigoOffline,
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _liberandoCortesia
                            ? null
                            : _liberarComCodigoOffline,
                        icon: const Icon(Icons.vpn_key_rounded, size: 18),
                        label: const Text(
                          'LIBERAR COM CODIGO OFFLINE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                        onPressed: _sincronizando
                            ? null
                            : _darOkPagamentoMesAtual,
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text(
                          '✅ DAR OK DE PAGAMENTO (LIBERAR MÊS ATUAL)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
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
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _sincronizando
                          ? null
                          : _verificarStatusPagamento,
                      child: _sincronizando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'VERIFICAR SE JÁ FOI LIBERADO',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
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
                        icon: const Icon(
                          Icons.av_timer_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: _liberandoCortesia
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
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
