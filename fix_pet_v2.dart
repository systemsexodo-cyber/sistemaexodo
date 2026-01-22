import 'dart:io';

void main() {
  final file = File('lib/pages/agenda_servicos_page.dart');
  final lines = file.readAsLinesSync();
  
  bool changed = false;
  for (int i = 0; i < lines.length; i++) {
    // Look for the specific pattern in the notification modal area
    if (i > 5500 && i < 5600) {
      if (lines[i].contains('Icons.pets_rounded')) {
         print('Found Icons.pets_rounded at line \${i+1}');
         lines[i] = lines[i].replaceFirst('Icons.pets_rounded', 'currentDataService.empresaAtual?.moduloPet == true ? Icons.pets_rounded : Icons.work_rounded');
         lines[i+1] = lines[i+1].replaceFirst("'Pet / Serviço'", "currentDataService.empresaAtual?.moduloPet == true ? 'Pet / Serviço' : 'Serviço'");
         
         // Fix the complex string with pet info
         if (lines[i+2].contains('sol.petNome')) {
            final indent = ' ' * (lines[i+2].length - lines[i+2].trimLeft().length);
            lines[i+2] = '''\${indent}currentDataService.empresaAtual?.moduloPet == true 
\${indent}  ? '\${sol.petNome ?? sol.pet?.nome ?? "Não informado"} - \${sol.servico?.nome ?? sol.servicoId ?? "Serviço"}'
\${indent}  : (sol.servico?.nome ?? sol.servicoId ?? "Serviço"),''';
            changed = true;
         }
      }
    }
  }

  if (changed) {
    file.writeAsStringSync(lines.join('\n'));
    print('Successfully updated notification modal');
  } else {
    print('Pattern not found');
  }
}
