import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

/// "Novidades da versão": abre ao clicar no chip `V1.0.40` do topo da Home.
///
/// Mostra três coisas, na ordem em que o suporte precisa delas:
/// 1. o que ESTA versão instalada trouxe (os detalhes que ficam publicados ao
///    lado do pacote na nuvem: `sistema_exodo_novo_<versao>.notas.txt`);
/// 2. se existe versão mais nova para esta empresa — com o botão de baixar e
///    instalar aqui mesmo, sem sair da tela;
/// 3. o histórico do que está publicado no bucket (versão, tamanho e quando).
///
/// Nada aqui derruba a tela: sem nuvem (ou sem detalhes publicados) o diálogo
/// abre com o que tem na mão e explica o que faltou.
class NovidadesVersaoDialog extends StatefulWidget {
  const NovidadesVersaoDialog({
    super.key,
    this.empresaId,
    this.configuracoesDaEmpresa,
  });

  final String? empresaId;
  final Map<String, dynamic>? configuracoesDaEmpresa;

  /// Abre o diálogo. Devolve quando ele fecha.
  static Future<void> mostrar(
    BuildContext context, {
    String? empresaId,
    Map<String, dynamic>? configuracoesDaEmpresa,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => NovidadesVersaoDialog(
        empresaId: empresaId,
        configuracoesDaEmpresa: configuracoesDaEmpresa,
      ),
    );
  }

  @override
  State<NovidadesVersaoDialog> createState() => _NovidadesVersaoDialogState();
}

class _NovidadesVersaoDialogState extends State<NovidadesVersaoDialog> {
  bool _carregando = true;
  String? _notas;
  List<VersaoNaNuvem> _versoes = const [];
  Map<String, dynamic>? _novaVersao;

  bool _baixando = false;
  double _progresso = 0.0;
  String _aviso = '';

  String get _versaoAtual => AppUpdateService.currentAppVersion;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    // Cada parte falha sozinha: sem nuvem o diálogo ainda abre e diz o que é a
    // versão instalada.
    String? notas;
    try {
      notas = await AppUpdateService.notasDaVersao(_versaoAtual);
    } catch (_) {
      notas = null;
    }

    List<VersaoNaNuvem> versoes = const [];
    try {
      final lista = await AppUpdateService.listarVersoesNaNuvem();
      versoes = [...lista]..sort((a, b) {
          final da = a.enviadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.enviadoEm ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
    } catch (_) {
      versoes = const [];
    }

    Map<String, dynamic>? nova;
    try {
      nova = await AppUpdateService.verificarAtualizacao(
        empresaId: widget.empresaId,
        configsEmpresa: widget.configuracoesDaEmpresa,
      );
    } catch (_) {
      nova = null;
    }

    if (!mounted) return;
    setState(() {
      _notas = notas;
      _versoes = versoes;
      _novaVersao = nova;
      _carregando = false;
    });
  }

  Future<void> _baixarEInstalar(String url, String versao) async {
    setState(() {
      _baixando = true;
      _progresso = 0.0;
      _aviso = '';
    });
    final (ok, motivo) = await AppUpdateService.baixarEAplicarAtualizacao(
      url,
      (progresso) {
        if (mounted) setState(() => _progresso = progresso);
      },
    );
    if (!mounted) return;
    setState(() {
      _baixando = false;
      // Quando dá certo o programa é trocado e o app fecha em seguida: o
      // aviso abaixo só aparece se algo deu errado.
      _aviso = ok
          ? 'Baixando a versão $versao... o programa vai fechar e reabrir sozinho.'
          : (motivo.isEmpty ? 'A atualização não foi aplicada.' : motivo);
    });
  }

  /// Quando esta versão foi publicada (a data vem do próprio pacote no bucket).
  VersaoNaNuvem? get _dadosDaVersaoAtual {
    for (final v in _versoes) {
      if (v.versao == _versaoAtual) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const corDoTexto = Color(0xFFE7E7F0);
    return AlertDialog(
      scrollable: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.blueAccent, width: 0.6),
      ),
      title: Row(
        children: [
          const Icon(Icons.system_update_alt, color: Colors.blueAccent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Atualizações do sistema',
              style: const TextStyle(
                color: corDoTexto,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersaoInstalada(),
            const SizedBox(height: 18),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              _buildNotas(),
              if (_novaVersao != null) ...[
                const SizedBox(height: 16),
                _buildNovaVersao(),
              ],
              const SizedBox(height: 18),
              _buildHistorico(),
              if (_aviso.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  _aviso,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildVersaoInstalada() {
    final dados = _dadosDaVersaoAtual;
    final detalhe = <String>[
      if (dados != null) 'publicada em ${dados.quandoLegivel}',
      if (dados != null) dados.tamanhoLegivel,
    ].join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Você está na versão $_versaoAtual',
            style: const TextStyle(
              color: Color(0xFFE7E7F0),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detalhe.isEmpty
                ? 'O pacote desta versão não está publicado na nuvem.'
                : detalhe,
            style: const TextStyle(color: Colors.white60, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _buildNotas() {
    final notas = _notas?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O QUE MUDOU NESTA VERSÃO',
          style: TextStyle(
            color: Colors.blueAccent,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          notas.isEmpty
              ? 'O suporte não publicou os detalhes desta versão. '
                  'As alterações ficam no arquivo de histórico do sistema.'
              : notas,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
        ),
      ],
    );
  }

  Widget _buildNovaVersao() {
    final url = (_novaVersao?['download_url'] ?? '').toString();
    final versao = (_novaVersao?['version'] ?? '').toString();
    final direcionada = _novaVersao?['is_direcionada'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nova versão disponível: $versao',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            direcionada
                ? 'Esta versão foi liberada especificamente para a sua empresa.'
                : 'Liberada para todos os clientes.',
            style: const TextStyle(color: Colors.white60, fontSize: 11.5),
          ),
          if (_baixando) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _progresso <= 0 ? null : _progresso,
              minHeight: 6,
              backgroundColor: Colors.white10,
            ),
            const SizedBox(height: 6),
            Text(
              _progresso <= 0
                  ? 'Baixando...'
                  : '${(_progresso * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: url.isEmpty ? null : () => _baixarEInstalar(url, versao),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.withOpacity(0.18),
                  foregroundColor: Colors.greenAccent,
                ),
                icon: const Icon(Icons.download, size: 16),
                label: Text('BAIXAR E INSTALAR $versao'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorico() {
    if (_versoes.isEmpty) {
      return const Text(
        'Sem comunicação com a nuvem para listar as versões publicadas.',
        style: TextStyle(color: Colors.white38, fontSize: 11.5),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VERSÕES PUBLICADAS NA NUVEM',
          style: TextStyle(
            color: Colors.blueAccent,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        for (final v in _versoes.take(12))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  v.versao == _versaoAtual
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  size: 13,
                  color: v.versao == _versaoAtual
                      ? Colors.greenAccent
                      : Colors.white24,
                ),
                const SizedBox(width: 8),
                Text(
                  'V${v.versao}',
                  style: TextStyle(
                    color: v.versao == _versaoAtual
                        ? Colors.greenAccent
                        : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${v.tamanhoLegivel} • ${v.quandoLegivel}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
