import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../services/producao_pdf_service.dart';
import '../models/departamento.dart';
import '../services/impressao_service.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Página de cadastro de DEPARTAMENTOS (setores de preparação: Cozinha, Bar,
/// Sobremesas, Frituras, etc.).
///
/// O departamento é a área onde o item é preparado. A configuração de
/// impressora é uma coisa SEPARADA: cada departamento PODE ter uma impressora
/// associada (ex.: a impressora da cozinha), mas isso é opcional e não
/// confunde a escolha do departamento no produto.
class CadastroDepartamentosPage extends StatefulWidget {
  const CadastroDepartamentosPage({super.key});

  @override
  State<CadastroDepartamentosPage> createState() => _CadastroDepartamentosPageState();
}

class _CadastroDepartamentosPageState extends State<CadastroDepartamentosPage> {
  List<String> _impressorasSistema = [];

  @override
  void initState() {
    super.initState();
    ImpressaoService.listarImpressoras().then((lista) {
      if (mounted) {
        setState(() {
          _impressorasSistema = lista.map((p) => p.name).toList();
        });
      }
    });
  }

  IconData _iconeDoDepartamento(Departamento d) {
    switch (d.icone) {
      case 'local_bar':
        return Icons.local_bar;
      case 'restaurant':
        return Icons.restaurant;
      case 'soup_kitchen':
        return Icons.soup_kitchen;
      case 'bakery_dining':
        return Icons.bakery_dining;
      case 'icecream':
        return Icons.icecream;
      case 'coffee':
        return Icons.coffee;
      case 'flatware':
        return Icons.flatware;
      case 'kitchen':
        return Icons.kitchen;
      default:
        return Icons.food_bank;
    }
  }

  Color _corDoDepartamento(Departamento d) {
    final hex = d.cor?.replaceAll('#', '') ?? '';
    if (hex.length == 6) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    }
    return Colors.orangeAccent;
  }

  @override
  Widget build(BuildContext context) {
    final ds = Provider.of<DataService>(context);
    final departamentos = ds.departamentos;

    return Scaffold(
      backgroundColor: const Color(0xFF161621),
      appBar: AppBar(
        title: const Text('Departamentos', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(null),
        icon: const Icon(Icons.add),
        label: const Text('Novo Departamento'),
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Departamentos são os setores de preparação (ex.: Bar, Cozinha, Sobremesas). '
              'Cada um pode ter sua própria impressora — a configuração de impressora é separada '
              'da escolha do departamento no produto.',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'A impressora de cada departamento é definida aqui. A tela de Cozinha/Bar usa '
                      'estes departamentos para separar os pedidos.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: departamentos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.food_bank, size: 64, color: Colors.white24),
                          const SizedBox(height: 16),
                          const Text('Nenhum departamento cadastrado', style: TextStyle(color: Colors.white60)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _abrirFormulario(null),
                            icon: const Icon(Icons.add),
                            label: const Text('Criar Primeiro Departamento'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: departamentos.length,
                      itemBuilder: (context, index) {
                        final d = departamentos[index];
                        final cor = _corDoDepartamento(d);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E2E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cor.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_iconeDoDepartamento(d), color: cor, size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.nome,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      d.impressoraProducao != null && d.impressoraProducao!.isNotEmpty
                                          ? '🖨️ Imprime em: ${d.impressoraProducao}'
                                          : 'Impressora: padrão do terminal',
                                      style: TextStyle(
                                        color: d.impressoraProducao != null && d.impressoraProducao!.isNotEmpty
                                            ? Colors.tealAccent
                                            : Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                                onPressed: () => _abrirFormulario(d),
                              ),
                              IconButton(
                                tooltip: 'Excluir',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _confirmarExclusao(d),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarExclusao(Departamento d) async {
    final ds = Provider.of<DataService>(context, listen: false);
    // Conta produtos vinculados para avisar o usuário
    final vinculados = ds.produtos.where((p) => p.departamentoId == d.id).length;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Excluir departamento?', style: TextStyle(color: Colors.white)),
        content: Text(
          vinculados > 0
              ? 'O departamento "${d.nome}" está vinculado a $vinculados produto(s). '
                  'Ao excluir, esses produtos ficarão SEM departamento.'
              : 'Tem certeza que deseja excluir o departamento "${d.nome}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar == true) {
      await ds.excluirDepartamento(d.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Departamento "${d.nome}" excluído'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  /// Imprime um ticket de PRODUÇÃO de exemplo na impressora do departamento,
  /// para conferir o layout e a impressora certa.
  Future<void> _testarImpressaoDepartamento(
    BuildContext ctx,
    String? impressora,
    DataService ds,
  ) async {
    final empresa = ds.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Empresa não encontrada para o teste de impressão.')),
      );
      return;
    }

    final impressoras = (impressora != null && impressora.isNotEmpty)
        ? [impressora]
        : <String>[];

    final impressos = await ProducaoPdfService.imprimirTicketTeste(
      empresa: empresa,
      impressoras: impressoras,
      dataService: ds,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(
          impressos > 0
              ? '✅ Ticket de teste enviado para: ${impressoras.isEmpty ? 'IMPRESSORA PADRÃO DO TERMINAL' : impressoras.join(' • ')}'
              : 'Não foi possível imprimir. Verifique se há uma impressora instalada/ativa no Windows.',
        ),
        backgroundColor: impressos > 0 ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _abrirFormulario(Departamento? departamento) async {
    final ds = Provider.of<DataService>(context, listen: false);
    final nomeController = TextEditingController(text: departamento?.nome ?? '');
    String? cor = departamento?.cor;
    String? icone = departamento?.icone;
    String? impressora = departamento?.impressoraProducao;

    final salvo = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              departamento == null ? 'Novo Departamento' : 'Editar Departamento',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nomeController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec(
                      'Nome do departamento',
                      hint: 'Ex: Cozinha, Bar, Sobremesas',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Cor', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      '#FF5722', // deep orange
                      '#2196F3', // blue
                      '#4CAF50', // green
                      '#9C27B0', // purple
                      '#FF9800', // orange
                      '#00BCD4', // cyan
                      '#E91E63', // pink
                      '#795548', // brown
                    ].map((hex) {
                      final val = int.parse(hex.replaceAll('#', ''), radix: 16);
                      final c = Color(0xFF000000 | val);
                      final selecionada = cor == hex;
                      return GestureDetector(
                        onTap: () => setDialogState(() => cor = hex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selecionada ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: selecionada
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ícone', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ('local_bar', Icons.local_bar),
                      ('restaurant', Icons.restaurant),
                      ('soup_kitchen', Icons.soup_kitchen),
                      ('bakery_dining', Icons.bakery_dining),
                      ('icecream', Icons.icecream),
                      ('coffee', Icons.coffee),
                      ('flatware', Icons.flatware),
                      ('kitchen', Icons.kitchen),
                    ].map((entry) {
                      final nome = entry.$1;
                      final ic = entry.$2;
                      final selecionado = (icone ?? 'restaurant') == nome;
                      return GestureDetector(
                        onTap: () => setDialogState(() => icone = nome),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selecionado ? Colors.orangeAccent.withOpacity(0.25) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selecionado ? Colors.orangeAccent : Colors.white24,
                            ),
                          ),
                          child: Icon(ic, color: selecionado ? Colors.orangeAccent : Colors.white70, size: 22),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Impressora deste departamento (separado do departamento)',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Deixe vazio para usar a impressora padrão do terminal.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: impressora,
                    dropdownColor: const Color(0xFF2A2D3E),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: _dec('Impressora do departamento'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Padrão do terminal', style: TextStyle(color: Colors.white70)),
                      ),
                      ..._impressorasSistema.map(
                        (nome) => DropdownMenuItem<String?>(
                          value: nome,
                          child: Text(nome, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => impressora = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _testarImpressaoDepartamento(ctx, impressora, ds),
                      icon: const Icon(Icons.print_outlined, color: Colors.amberAccent, size: 18),
                      label: const Text(
                        'TESTAR IMPRESSÃO DE PRODUÇÃO',
                        style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: const BorderSide(color: Colors.amberAccent, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Imprime um ticket de exemplo na impressora acima para conferir o layout e a impressora.',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  final nome = nomeController.text.trim();
                  if (nome.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Informe o nome do departamento'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('SALVAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (salvo == true) {
      final nome = nomeController.text.trim();
      final dep = Departamento(
        id: departamento?.id ?? _uuid.v4(),
        nome: nome,
        cor: cor,
        icone: icone,
        impressoraProducao: (impressora != null && impressora!.isNotEmpty) ? impressora : null,
        ordem: departamento?.ordem ?? ds.departamentos.length,
      );
      await ds.salvarDepartamento(dep);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(departamento == null ? 'Departamento criado: $nome' : 'Departamento atualizado: $nome'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.white24),
      ),
    );
  }
}
