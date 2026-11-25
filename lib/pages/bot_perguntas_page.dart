import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bot_admin_service.dart';
import '../theme.dart';
import 'bot_teste_page.dart';

/// O que os clientes perguntaram de verdade no WhatsApp e como o bot respondeu.
/// Serve para achar os buracos e completar o `negocio.json`.
class BotPerguntasPage extends StatefulWidget {
  const BotPerguntasPage({super.key});

  @override
  State<BotPerguntasPage> createState() => _BotPerguntasPageState();
}

class _BotPerguntasPageState extends State<BotPerguntasPage> {
  final List<Map<String, dynamic>> _entradas = [];
  bool _somenteFalhas = true;
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic> _contagem = {};
  int _totalGravadas = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final dados = await BotAdminService.perguntas(
        somenteFalhas: _somenteFalhas,
        limite: 100,
      );
      final lista = (dados['entradas'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _entradas
          ..clear()
          ..addAll(lista);
        _contagem = Map<String, dynamic>.from(
          dados['counts'] as Map? ?? const {},
        );
        _totalGravadas = (dados['total_gravadas'] as int?) ?? lista.length;
      });
    } on BotAdminException catch (e) {
      if (!mounted) return;
      setState(() => _erro = e.mensagem);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _erro = 'Não consegui falar com o bot.\n'
            'A loja/VM está ligada e o atendimento iniciado?',
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  int get _semResposta {
    var total = 0;
    for (final item in _contagem.entries) {
      if (item.key == 'modelo' ||
          item.key == 'config' ||
          item.key == 'bloqueio' ||
          item.key == 'saudacao') {
        continue;
      }
      total += (item.value as num?)?.toInt() ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Perguntas dos clientes'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar',
              onPressed: _carregar,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildResumo(),
            Expanded(child: _buildLista()),
          ],
        ),
      ),
    );
  }

  Widget _buildResumo() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_semResposta pergunta(s) sem resposta certa · '
            '$_totalGravadas registrada(s)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Ficam aqui as conversas reais do WhatsApp. O que caiu em '
            '"não soube" é o que falta no negocio.json.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Só onde não soube'),
                selected: _somenteFalhas,
                onSelected: (_) {
                  setState(() => _somenteFalhas = true);
                  _carregar();
                },
              ),
              FilterChip(
                label: const Text('Todas'),
                selected: !_somenteFalhas,
                onSelected: (_) {
                  setState(() => _somenteFalhas = false);
                  _carregar();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    if (_carregando && _entradas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.orange),
          ),
        ),
      );
    }
    if (_entradas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _somenteFalhas
                ? 'Nada caiu em "não soube" ainda.\n\n'
                    'Os registros aparecem conforme os clientes escrevem no '
                    'WhatsApp. Para já testar hipóteses, use "Conversar com o bot".'
                : 'Nenhuma conversa registrada ainda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor, height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: _entradas.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildItem(_entradas[index]),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final origem = item['origem']?.toString();
    final pergunta = (item['pergunta'] ?? '').toString();
    final resposta = (item['resposta'] ?? '').toString();
    final nome = (item['nome'] ?? '').toString();
    final quando = _formatarData(item['at']?.toString());
    final cor = _corOrigem(origem);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _abrirDetalhe(item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    BotAdminService.rotuloOrigem(origem),
                    style: TextStyle(
                      fontSize: 10,
                      color: cor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [nome.isEmpty ? 'Cliente' : nome, quando]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              pergunta,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (resposta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Bot: $resposta',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _corOrigem(String? origem) {
    if (origem == 'config' || origem == 'bloqueio') return Colors.green;
    if (origem == 'modelo') return Colors.blue;
    if (origem == 'handoff') return Colors.purple;
    if (origem == 'saudacao') return Colors.teal;
    return Colors.orange;
  }

  String _formatarData(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final data = DateTime.tryParse(iso);
    if (data == null) return iso;
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)} ${dois(data.hour)}:${dois(data.minute)}';
  }

  void _abrirDetalhe(Map<String, dynamic> item) {
    final pergunta = (item['pergunta'] ?? '').toString();
    final resposta = (item['resposta'] ?? '').toString();
    final origem = item['origem']?.toString();
    final regra = (item['regra'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              BotAdminService.rotuloOrigem(origem),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _corOrigem(origem),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Cliente perguntou',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            SelectableText(
              pergunta,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text('Bot respondeu',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            SelectableText(
              resposta.isEmpty ? '(nada)' : resposta,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (regra.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Regra: $regra',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotTestePage(textoInicial: pergunta),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Testar no chat'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pergunta));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pergunta copiada.')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Para o bot responder isso sem IA, coloque no campo "respostas" '
              'do negocio.json uma chave com uma palavra dessa pergunta e o '
              'texto que ele deve responder.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
