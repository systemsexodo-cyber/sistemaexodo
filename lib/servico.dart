// class Servico { (remove this file or comment out)
  final String id;
  final String nome;
  final String? descricao;
  final double preco;
  final double valorAdicional;
  final String? descricaoAdicional;
  final double desconto;
  final String? descricaoDesconto;

  class Servico {
    final String id;
    final String nome;
    final String descricao;
    final double preco;
    final double valorAdicional;
    final String descricaoAdicional;
    final double desconto;
    final String descricaoDesconto;
    final DateTime dataInicio;
    final DateTime dataFim;
    final DateTime createdAt;
    final DateTime updatedAt;

    Servico({
      required this.id,
      required this.nome,
      required this.descricao,
      required this.preco,
      required this.valorAdicional,
      required this.descricaoAdicional,
      required this.desconto,
      required this.descricaoDesconto,
      required this.dataInicio,
      required this.dataFim,
      class Servico {
        final String id;
        final String nome;
        final String descricao;
        final double preco;
        final double valorAdicional;
        final String descricaoAdicional;
        final double desconto;
        final String descricaoDesconto;
        final DateTime dataInicio;
        final DateTime dataFim;
        final DateTime createdAt;
        final DateTime updatedAt;

        Servico({
          required this.id,
          required this.nome,
          required this.descricao,
          required this.preco,
          required this.valorAdicional,
          required this.descricaoAdicional,
          required this.desconto,
          required this.descricaoDesconto,
          required this.dataInicio,
          required this.dataFim,
          required this.createdAt,
          required this.updatedAt,
        });

        factory Servico.fromMap(Map<String, dynamic> map) {
          return Servico(
            id: map['id'] ?? '',
            nome: map['nome'] ?? '',
            descricao: map['descricao'] ?? '',
            preco: (map['preco'] ?? 0).toDouble(),
            valorAdicional: (map['valorAdicional'] ?? 0).toDouble(),
            descricaoAdicional: map['descricaoAdicional'] ?? '',
            desconto: (map['desconto'] ?? 0).toDouble(),
            descricaoDesconto: map['descricaoDesconto'] ?? '',
            dataInicio: map['dataInicio'] is Timestamp
                ? (map['dataInicio'] as Timestamp).toDate()
                : DateTime.tryParse(map['dataInicio'] ?? '') ?? DateTime.now(),
            dataFim: map['dataFim'] is Timestamp
                ? (map['dataFim'] as Timestamp).toDate()
                : DateTime.tryParse(map['dataFim'] ?? '') ?? DateTime.now(),
            createdAt: map['createdAt'] is Timestamp
                ? (map['createdAt'] as Timestamp).toDate()
                : DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
            updatedAt: map['updatedAt'] is Timestamp
                ? (map['updatedAt'] as Timestamp).toDate()
                : DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
          );
        }

        Map<String, dynamic> toMap() {
          return {
            'id': id,
            'nome': nome,
            'descricao': descricao,
            'preco': preco,
            'valorAdicional': valorAdicional,
            'descricaoAdicional': descricaoAdicional,
            'desconto': desconto,
            'descricaoDesconto': descricaoDesconto,
            'dataInicio': Timestamp.fromDate(dataInicio),
            'dataFim': Timestamp.fromDate(dataFim),
            'createdAt': Timestamp.fromDate(createdAt),
            'updatedAt': Timestamp.fromDate(updatedAt),
          };
        }
      }

