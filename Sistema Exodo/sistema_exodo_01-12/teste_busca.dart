void main() {
  final produtos = [
    'Parafuso Phillips 4x40mm',
    'Rolo de Pintura 23cm',
    'Lixa Madeira 120',
    'Porca Sextavada M8',
    'Tinta Látex Branco 18L',
  ];

  final busca = 'para';

  print('Buscando: "$busca"\n');

  for (final nome in produtos) {
    final palavras = nome
        .toLowerCase()
        .replaceAll(RegExp(r'[0-9]+'), ' ')
        .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();

    final match = palavras.any((p) => p.startsWith(busca.toLowerCase()));

    print(nome);
    print('  Palavras: $palavras');
    print('  Match: $match');
    print('');
  }
}
