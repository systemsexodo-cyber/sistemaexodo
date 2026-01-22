import 'dart:io';

void main() {
  final file = File('lib/pages/agenda_servicos_page.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceAll('\${indent}', '                                      ');
  
  file.writeAsStringSync(content);
  print('Removed \${indent} placeholders');
}
