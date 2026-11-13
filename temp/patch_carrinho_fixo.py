from pathlib import Path
p = Path(r"C:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\loja_publica_page.dart")
s = p.read_text(encoding="utf-8-sig")
old = "                    padding: const EdgeInsets.only(bottom: 48),"
new = "                    padding: const EdgeInsets.only(bottom: 132),"
if s.count(old) != 1: raise SystemExit("padding do catálogo não encontrado unicamente")
s = s.replace(old, new, 1)
anchor = """          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground"""
insert = """            // Sacola fixa: permanece visível durante toda a navegação pelo catálogo.
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: _buildCarrinhoFlutuante(primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarrinhoFlutuante(Color primaryColor) {
    return Consumer<CarrinhoService>(
      builder: (context, carrinho, _) {
        if (carrinho.isEmpty) return const SizedBox.shrink();
        final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\\$');
        final resumo = carrinho.itens.take(2).map((item) =>
          '\${item.quantidade}x \${item.nome}'
        ).join('  •  ');
        final restantes = carrinho.itens.length - 2;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _mostrarCarrinhoDrawer(moeda),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827).withOpacity(0.97),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: primaryColor.withOpacity(0.75), width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.shopping_basket_outlined, color: Colors.white, size: 25),
                            Positioned(
                              right: 1,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                                child: Text(
                                  '\${carrinho.totalItens}',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Sua sacola', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 3),
                            Text(
                              '\$resumo\${restantes > 0 ? '  + \$restantes outro(s)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('TOTAL', style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 1)),
                          Text(
                            moeda.format(carrinho.valorTotal),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedBackground"""
if s.count(anchor) != 1: raise SystemExit("âncora de fim do Scaffold não encontrada unicamente")
s = s.replace(anchor, insert, 1)
p.write_text(s, encoding="utf-8-sig", newline="")
print("Barra fixa do carrinho adicionada ao catálogo.")
