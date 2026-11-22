import io

# ---------- loja_publica_page.dart (LF) ----------
caminho = 'lib/pages/loja_publica_page.dart'
with io.open(caminho, 'r', encoding='utf-8', newline='') as f:
    text = f.read()
assert '\r\n' not in text


def sub(old, new, count=1):
    global text
    n = text.count(old)
    print('[loja]', n, '->', old.splitlines()[0][:70])
    assert n == count, old
    text = text.replace(old, new, count)


sub("    final estiloCards = configEcommerce?['estiloCards'] as String? ?? 'padrao';\n",
    "    final estiloCards = configEcommerce?['estiloCards'] as String? ?? 'padrao';\n"
    "    // Colunas do catálogo (Personalizar Loja > Layout): 2 é o padrão.\n"
    "    final colunasCatalogo =\n"
    "        configEcommerce?['colunasCatalogoLoja'] as String? ?? '2';\n")

sub("                                _buildGridProdutosPremium(\n"
    "                                  produtos: restantes,\n"
    "                                  estiloCards: estiloCards,\n",
    "                                _buildGridProdutosPremium(\n"
    "                                  produtos: restantes,\n"
    "                                  estiloCards: estiloCards,\n"
    "                                  colunasCatalogo: colunasCatalogo,\n")

sub("    required Color textColor,\n"
    "    String estiloCards = 'padrao',\n"
    "  }) {\n"
    "    if (produtos.isEmpty) {",
    "    required Color textColor,\n"
    "    String estiloCards = 'padrao',\n"
    "    String colunasCatalogo = '2',\n"
    "  }) {\n"
    "    if (produtos.isEmpty) {")

sub("        // Colunas responsivas: 2 no celular/tablet estreito, mais conforme a\n"
    "        // largura disponível, para a grade ficar simétrica em qualquer tela.\n"
    "        final largura = constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;\n"
    "        final colunas = (largura / 260).floor().clamp(2, 5);\n",
    "        final largura = constraints.maxWidth.isFinite ? constraints.maxWidth : 1200.0;\n"
    "        // Quantidade de colunas escolhida em Personalizar Loja > Layout.\n"
    "        // \"auto\" mantém a grade responsiva antiga (2 a 5 colunas).\n"
    "        final int colunas;\n"
    "        if (colunasCatalogo == 'auto') {\n"
    "          colunas = (largura / 260).floor().clamp(2, 5);\n"
    "        } else {\n"
    "          colunas = (int.tryParse(colunasCatalogo) ?? 2).clamp(2, 5);\n"
    "        }\n"
    "        // A altura do card acompanha a largura da coluna (a foto cresce\n"
    "        // junto), então o aspecto é calculado em vez de fixo em 0.7 — com\n"
    "        // 2 colunas o card fica proporcional em vez de esticado.\n"
    "        const espaco = 20.0;\n"
    "        final larguraCard = (largura - (colunas - 1) * espaco) / colunas;\n"
    "        final alturaImagem = (larguraCard / 1.5).clamp(140.0, 300.0);\n"
    "        final aspecto = larguraCard / (alturaImagem + 180);\n")

sub("            childAspectRatio: 0.7, // Ajustado para não cortar o botão\n"
    "            crossAxisSpacing: 20,\n"
    "            mainAxisSpacing: 20,\n",
    "            childAspectRatio: aspecto,\n"
    "            crossAxisSpacing: espaco,\n"
    "            mainAxisSpacing: espaco,\n")

# destaques: cards mais próximos
sub("                padding: const EdgeInsets.only(right: 16),\n"
    "                child: SizedBox(\n"
    "                  width: compacto ? 172 : 230,\n",
    "                padding: const EdgeInsets.only(right: 8),\n"
    "                child: SizedBox(\n"
    "                  width: compacto ? 172 : 230,\n")

with io.open(caminho, 'w', encoding='utf-8', newline='') as f:
    f.write(text)

# ---------- produto_card.dart (CRLF) ----------
card_path = 'lib/widgets/loja/produto_card.dart'
with io.open(card_path, 'r', encoding='utf-8', newline='') as f:
    card = f.read().replace('\r\n', '\n')


def csub(old, new, count=1):
    global card
    n = card.count(old)
    print('[card]', n, '->', old.splitlines()[0][:70])
    assert n == count, old
    card = card.replace(old, new, count)


csub("                    child: SizedBox(\n"
     "                      height: 150,\n"
     "                      width: double.infinity,\n"
     "                      child: _buildImagemComHover(\n"
     "                        fotoUrl: fotoUrl,\n"
     "                        produto: produto,\n"
     "                        corPrimaria: corPrimaria,\n"
     "                      ),\n"
     "                    ),\n",
     "                    child: LayoutBuilder(\n"
     "                      builder: (context, limitesImagem) {\n"
     "                        final larguraImagem =\n"
     "                            limitesImagem.maxWidth.isFinite\n"
     "                                ? limitesImagem.maxWidth\n"
     "                                : 260.0;\n"
     "                        // A foto acompanha a largura do card: na grade de\n"
     "                        // 2 colunas ela cresce; no celular fica compacta.\n"
     "                        final alturaImagem = widget.isCompacto\n"
     "                            ? (larguraImagem / 1.5).clamp(110.0, 240.0)\n"
     "                            : (larguraImagem / 1.5).clamp(140.0, 300.0);\n"
     "                        return SizedBox(\n"
     "                          height: alturaImagem,\n"
     "                          width: double.infinity,\n"
     "                          child: _buildImagemComHover(\n"
     "                            fotoUrl: fotoUrl,\n"
     "                            produto: produto,\n"
     "                            corPrimaria: corPrimaria,\n"
     "                          ),\n"
     "                        );\n"
     "                      },\n"
     "                    ),\n")

with io.open(card_path, 'w', encoding='utf-8', newline='') as f:
    f.write(card.replace('\n', '\r\n'))

# ---------- personalizar_loja_page.dart (CRLF) ----------
pers_path = 'lib/pages/personalizar_loja_page.dart'
with io.open(pers_path, 'r', encoding='utf-8', newline='') as f:
    pers = f.read().replace('\r\n', '\n')


def psub(old, new, count=1):
    global pers
    n = pers.count(old)
    print('[personalizar]', n, '->', old.splitlines()[0][:70])
    assert n == count, old
    pers = pers.replace(old, new, count)


psub("  String _tamanhoDestaquesLoja = 'grande'; // grande, compacto\n",
     "  String _tamanhoDestaquesLoja = 'grande'; // grande, compacto\n"
     "\n"
     "  /// Colunas do catálogo na vitrine: auto, 2, 3 ou 4.\n"
     "  String _colunasCatalogoLoja = '2';\n")

psub("      _estiloCards = ecommerceConfig['estiloCards'] as String? ?? 'padrao';\n",
     "      _estiloCards = ecommerceConfig['estiloCards'] as String? ?? 'padrao';\n"
     "      _colunasCatalogoLoja =\n"
     "          ecommerceConfig['colunasCatalogoLoja'] as String? ?? '2';\n")

psub("      ecommerceExistente['estiloCards'] = _estiloCards;\n",
     "      ecommerceExistente['estiloCards'] = _estiloCards;\n"
     "      ecommerceExistente['colunasCatalogoLoja'] = _colunasCatalogoLoja;\n")

psub("    ecommerceExistente['tamanhoDestaquesLoja'] = _tamanhoDestaquesLoja;\n",
     "    ecommerceExistente['tamanhoDestaquesLoja'] = _tamanhoDestaquesLoja;\n"
     "    ecommerceExistente['colunasCatalogoLoja'] = _colunasCatalogoLoja;\n")

card_ui = '''          const SizedBox(height: 16),

          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.grid_view_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Colunas do catálogo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Quantos produtos por linha na vitrine. Com 2 colunas os cards ficam maiores; '
                    '\\"Automático\\" volta à grade antiga, que se ajusta ao tamanho da tela.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('Automático')),
                      ButtonSegment(value: '2', label: Text('2')),
                      ButtonSegment(value: '3', label: Text('3')),
                      ButtonSegment(value: '4', label: Text('4')),
                    ],
                    selected: {_colunasCatalogoLoja},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() => _colunasCatalogoLoja = newSelection.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.star_rounded, color: Colors.white),'''

psub("          const SizedBox(height: 16),\n"
     "\n"
     "          Card(\n"
     "            color: Colors.white.withOpacity(0.1),\n"
     "            child: Padding(\n"
     "              padding: const EdgeInsets.all(16),\n"
     "              child: Column(\n"
     "                crossAxisAlignment: CrossAxisAlignment.start,\n"
     "                children: [\n"
     "                  Row(\n"
     "                    children: [\n"
     "                      Icon(Icons.star_rounded, color: Colors.white),",
     card_ui)

with io.open(pers_path, 'w', encoding='utf-8', newline='') as f:
    f.write(pers.replace('\n', '\r\n'))

print('OK')
