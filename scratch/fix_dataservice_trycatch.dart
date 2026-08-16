import 'dart:io';

void main() {
  final file = File('lib/services/data_service.dart');
  String content = file.readAsStringSync();
  
  final regex = RegExp(r'      if \(([a-zA-Z0-9_]+Map)\.isNotEmpty\) \{\s+([a-zA-Z0-9_]+)\.clear\(\);\s+([a-zA-Z0-9_]+)\.addAll\(\1\.map\(\(map\) => ([a-zA-Z0-9_]+)\.fromMap\(map\)\)\);\s+\}');
  
  content = content.replaceAllMapped(regex, (match) {
    return "      try { if (\${match.group(1)}.isNotEmpty) { \${match.group(2)}.clear(); \${match.group(3)}.addAll(\${match.group(1)}.map((map) => \${match.group(4)}.fromMap(map))); } } catch (e, st) { print('CRASH \${match.group(4)}: \$e'); try { File('crash_load.txt').writeAsStringSync('CRASH \${match.group(4)}: \$e\\n', mode: FileMode.append); } catch(_) {} }";
  });
  
  file.writeAsStringSync(content);
  print('Done');
}
