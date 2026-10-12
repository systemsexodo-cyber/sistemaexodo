import 'dart:async';

import 'package:flutter/material.dart';

import '../services/data_service.dart';
import '../utils/identidade_caixa.dart';
import '../utils/numeracao_venda.dart';

/// Identificação DESTE caixa (computador), usada para numerar as vendas.
///
/// É a configuração que resolve o problema de dois computadores sem internet
/// emitirem o mesmo número: com um nome por máquina, cada caixa tem a própria
/// sequência (`CX1-0001`, `CX2-0001`) e elas nunca se cruzam.
Future<void> mostrarDialogoIdentidadeDoCaixa(
  BuildContext context,
  DataService service,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoIdentidadeDoCaixa(service: service),
  );
}

class _DialogoIdentidadeDoCaixa extends StatefulWidget {
  const _DialogoIdentidadeDoCaixa({required this.service});

  final DataService service;

  @override
  State<_DialogoIdentidadeDoCaixa> createState() =>
      _DialogoIdentidadeDoCaixaState();
}

class _DialogoIdentidadeDoCaixaState extends State<_DialogoIdentidadeDoCaixa> {
  late final TextEditingController _controller;
  String? _erro;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.service.nomeDoCaixa);
    // Rebuild a cada tecla: a prévia de numeração acompanha o nome digitado.
    _controller.addListener(() {
      if (!mounted) return;
      setState(() => _erro = null);
    });
    // A conferência do nome repetido é respondida pela nuvem depois; sem escutar
    // o serviço, o aviso só apareceria quando o operador digitasse algo.
    widget.service.addListener(_aoAtualizarServico);

    // "Outro computador já usa este nome?" é pergunta para a nuvem: dispara em
    // segundo plano para abrir o diálogo na hora.
    unawaited(widget.service.verificarDuplicidadeDoNomeDoCaixa());
  }

  void _aoAtualizarServico() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(_aoAtualizarServico);
    _controller.dispose();
    super.dispose();
  }

  String get _digitado => _controller.text.trim();

  /// O que vai aparecer na venda se salvar agora.
  String get _exemploDeNumeracao {
    final normalizado = NumeracaoVenda.normalizarCaixa(_digitado);
    if (normalizado != null) {
      return '${NumeracaoVenda.formatar(normalizado, 1)}, '
          '${NumeracaoVenda.formatar(normalizado, 2)}, '
          '${NumeracaoVenda.formatar(normalizado, 3)}...';
    }
    return '${NumeracaoVenda.formatar(NumeracaoVenda.prefixoLegado, 1)}, '
        '${NumeracaoVenda.formatar(NumeracaoVenda.prefixoLegado, 2)}, '
        '${NumeracaoVenda.formatar(NumeracaoVenda.prefixoLegado, 3)}...';
  }

  Future<void> _salvar() async {
    final normalizado = NumeracaoVenda.normalizarCaixa(_digitado);
    if (_digitado.isNotEmpty && normalizado == null) {
      setState(() => _erro = 'Use de 1 a 8 caracteres, começando por letra '
          '(ex.: CX1, CX2, LOJA1). PED e VND são reservados.');
      return;
    }

    setState(() => _salvando = true);

    // Antes de gravar, confere se OUTRO computador já publicou este nome: dois
    // caixas com o mesmo nome voltam a emitir número repetido quando ficam sem
    // internet, então o operador confirma que é isso mesmo. (Vazio = remover o
    // nome, e aí não há prefixo a defender.)
    final nomeNovo = normalizado ?? '';
    final outrasMaquinas = nomeNovo.isEmpty
        ? const <String>[]
        : await widget.service.maquinasUsandoNomeDeCaixa(nomeNovo);
    if (!mounted) return;
    // Só interroga quando o operador está ESCOLHENDO um nome já usado: se é o
    // mesmo nome que já está aqui, o aviso vermelho acima já diz tudo e o
    // SALVAR não muda nada no mundo.
    final escolhendoNomeNovo = nomeNovo != widget.service.nomeDoCaixa;
    if (outrasMaquinas.isNotEmpty && escolhendoNomeNovo) {
      final insistir =
          await _confirmarNomeJaEmUso(nomeNovo, outrasMaquinas);
      if (!mounted) return;
      if (insistir != true) {
        setState(() => _salvando = false);
        return;
      }
    }

    final salvo = await widget.service.definirNomeDoCaixa(_digitado);
    if (!mounted) return;
    setState(() => _salvando = false);

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(
          salvo == null || salvo.isEmpty
              ? 'Caixa sem nome: as vendas voltaram para a sequência VND- '
                  '(compartilhada com os outros computadores).'
              : 'Caixa identificado como "$salvo": agora este computador numera '
                  'as vendas como $salvo-0001, $salvo-0002...',
        ),
      ),
    );
  }

  /// Confirmação de nome já em uso em outra máquina.
  ///
  /// Devolve true quando o operador escolhe manter o nome repetido (por exemplo
  /// ao SUBSTITUIR o computador antigo, que saiu de circulação).
  Future<bool?> _confirmarNomeJaEmUso(String nome, List<String> maquinas) {
    final outras = IdentidadeCaixa.listarMaquinas(maquinas);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Nome já em uso'),
          ],
        ),
        content: Text(
          'O caixa "$nome" já está em uso em: $outras.\n\n'
          'Dois computadores com o mesmo nome voltam a gerar o MESMO número de '
          'venda quando ficam sem internet. Se este computador está substituindo '
          'aquele (a máquina antiga saiu de uso), confirme; senão, escolha outro '
          'nome — por exemplo CX2, LOJA2.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ESCOLHER OUTRO'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('MANTER MESMO ASSIM'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeAtual = widget.service.nomeDoCaixa;
    final numeracaoPorCaixa = widget.service.numeracaoPorCaixa;
    final outrasMaquinas = widget.service.caixasComMesmoNome;

    return AlertDialog(
      scrollable: true,
      title: const Row(
        children: [
          Icon(Icons.point_of_sale, color: Color(0xFFFF6B35)),
          SizedBox(width: 8),
          Text('Identificação deste caixa'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: numeracaoPorCaixa
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: numeracaoPorCaixa ? Colors.green : Colors.amber,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    numeracaoPorCaixa ? Icons.check_circle : Icons.info_outline,
                    size: 18,
                    color: numeracaoPorCaixa ? Colors.green : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      numeracaoPorCaixa
                          ? 'Este computador está identificado como "$nomeAtual" '
                              'e numera as vendas como $nomeAtual-0001.'
                          : 'Sem nome, dois computadores sem internet geram o '
                              'MESMO número de venda. Dê um nome diferente para '
                              'cada caixa.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            // Outra máquina usando o MESMO nome: é o cenário que faz os dois
            // caixas voltarem a numerar igual, então o aviso é vermelho e fica
            // acima do campo.
            if (outrasMaquinas.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'O nome "$nomeAtual" também está em uso em: '
                        '${IdentidadeCaixa.listarMaquinas(outrasMaquinas)}. '
                        'Dois caixas com o mesmo nome voltam a gerar o MESMO '
                        'número de venda quando ficam sem internet — troque o '
                        'nome de um deles.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Nome deste caixa',
                hintText: 'CX1',
                errorText: _erro,
                helperText: 'Ex.: CX1 no caixa da frente, CX2 no do fundo. '
                    'Não repita o nome no outro computador.',
                prefixIcon: const Icon(Icons.edit),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _salvando ? null : _salvar(),
            ),
            const SizedBox(height: 4),
            Text(
              'Como vão sair as vendas: $_exemploDeNumeracao',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A numeração dos pedidos (PED-) não muda. A venda já emitida '
              'continua com o número que está na nota.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _salvando
              ? null
              : () {
                  _controller.text = '';
                  _salvar();
                },
          child: const Text('REMOVER NOME'),
        ),
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton.icon(
          onPressed: _salvando ? null : _salvar,
          icon: _salvando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: const Text('SALVAR'),
        ),
      ],
    );
  }
}
