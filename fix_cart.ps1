$file = "lib\pages\venda_direta_page.dart"
$lines = [System.IO.File]::ReadAllLines($file, [System.Text.Encoding]::UTF8)
Write-Host "Lines before: $($lines.Length)"

$newBlock = @(
  '                            color: isNewest',
  '                                ? Colors.greenAccent.withOpacity(0.75)',
  '                                : (_focoNoCarrinho && _cartSelectedIndex == reversedIndex',
  '                                    ? Colors.cyanAccent',
  '                                    : Colors.transparent),',
  '                            width: 2,',
  '                          ),',
  '                          boxShadow: isNewest',
  '                              ? [',
  '                                  BoxShadow(',
  '                                    color: Colors.greenAccent.withOpacity(0.2),',
  '                                    blurRadius: 10,',
  '                                    spreadRadius: 1,',
  '                                  )',
  '                                ]',
  '                              : null,',
  '                        ),',
  '                        child: _ItemCarrinhoComHover(',
  '                          item: item,',
  '                          index: reversedIndex,',
  '                          onAlterarQuantidade: (delta) =>',
  '                              _alterarQuantidade(reversedIndex, delta),',
  '                          onAplicarDesconto: () => _aplicarDescontoItem(reversedIndex),',
  '                          onRemover: () => _removerItem(reversedIndex),',
  '                          onRemoverDescontoDirect: () {',
  '                            setState(() {',
  '                              _carrinho[reversedIndex].desconto = 0.0;',
  '                            });',
  '                            _salvarCarrinho();',
  '                          },',
  '                          onDarBaixa: () => _darBaixaEstoqueItem(reversedIndex),',
  '                          onAdicionarObservacao: () => _adicionarObservacaoItem(reversedIndex),',
  '                        ),',
  '                      ),',
  '                    );',
  '                  },',
  '                ),',
  '        ),'
)

# lines 9644-9686 (0-indexed 9643-9685) are corrupted -> replace with $newBlock
$result = $lines[0..9642] + $newBlock + $lines[9686..($lines.Length-1)]
Write-Host "Lines after: $($result.Length)"
[System.IO.File]::WriteAllLines($file, $result, [System.Text.Encoding]::UTF8)
Write-Host "DONE"
