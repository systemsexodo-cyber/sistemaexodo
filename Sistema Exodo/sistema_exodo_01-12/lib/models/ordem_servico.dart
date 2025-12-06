import 'package:sistema_exodo_novo/models/cliente.dart';

class OrdemServico {
  final String id;
  final Cliente cliente;

  OrdemServico({required this.id, required this.cliente});

  factory OrdemServico.fromMap(Map<String, dynamic> map) {
    return OrdemServico(
      id: map['id'] ?? '',
      cliente: Cliente.fromMap(map['cliente'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'cliente': cliente.toMap()};
  }
}
