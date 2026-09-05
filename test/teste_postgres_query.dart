import 'dart:io';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() async {
  print("Iniciando teste Dart de query no PostgreSQL...");
  final db = DatabaseService();
  db.setEmpresaId('22ae2c16-a730-43f3-a4f9-19f105eb0d13');
  
  try {
    print("Tentando carregar lista de produtos...");
    final produtos = await db.carregarLista('empresa_22ae2c16-a730-43f3-a4f9-19f105eb0d13_exodo_produtos');
    print("Sucesso! Carregou ${produtos.length} produtos.");
    if (produtos.isNotEmpty) {
      final p = produtos.first;
      print("Primeiro produto: ${p['nome']}");
      print("Tipo de preco: ${p['preco'].runtimeType} (Valor: ${p['preco']})");
      print("Tipo de estoque: ${p['estoque'].runtimeType} (Valor: ${p['estoque']})");
    }
  } catch (e, st) {
    print("Erro durante o carregamento de produtos:");
    print(e);
    print(st);
  }
  
  exit(0);
}
