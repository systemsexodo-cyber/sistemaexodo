import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\nfe_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Corrigir item.produtoId para item.id na leitura de itens faturáveis em _popularDadosExistentes ---
old_prod_popular = """      // Mapear itens para a listagem da UI
      for (final item in itensOriginais) {
        Produto? prod;
        try {
          prod = widget.dataService.produtos.firstWhere((p) => p.id == item.produtoId);
        } catch (_) {"""

new_prod_popular = """      // Mapear itens para a listagem da UI
      for (final item in itensOriginais) {
        Produto? prod;
        try {
          prod = widget.dataService.produtos.firstWhere((p) => p.id == item.id);
        } catch (_) {"""

if old_prod_popular in content:
    content = content.replace(old_prod_popular, new_prod_popular)
    print("PROD_POPULAR_CORRIGIDO")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_prod_popular.replace("\r\n", "\n")
    normalized_new = new_prod_popular.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("PROD_POPULAR_CORRIGIDO_NORMALIZADO")
    else:
        print("FALHA_AO_CORRIGIR_PROD_POPULAR")


# --- 2. Deixar apenas a opção consolidar manual no botão Confirmar Seleção (Sem caixa de diálogo com opção Lote Direto) ---
old_onpressed_confirmar = """                        onPressed: selecionadosLote.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selecionados.clear();
                                  _selecionados.addAll(selecionadosLote);
                                });
                                
                                // Se for apenas 1 venda/pedido, abre a tela de emissão manual pré-carregada
                                if (selecionadosLote.length == 1) {
                                  final idLote = selecionadosLote.first;
                                  final itemFat = itensFaturaveis.firstWhere((i) => i['id'] == idLote);
                                  if (itemFat['tipo'] == 'Venda') {
                                    _abrirFaturamentoManual(venda: itemFat);
                                  } else {
                                    _abrirFaturamentoManual(pedido: itemFat);
                                  }
                                } else {
                                  // Se forem múltiplos, oferece a opção de consolidar em uma nota ou emitir em lote
                                  showDialog(
                                    context: context,
                                    builder: (subCtx) => AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E2E),
                                      title: const Text('Opções de Faturamento', style: TextStyle(color: Colors.white)),
                                      content: Text('Você selecionou ${selecionadosLote.length} registros. Como deseja prosseguir?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(subCtx);
                                            // Abre a emissão manual consolidando todos os itens!
                                            final loteComItens = itensFaturaveis.where((i) => selecionadosLote.contains(i['id'])).toList();
                                            _abrirFaturamentoManual(lote: loteComItens);
                                          },
                                          child: const Text('Consolidar em 1 NF-e Manual', style: TextStyle(color: Colors.greenAccent)),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(subCtx);
                                            _validarEEmitir(itensFaturaveis, dataService);
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                          child: const Text('Emitir em Lote (Direto)'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },"""

new_onpressed_confirmar = """                        onPressed: selecionadosLote.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _selecionados.clear();
                                  _selecionados.addAll(selecionadosLote);
                                });
                                
                                // Abre diretamente a emissão manual consolidando todos os itens selecionados!
                                final loteComItens = itensFaturaveis.where((i) => selecionadosLote.contains(i['id'])).toList();
                                _abrirFaturamentoManual(lote: loteComItens);
                              },"""

if old_onpressed_confirmar in content:
    content = content.replace(old_onpressed_confirmar, new_onpressed_confirmar)
    print("BOTAO_CONFIRMAR_OPCAO_MANUAL_LIMITADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_onpressed_confirmar.replace("\r\n", "\n")
    normalized_new = new_onpressed_confirmar.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("BOTAO_CONFIRMAR_OPCAO_MANUAL_LIMITADA_NORMALIZADO")
    else:
        print("FALHA_AO_LIMITAR_OPCAO_BOTAO_CONFIRMAR")


# --- 3. Injetar a geração da Conta a Receber após a nota ser emitida com sucesso ---
old_nota_adicionada = """      final nfceFinal = responseNfce.copyWith(nomeConsumidor: _nomeDestCtrl.text.trim());
      await dataService.adicionarNFCe(nfceFinal);"""

new_nota_adicionada = """      final nfceFinal = responseNfce.copyWith(nomeConsumidor: _nomeDestCtrl.text.trim());
      await dataService.adicionarNFCe(nfceFinal);

      // Gerar a Conta a Receber correspondente no Financeiro (salvamos na tabela contas_pagar com categoria 'Recebível')
      try {
        final dataVenc = DateTime.now().add(const Duration(days: 30)); // Vencimento padrão de 30 dias
        final contaReceber = ContaPagar(
          id: 'CR-' + responseNfce.numero.toString() + '-' + DateTime.now().millisecondsSinceEpoch.toString(),
          numero: 'CR-' + responseNfce.numero.toString(),
          tipo: TipoContaPagar.despesaVariavel,
          categoria: 'Recebível',
          descricao: 'NF-e Nº ' + responseNfce.numero.toString() + ' - Faturamento Cliente: ' + _nomeDestCtrl.text.trim(),
          valor: total,
          dataVencimento: dataVenc,
          dataCriacao: DateTime.now(),
          updatedAt: DateTime.now(),
          createdAt: DateTime.now(),
          status: StatusContaPagar.pendente,
          ativo: true,
          formaPagamento: _tipoPagamento == '15' ? 'Boleto' : (_tipoPagamento == '17' ? 'PIX' : 'Outros'),
          historicoPagamentos: [],
          recorrente: false,
        );
        await dataService.addContaPagar(contaReceber);
        debugPrint('>>> [FINANCEIRO] Conta a Receber gerada automaticamente para a nota ' + responseNfce.numero.toString());
      } catch (eFin) {
        debugPrint('>>> [FINANCEIRO] ⚠️ Falha ao registrar Conta a Receber: $eFin');
      }"""

if old_nota_adicionada in content:
    content = content.replace(old_nota_adicionada, new_nota_adicionada)
    print("CONTA_RECEBER_AUTO_INJETADA")
else:
    normalized_content = content.replace("\r\n", "\n")
    normalized_old = old_nota_adicionada.replace("\r\n", "\n")
    normalized_new = new_nota_adicionada.replace("\r\n", "\n")
    if normalized_old in normalized_content:
        normalized_content = normalized_content.replace(normalized_old, normalized_new)
        content = normalized_content
        print("CONTA_RECEBER_AUTO_NORMALIZADO")
    else:
        print("FALHA_AO_INJETAR_CONTA_RECEBER_AUTO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
