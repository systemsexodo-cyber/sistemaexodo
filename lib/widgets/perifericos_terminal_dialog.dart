import 'package:flutter/material.dart';
import '../models/empresa.dart';
import '../services/impressao_service.dart';
import '../services/balanca_service.dart';

/// Diálogo de periféricos DESTE terminal (máquina local).
///
/// - Impressora padrão do terminal — salva localmente (SharedPreferences da
///   máquina), individual por máquina. Não altera a configuração da empresa.
/// - Balança (porta COM, baud rate, modo simulação) — também local por máquina.
///
/// Tudo o que é alterado aqui fica salvo APENAS nesta máquina e NÃO afeta os
/// outros PDVs. As configurações gerais da empresa continuam no Portal.
class PerifericosTerminalDialog extends StatefulWidget {
  final Empresa? empresa;

  const PerifericosTerminalDialog({super.key, this.empresa});

  @override
  State<PerifericosTerminalDialog> createState() => _PerifericosTerminalDialogState();
}

class _PerifericosTerminalDialogState extends State<PerifericosTerminalDialog> {
  bool _carregando = true;
  String? _impressoraAtual;
  int _totalImpressoras = 0;

  // Balança
  Map<String, dynamic> _configBalanca = {};
  List<String> _portasCOM = [];
  bool _balancaAtiva = false;
  String _portaSelecionada = 'COM1';
  int _baudRate = 9600;
  bool _usarMock = true;
  double _pesoMock = 1.5;
  bool _testandoBalanca = false;

  static const List<int> _baudRates = [2400, 4800, 9600, 19200, 38400, 57600, 115200];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final impressora = await ImpressaoService.getUltimaImpressora(
        empresaId: widget.empresa?.id,
      );
      final impressoras = await ImpressaoService.listarImpressoras();
      final balanca = BalancaService();
      final config = await balanca.obterConfiguracao();
      final portas = await balanca.listarPortasCOM();

      if (!mounted) return;
      setState(() {
        _impressoraAtual = (impressora != null && impressora.isNotEmpty)
            ? impressora
            : (widget.empresa?.configuracoes?['impressoraSelecionada'] as String?)?.trim();
        _totalImpressoras = impressoras.length;
        _configBalanca = config;
        _balancaAtiva = config['ativo'] == true;
        _portaSelecionada = (config['porta']?.toString() ?? 'COM1');
        final baudRaw = config['baudRate'];
        _baudRate = baudRaw is int
            ? baudRaw
            : (int.tryParse(baudRaw?.toString() ?? '9600') ?? 9600);
        _usarMock = config['usarMock'] == true;
        _pesoMock = double.tryParse(config['pesoMock']?.toString() ?? '1.5') ?? 1.5;
        _portasCOM = portas;
        if (!_portasCOM.contains(_portaSelecionada)) {
          _portasCOM.insert(0, _portaSelecionada);
        }
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _trocarImpressora() async {
    final escolhida = await ImpressaoService.exibirDialogoSelecaoImpressora(
      context,
      empresa: widget.empresa,
      somenteLocal: true, // a escolha fica APENAS nesta máquina
    );
    if (escolhida != null && mounted) {
      setState(() => _impressoraAtual = escolhida);
      _mostrarSnack('✓ Impressora deste terminal: $escolhida', Colors.green);
    }
  }

  Future<void> _testarImpressora() async {
    final nome = _impressoraAtual;
    if (nome == null || nome.isEmpty) {
      _mostrarSnack('Selecione uma impressora primeiro', Colors.orange);
      return;
    }
    final ok = await ImpressaoService.testarImpressora(nome, empresa: widget.empresa);
    if (mounted) {
      _mostrarSnack(
        ok ? '✓ Teste enviado para: $nome' : '✗ Falha ao testar: $nome',
        ok ? Colors.green : Colors.redAccent,
      );
    }
  }

  Future<void> _testarBalanca() async {
    setState(() => _testandoBalanca = true);
    final res = await BalancaService().lerPeso();
    if (!mounted) return;
    setState(() => _testandoBalanca = false);
    final erro = res['erro'] as String?;
    final peso = res['peso'];
    final simulado = res['simulado'] == true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resultado da Balança', style: TextStyle(color: Colors.white)),
        content: Text(
          erro != null
              ? erro
              : 'Peso lido: $peso kg${simulado ? ' (modo simulado)' : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _salvarBalanca() async {
    final novaConfig = Map<String, dynamic>.from(_configBalanca);
    novaConfig['ativo'] = _balancaAtiva;
    novaConfig['porta'] = _portaSelecionada;
    novaConfig['baudRate'] = _baudRate;
    novaConfig['usarMock'] = _usarMock;
    novaConfig['pesoMock'] = _pesoMock;
    await BalancaService().salvarConfiguracao(novaConfig);
    if (mounted) {
      _mostrarSnack('✓ Configurações da balança salvas (somente nesta máquina)', Colors.green);
    }
  }

  void _mostrarSnack(String msg, Color cor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(24),
        child: _carregando
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cabecalho(),
                    const SizedBox(height: 14),
                    _infoLocal(),
                    const SizedBox(height: 18),
                    _secaoImpressora(),
                    const SizedBox(height: 22),
                    _secaoBalanca(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Fechar', style: TextStyle(color: Colors.white60)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _salvarBalanca,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Salvar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _cabecalho() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.settings_input_component, color: Colors.blueAccent, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Periféricos deste Terminal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Configure a impressora e a balança DESTA máquina',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70),
          tooltip: 'Recarregar periféricos',
          onPressed: _carregarDados,
        ),
      ],
    );
  }

  Widget _infoLocal() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Estas configurações ficam salvas APENAS nesta máquina (PDV). '
              'Mudar aqui não afeta as outras máquinas. As configurações gerais '
              'da empresa continuam sendo feitas no Portal.',
              style: TextStyle(color: Colors.amber.shade100, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoImpressora() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.print_rounded, color: Colors.blueAccent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Impressora',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_totalImpressoras > 0)
              Text(
                '$_totalImpressoras no Windows',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.print, color: Colors.white38, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Impressora padrão deste terminal',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (_impressoraAtual != null && _impressoraAtual!.isNotEmpty)
                          ? _impressoraAtual!
                          : 'Nenhuma configurada (usará a padrão da empresa)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _trocarImpressora,
                child: const Text('Trocar', style: TextStyle(color: Colors.blueAccent)),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _testarImpressora,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Testar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _secaoBalanca() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.monitor_weight_outlined, color: Colors.tealAccent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Balança',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Switch(
              value: _balancaAtiva,
              activeColor: Colors.tealAccent,
              onChanged: (v) => setState(() => _balancaAtiva = v),
            ),
          ],
        ),
        if (_balancaAtiva) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _dropdownPorta(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdownBaud(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text(
                    'Modo simulado',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Sem balança física conectada',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  value: _usarMock,
                  activeColor: Colors.tealAccent,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (v) => setState(() => _usarMock = v ?? true),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _testandoBalanca ? null : _testarBalanca,
                icon: _testandoBalanca
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                      )
                    : const Icon(Icons.play_arrow, size: 16),
                label: Text(_testandoBalanca ? 'Lendo...' : 'Testar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: BorderSide(color: Colors.tealAccent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dropdownPorta() {
    return DropdownButtonFormField<String>(
      initialValue: _portaSelecionada,
      dropdownColor: const Color(0xFF2A2D3E),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Porta COM',
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _portasCOM
          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _portaSelecionada = v);
      },
    );
  }

  Widget _dropdownBaud() {
    return DropdownButtonFormField<int>(
      initialValue: _baudRate,
      dropdownColor: const Color(0xFF2A2D3E),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: 'Baud Rate',
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: _baudRates
          .map((b) => DropdownMenuItem(value: b, child: Text('$b')))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _baudRate = v);
      },
    );
  }
}
