import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:gestor_completo/models/servico.dart';
import 'package:sistema_exodo_novo/ordem_servico.dart';
import 'package:gestor_completo/widgets/lancamento_servico_form.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';

// import 'package:gestor_completo/widgets/produto_form.dart'; // Removido para ser substituído pelo LancamentoServicoForm
import 'package:gestor_completo/theme.dart';
import 'package:gestor_completo/widgets/custom_app_bar.dart';

class ServicosPage extends StatefulWidget {
  const ServicosPage({super.key});

  @override
  State<ServicosPage> createState() => _ServicosPageState();
}

class _ServicosPageState extends State<ServicosPage> {
  void _showForm(BuildContext context, {OrdemServico? os}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: LancamentoServicoForm(
            os: os,
            onSave: (newOs) {
              final service = p.Provider.of<DataService>(
                context,
                listen: false,
              );
              if (os == null) {
                service.addOrdemServico(newOs);
              } else {
                service.updateOrdemServico(newOs);
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = p.Provider.of<DataService>(context);
    final ordensServico =
        service.ordensServico; // Será implementado na próxima fase
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: CustomAppBar(
          title: 'Serviços',
          actions: [
            IconButton(
              icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
              onPressed: () => _showForm(context),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ordensServico.isEmpty
              ? Center(
                  child: Text(
                    'Nenhuma Ordem de Serviço lançada.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
                  ),
                )
              : ListView.builder(
                  itemCount: ordensServico.length,
                  itemBuilder: (context, index) {
                    final os = ordensServico[index];
                    return AppTheme.appBackground(
                      child: Scaffold(
                        backgroundColor: AppTheme.backgroundColor,
                        appBar: CustomAppBar(
                          title: 'Serviços',
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () => _showForm(context),
                            ),
                          ],
                        ),
                        body: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: ordensServico.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Nenhuma Ordem de Serviço lançada.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: ordensServico.length,
                                  itemBuilder: (context, index) {
                                    final os = ordensServico[index];
                                    return Card(
                                      color: Theme.of(context).cardColor.withOpacity(0.8),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: ListTile(
                                        title: Text(
                                          'OS #${os.id} - ${os.cliente.nome}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onPrimary,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Início: ${os.dataInicio.day}/${os.dataInicio.month}/${os.dataInicio.year} | Agendamento: ${os.dataAgendamento.day}/${os.dataAgendamento.month}/${os.dataAgendamento.year}',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
                                              onPressed: () => _showForm(context, os: os),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                              onPressed: () {
                                                p.Provider.of<DataService>(context, listen: false).deleteOrdemServico(os.id);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    );
