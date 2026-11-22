/// Toques disponiveis para avisar que chegou um pedido novo da loja online.
///
/// O arquivo escolhido fica salvo em `configuracoes['ecommerce']['somPedidoNovo']`
/// e o DataService usa esse valor ao tocar o som de pedido novo. Os arquivos
/// ficam em `assets/sounds/` (declarados no pubspec).
class SomPedidoOpcao {
  const SomPedidoOpcao(this.arquivo, this.nome, this.descricao);

  /// Nome do arquivo dentro de `assets/sounds/`.
  final String arquivo;

  /// Texto mostrado na lista de escolha.
  final String nome;

  /// Explicacao curta do toque.
  final String descricao;
}

/// Toque usado quando a loja ainda nao escolheu outro.
const String somPedidoPadrao = 'pedido_novo.wav';

const List<SomPedidoOpcao> sonsPedidoDisponiveis = [
  SomPedidoOpcao(
    'pedido_novo.wav',
    'Sino grave',
    'Duas notas, graves e curtas (sol e do).',
  ),
  SomPedidoOpcao(
    'pedido_alegre.wav',
    'Alegre',
    'Tres notas subindo, tipo sininho de comemoracao.',
  ),
  SomPedidoOpcao(
    'pedido_sino.wav',
    'Sino suave',
    'Uma nota so, macia e bem curta.',
  ),
  SomPedidoOpcao(
    'pedido_bip.wav',
    'Bip duplo',
    'Dois bips rapidos, estilo caixa do mercado.',
  ),
  SomPedidoOpcao(
    'success.wav',
    'Sucesso',
    'O som de sucesso ja usado no sistema.',
  ),
  SomPedidoOpcao(
    'notification.mp3',
    'Aviso antigo',
    'O som de notificacao que era usado antes.',
  ),
];

/// Garante que o arquivo salvo ainda existe na lista; se nao, volta ao padrao.
String somPedidoValido(String? arquivo) {
  if (arquivo == null || arquivo.isEmpty) return somPedidoPadrao;
  for (final opcao in sonsPedidoDisponiveis) {
    if (opcao.arquivo == arquivo) return arquivo;
  }
  return somPedidoPadrao;
}
