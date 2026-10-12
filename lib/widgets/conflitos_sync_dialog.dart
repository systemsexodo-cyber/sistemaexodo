import 'package:flutter/material.dart';

import '../models/conflito_sync.dart';
import '../services/data_service.dart';

/// Tela de decisão dos conflitos entre ESTE banco local e a nuvem.
///
/// Aparece quando a mesma linha foi alterada nas duas máquinas (uma delas sem
/// internet). Nada foi perdido: as duas versões estão guardadas. Aqui o usuário
/// escolhe, item por item, qual delas passa a valer — e a decisão é aplicada no
/// banco local e reenviada para a nuvem.
class ConflitosSyncDialog extends StatefulWidget {
  final DataService service;

  const ConflitosSyncDialog({super.key, required this.service});

  static Future<void> mostrar(BuildContext context, DataService service) {
    return showDialog<void>(
      context: context,
      builder: (_) => ConflitosSyncDialog(service: service),
    );
  }

  @override
  State<ConflitosSyncDialog> createState() => _ConflitosSyncDialogState();
}

class _ConflitosSyncDialogState extends State<ConflitosSyncDialog> {
  List<ConflitoSync>? _conflitos;
  String? _erro;
  String? _processando;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final lista = await widget.service.listarConflitosPendentes();
    if (!mounted) return;
    setState(() {
      _conflitos = lista;
      _erro = null;
    });
  }

  Future<void> _decidir(ConflitoSync conflito, {required bool manterMeu}) async {
    setState(() => _processando = conflito.id);
    final ok = manterMeu
        ? await widget.service.resolverConflitoMantendoLocal(conflito)
        : await widget.service.resolverConflitoUsandoNuvem(conflito);
    if (!mounted) return;
    setState(() {
      _processando = null;
      if (ok) {
        _conflitos = _conflitos?.where((c) => c.id != conflito.id).toList();
      } else {
        _erro = 'Não consegui aplicar a decisão em '
            '${conflito.rotuloTabela} / ${conflito.nomeDoRegistro}.';
      }
    });
    if (ok && mounted && (_conflitos?.isEmpty ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflitos = _conflitos;
    return Dialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.call_split, color: Colors.amberAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Conflitos de sincronização',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  ),
                ],
              ),
              const Text(
                'Estes registros foram alterados neste computador E na nuvem (outro PC). '
                'As duas versões foram guardadas — escolha qual vale. Nada foi perdido.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_erro != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_erro!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              Expanded(
                child: conflitos == null
                    ? const Center(child: CircularProgressIndicator(color: Colors.amberAccent))
                    : conflitos.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum conflito pendente. As duas máquinas estão iguais. 👍',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: conflitos.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _buildConflito(conflitos[i]),
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: (conflitos?.isEmpty ?? true)
                        ? null
                        : () async {
                            await widget.service.resolverTodosConflitos();
                            if (!mounted) return;
                            Navigator.of(context).pop();
                          },
                    child: const Text(
                      'IGNORAR TODOS (mantém a nuvem e não reenvia)',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _carregar,
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.blueAccent),
                    label: const Text('Atualizar', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConflito(ConflitoSync conflito) {
    final divergentes = conflito.camposDivergentes;
    final processando = _processando == conflito.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  conflito.rotuloTabela,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conflito.nomeDoRegistro,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (divergentes.isEmpty)
            const Text(
              'Os valores ficaram diferentes só em campos de controle.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            )
          else
            ...divergentes.take(6).map(
                  (campo) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            campo,
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'meu: ${_valor(conflito.dadosLocais[campo])}   →   '
                            'nuvem: ${_valor(conflito.dadosNuvem[campo])}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          if (divergentes.length > 6)
            Text(
              '+ ${divergentes.length - 6} campo(s) diferente(s)',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (processando)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: processando ? null : () => _decidir(conflito, manterMeu: true),
                icon: const Icon(Icons.keyboard_return, size: 15),
                label: const Text('MANTER MEU (reenviar)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.22),
                  foregroundColor: Colors.greenAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: processando ? null : () => _decidir(conflito, manterMeu: false),
                icon: const Icon(Icons.cloud_download, size: 15),
                label: const Text('USAR NUVEM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.18),
                  foregroundColor: Colors.blueAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _valor(dynamic valor) {
    if (valor == null) return '—';
    final texto = valor.toString().trim();
    if (texto.isEmpty) return '—';
    if (texto.length <= 42) return texto;
    return '${texto.substring(0, 39)}...';
  }
}
