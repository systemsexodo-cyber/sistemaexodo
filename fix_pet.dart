import 'dart:io';

void main() {
  final file = File('lib/pages/agenda_servicos_page.dart');
  var content = file.readAsStringSync();
  
  // Fix 1: Notification modal
  final oldNotification = '''
                                     const SizedBox(height: 16),
                                     _buildInfoItem(
                                       Icons.pets_rounded,
                                       'Pet / Serviço',
                                       '\${sol.petNome ?? sol.pet?.nome ?? "Não informado"} - \${sol.servico?.nome ?? sol.servicoId ?? "Serviço"}',
                                     ),''';
                                     
  final newNotification = '''
                                     const SizedBox(height: 16),
                                     _buildInfoItem(
                                       currentDataService.empresaAtual?.moduloPet == true ? Icons.pets_rounded : Icons.work_rounded,
                                       currentDataService.empresaAtual?.moduloPet == true ? 'Pet / Serviço' : 'Serviço',
                                       currentDataService.empresaAtual?.moduloPet == true 
                                         ? '\${sol.petNome ?? sol.pet?.nome ?? "Não informado"} - \${sol.servico?.nome ?? sol.servicoId ?? "Serviço"}'
                                         : (sol.servico?.nome ?? sol.servicoId ?? "Serviço"),
                                     ),''';

  // Fix 2: Agenda card (if not already fixed)
  final oldCard = 'if (agendamento.pet != null || agendamento.petNome != null) ...[';
  final newCard = 'if ((agendamento.pet != null || agendamento.petNome != null) && dataService.empresaAtual?.moduloPet == true) ...[';

  if (content.contains(oldNotification.trim())) {
    print('Found notification block');
    content = content.replaceFirst(oldNotification.trim(), newNotification.trim());
  } else {
    print('Could not find notification block exactly, trying partial match...');
    // Try to match just the Pet / Serviço part
    content = content.replaceAll(
      "Icons.pets_rounded,\n                                       'Pet / Serviço',",
      "currentDataService.empresaAtual?.moduloPet == true ? Icons.pets_rounded : Icons.work_rounded,\n                                       currentDataService.empresaAtual?.moduloPet == true ? 'Pet / Serviço' : 'Serviço',"
    );
  }
  
  if (content.contains(oldCard)) {
    content = content.replaceAll(oldCard, newCard);
    print('Replaced card condition');
  }

  file.writeAsStringSync(content);
  print('Done');
}
