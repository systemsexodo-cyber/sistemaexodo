import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/caixa.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/nfce.dart';
import '../models/conta_pagar.dart';
import '../widgets/sync_status_widget.dart';
import '../services/nfce_service_factory.dart';
import '../services/auth_service.dart';
import '../services/danfe_service.dart';

class NfePage extends StatefulWidget {
  const NfePage({super.key});

  @override
  State<NfePage> createState() => _NfePageState();
}

class _NfePageState extends State<NfePage> {
  final _buscaController = TextEditingController();
  final _serieController = TextEditingController(text: '1');
  final _numeroController = TextEditingController();
  String _filtroStatus = 'Todos'; // 'Todos', 'Autorizada', 'Cancelada', 'Pendente/Rejeitada'
  bool _ambienteHomologacao = true;
  
  // Vendas e Pedidos selecionados para emissão
  final Set<String> _selecionados = {};
  
  @override
  void dispose() {
    _buscaController.dispose();
    _serieController.dispose();
    _numeroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context);
    
    // Inicializar a série padrão de acordo com o operador logado para evitar colisão na SEFAZ
    if (_serieController.text == '1' || _serieController.text.isEmpty) {
      final userSerie = authService.usuarioAtual?.serieNfce;
      if (userSerie != null && userSerie > 0) {
        _serieController.text = userSerie.toString();
      } else {
        final empSerie = authService.empresaAtual?.serieNFCe;
        if (empSerie != null && empSerie.isNotEmpty) {
          _serieController.text = empSerie;
        }
      }
    }

    // Pegar todas as notas fiscais (filtramos apenas as modelo 55 / nfe)
    final todasNotas = [...dataService.nfes, ...dataService.nfces];
    final nfes = todasNotas.where((n) {
      if (n.modelo == 55) return true;
      if (n.chaveAcesso != null && n.chaveAcesso!.length == 44) {
        final mod = n.chaveAcesso!.substring(20, 22);
        return mod == '55';
      }
      final modelNum = int.tryParse(n.serie) ?? 1;
      return modelNum < 900;
    }).toList();

    nfes.sort((a, b) => b.dataEmissao.compareTo(a.dataEmissao));

    // Descobrir a próxima numeração automaticamente baseada na última nota cronológica emitida (não no maior número)
    if (_numeroController.text.isEmpty) {
      int ultimoNumeroEmitido = 0;
      if (nfes.isNotEmpty) {
        // Como nfes está ordenado por dataEmissao descrescente, o primeiro é o mais recente cronologicamente
        final maisRecente = nfes.first;
        final numInt = int.tryParse(maisRecente.numero.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (numInt <= 999999999) {
          ultimoNumeroEmitido = numInt;
        }
      }
      _numeroController.text = (ultimoNumeroEmitido + 1).toString();
    }

    final busca = _buscaController.text.toLowerCase().trim();
    final filtradas = nfes.where((n) {
      final bateBusca = n.numero.toString().contains(busca) ||
                        (n.nomeConsumidor?.toLowerCase().contains(busca) ?? false) ||
                        (n.chaveAcesso?.contains(busca) ?? false);

      bool bateStatus = true;
      if (_filtroStatus == 'Autorizada') {
        bateStatus = n.status == 'autorizada' || n.status == 'sucesso';
      } else if (_filtroStatus == 'Cancelada') {
        bateStatus = n.status == 'cancelada';
      } else if (_filtroStatus == 'Pendente/Rejeitada') {
        bateStatus = n.status != 'autorizada' && n.status != 'sucesso' && n.status != 'cancelada';
      }

      return bateBusca && bateStatus;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF13131A),
      appBar: AppBar(
        title: const Text('Emissor NF-e (Modelo 55)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_shopping_cart, color: Colors.greenAccent),
            tooltip: 'Faturar Vendas / Pedidos',
            onPressed: () => _abrirFaturamentoVendas(dataService),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            tooltip: 'Emitir Manualmente',
            onPressed: () => _abrirEmissaoManual(dataService),
          ),
          const SyncStatusWidget(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E2E),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _buscaController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar por Nº da NF-e, destinatário ou chave...',
                          hintStyle: const TextStyle(color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF13131A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Configuração de numeração direta na tela
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _numeroController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Próx. Nº NF-e',
                          labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFF13131A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _serieController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Série NF-e',
                          labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                          filled: true,
                          fillColor: const Color(0xFF13131A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        const Text(
                          'Homologação',
                          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: _ambienteHomologacao,
                          activeTrackColor: Colors.orange,
                          activeColor: Colors.white,
                          onChanged: (val) {
                            setState(() {
                              _ambienteHomologacao = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildDropdownFiltro(
                      label: 'Situação da Nota',
                      value: _filtroStatus,
                      items: ['Todos', 'Autorizada', 'Cancelada', 'Pendente/Rejeitada'],
                      onChanged: (val) => setState(() => _filtroStatus = val!),
                    ),
                  ],
                )
              ],
            ),
          ),
          
          Expanded(
            child: filtradas.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma NF-e modelo 55 encontrada.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtradas.length,
                    itemBuilder: (context, idx) {
                      final n = filtradas[idx];
                      final isAutorizada = n.status == 'autorizada' || n.status == 'sucesso';
                      final isCancelada = n.status == 'cancelada';

                      return Card(
                        color: const Color(0xFF1E1E2E),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isAutorizada
                                ? Colors.green.withValues(alpha: 0.4)
                                : (isCancelada ? Colors.grey.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.35)),
                            width: 1.2,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _mostrarDetalhesNfe(n, dataService),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Linha 1: Status badge + Número + Valor ──
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isAutorizada
                                            ? Colors.green.withValues(alpha: 0.2)
                                            : (isCancelada ? Colors.grey.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isAutorizada
                                                ? Icons.check_circle
                                                : (isCancelada ? Icons.cancel : Icons.error),
                                            color: isAutorizada
                                                ? Colors.greenAccent
                                                : (isCancelada ? Colors.grey : Colors.redAccent),
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isAutorizada ? 'Autorizada' : (isCancelada ? 'Cancelada' : 'Pendente'),
                                            style: TextStyle(
                                              color: isAutorizada
                                                  ? Colors.greenAccent
                                                  : (isCancelada ? Colors.grey : Colors.redAccent),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'NF-e Nº ${n.numero} | Série ${n.serie}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const Spacer(),
                                    Text(
                                      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(n.valorTotal),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // ── Linha 2: Destinatário ──
                                Text(
                                  'Destinatário: ${n.nomeConsumidor ?? "Não informado"}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),

                                // Exibir a Origem se faturada de Venda/Pedido, ou "Manual" se lançada sem origem
                                Builder(
                                  builder: (ctx) {
                                    final origem = _obterOrigemDinamica(n, dataService);
                                    final ehManual = origem == null;
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        children: [
                                          Icon(
                                            ehManual ? Icons.edit_note : (origem!.startsWith('PED') ? Icons.assignment_outlined : Icons.shopping_bag_outlined),
                                            size: 13,
                                            color: ehManual ? Colors.white38 : Colors.blueAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ehManual ? 'Faturamento Origem: Manual (sem pedido)' : 'Faturamento Origem: ' + origem!,
                                            style: TextStyle(
                                              color: ehManual ? Colors.white38 : Colors.blueAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                // ── Linha 3: Chave de Acesso ──
                                if (n.chaveAcesso != null && n.chaveAcesso!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () {
                                      // Copiar chave
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF13131A),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.key, color: Colors.blueAccent, size: 13),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              n.chaveAcesso!,
                                              style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                // ── Linha 4: Protocolo ──
                                if (n.protocolo != null && n.protocolo!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.verified_outlined, color: Colors.greenAccent, size: 13),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Protocolo: ${n.protocolo}',
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 10),

                                // ── Linha 5: Ações ──
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.copy, size: 16, color: Colors.orangeAccent),
                                      label: const Text('Clonar', style: TextStyle(color: Colors.orangeAccent)),
                                      onPressed: () => _abrirEmissaoManual(dataService, nfeExistente: n, clonar: true),
                                    ),
                                    const SizedBox(width: 4),
                                    if (isAutorizada) ...[
                                      TextButton.icon(
                                        icon: const Icon(Icons.print, size: 16),
                                        label: const Text('DANFE'),
                                        onPressed: () {
                                          final emp = authService.empresaAtual;
                                          if (emp != null) {
                                            DANFEService.visualizarPDF(context: context, nfce: n, empresa: emp);
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        icon: const Icon(Icons.cancel_presentation, size: 16, color: Colors.redAccent),
                                        label: const Text('Cancelar', style: TextStyle(color: Colors.redAccent)),
                                        onPressed: () => _cancelarNfe(n, dataService),
                                      ),
                                    ] else ...[
                                      TextButton.icon(
                                        icon: const Icon(Icons.edit, size: 16, color: Colors.blueAccent),
                                        label: const Text('Editar e Reemitir', style: TextStyle(color: Colors.blueAccent)),
                                        onPressed: () => _abrirEmissaoManual(dataService, nfeExistente: n),
                                      ),
                                    ]
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }


  Widget _buildDropdownFiltro({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF13131A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                items: items.map((val) {
                  return DropdownMenuItem<String>(
                    value: val,
                    child: Text(val),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          )
        ],
      ),
    );
  }

  void _cancelarNfe(NFCe nfce, DataService dataService) {
    final justificativaController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Cancelar NF-e', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: justificativaController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Justificativa (Mínimo 15 caracteres)',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (justificativaController.text.trim().length < 15) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Justificativa deve ter pelo menos 15 caracteres.'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx);
              
              try {
                final authService = Provider.of<AuthService>(context, listen: false);
                final service = NFCeServiceFactory.criar();
                await service.cancelarNFCe(
                  nfce: nfce,
                  empresa: authService.empresaAtual!,
                  justificativa: justificativaController.text.trim(),
                );
                
                final nfceCancelada = nfce.copyWith(status: 'cancelada');
                await dataService.atualizarNFCe(nfceCancelada);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ NF-e cancelada com sucesso!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                _exibirDialogoErro(e.toString());
              }
            },
            child: const Text('Cancelar Nota'),
          )
        ],
      ),
    );
  }

  void _abrirFaturamentoVendas(DataService dataService) {
    final Set<String> selecionadosLote = {};
    String filtroTipoLote = 'Todos';
    String filtroStatusLote = 'Todos';
    final buscaLoteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final vendas = dataService.vendasBalcao;
          final pedidos = dataService.pedidos;

          final List<Map<String, dynamic>> itensFaturaveis = [];
          
          // Mapeamento de notas autorizadas para identificar faturados
          final todasNotasFiscais = [...dataService.nfes, ...dataService.nfces];
          final autorizadasVendasIds = todasNotasFiscais
              .where((n) => n.vendaId != null)
              .map((n) => n.vendaId!)
              .toSet();
          
          final autorizadasVendasNums = todasNotasFiscais
              .where((n) => n.vendaNumero != null)
              .map((n) => n.vendaNumero!)
              .toSet();
          
          for (final v in vendas) {
            final jaFaturado = autorizadasVendasIds.contains(v.id) || autorizadasVendasNums.contains(v.numero);
            itensFaturaveis.add({
              'id': v.id,
              'numero': v.numero,
              'cliente': v.clienteNome ?? 'Consumidor Final',
              'clienteId': v.clienteId,
              'clienteCpfCnpj': v.clienteCpfCnpj,
              'data': v.dataVenda,
              'valor': v.valorTotal,
              'status': v.cancelado ? 'Cancelada' : 'Finalizada',
              'tipo': 'Venda',
              'origem': v,
              'faturado': jaFaturado,
            });
          }

          for (final p in pedidos) {
            final jaFaturado = autorizadasVendasIds.contains(p.id) || autorizadasVendasNums.contains(p.numero);
            itensFaturaveis.add({
              'id': p.id,
              'numero': p.numero,
              'cliente': p.clienteNome ?? 'Consumidor Final',
              'clienteId': p.clienteId,
              'clienteCpfCnpj': p.clienteCpfCnpj,
              'data': p.dataPedido,
              'valor': p.total,
              'status': p.status,
              'tipo': 'Pedido',
              'origem': p,
              'faturado': jaFaturado,
            });
          }

          itensFaturaveis.sort((a, b) => b['data'].compareTo(a['data']));

          final busca = buscaLoteController.text.toLowerCase().trim();
          final filtrados = itensFaturaveis.where((item) {
            final bateBusca = item['numero'].toString().toLowerCase().contains(busca) ||
                              item['cliente'].toString().toLowerCase().contains(busca);
            
            final bateTipo = filtroTipoLote == 'Todos' || item['tipo'] == filtroTipoLote;

            bool bateStatus = true;
            final st = item['status'].toString().toLowerCase();
            if (filtroStatusLote == 'Finalizados') {
              bateStatus = st.contains('finalizada') || st.contains('conclu') || st.contains('fechado') || st.contains('pago');
            } else if (filtroStatusLote == 'Abertos') {
              bateStatus = !st.contains('finalizada') && !st.contains('conclu') && !st.contains('fechado') && !st.contains('pago');
            }

            return bateBusca && bateTipo && bateStatus;
          }).toList();

          return Dialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 700,
              height: 600,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Faturar Vendas e Pedidos (NF-e)',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: buscaLoteController,
                    onChanged: (_) => setDialogState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Pesquise por Nº da venda/pedido ou cliente...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF13131A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildDropdownFiltroLote(
                        label: 'Origem',
                        value: filtroTipoLote,
                        items: ['Todos', 'Venda', 'Pedido'],
                        onChanged: (val) => setDialogState(() => filtroTipoLote = val!),
                      ),
                      const SizedBox(width: 12),
                      _buildDropdownFiltroLote(
                        label: 'Situação',
                        value: filtroStatusLote,
                        items: ['Todos', 'Finalizados', 'Abertos'],
                        onChanged: (val) => setDialogState(() => filtroStatusLote = val!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtrados.isEmpty
                        ? const Center(child: Text('Nenhum registro para faturamento.', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: filtrados.length,
                            itemBuilder: (context, index) {
                              final item = filtrados[index];
                              final id = item['id'] as String;
                              final selecionado = selecionadosLote.contains(id);

                              final jaFaturado = item['faturado'] == true;
                              return Card(
                                color: jaFaturado ? const Color(0xFF1B2C1C) : const Color(0xFF13131A),
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: jaFaturado 
                                  ? ListTile(
                                      title: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item['tipo'] == 'Venda' ? Colors.green.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(item['tipo'].toString().toUpperCase(), style: TextStyle(color: item['tipo'] == 'Venda' ? Colors.greenAccent : Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Nº ${item['numero']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                      subtitle: Text('Cliente: ${item['cliente']}\nValor: R\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check, color: Colors.greenAccent, size: 12),
                                                SizedBox(width: 4),
                                                Text('FATURADO', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.link_off, color: Colors.redAccent, size: 20),
                                            tooltip: 'Desfaturar (Exige Senha Master)',
                                            onPressed: () {
                                              _solicitarSenhaMaster(
                                                context: context,
                                                titulo: 'Desfaturar Venda/Pedido',
                                                mensagem: 'Tem certeza que deseja desfaturar a ' + item['tipo'] + ' Nº ' + item['numero'] + '? A nota correspondente será desvinculada e o recebível deletado.',
                                                onConfirmar: () async {
                                                  await _desfaturarRegistro(id, item['numero'], dataService);
                                                  setDialogState(() {
                                                    item['faturado'] = false;
                                                  });
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('✓ Registro desfaturado com sucesso!'), backgroundColor: Colors.green),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    )
                                  : CheckboxListTile(
                                      value: selecionado,
                                      title: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: item['tipo'] == 'Venda' ? Colors.green.withOpacity(0.15) : Colors.purple.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(item['tipo'].toString().toUpperCase(), style: TextStyle(color: item['tipo'] == 'Venda' ? Colors.greenAccent : Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 8),
                                          Text('Nº ${item['numero']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        ],
                                      ),
                                      subtitle: Text('Cliente: ${item['cliente']}\nValor: R\$ ${item['valor'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      activeColor: Colors.blue,
                                      onChanged: (val) {
                                        setDialogState(() {
                                          if (val == true) {
                                            selecionadosLote.add(id);
                                          } else {
                                            selecionadosLote.remove(id);
                                          }
                                        });
                                      },
                                    ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${selecionadosLote.length} selecionado(s)', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: selecionadosLote.isEmpty
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
                              },
                        child: const Text('Confirmar Seleção'),
                      )
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDropdownFiltroLote({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF13131A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E2E),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            items: items.map((val) {
              return DropdownMenuItem<String>(
                value: val,
                child: Text(val),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  void _validarEEmitir(List<Map<String, dynamic>> todosItens, DataService dataService) async {
    final selecionadosComInfo = todosItens.where((item) => _selecionados.contains(item['id'])).toList();
    
    for (var item in selecionadosComInfo) {
      final clienteId = item['clienteId'] as String?;
      Cliente? cliente;
      if (clienteId != null) {
        cliente = dataService.clientes.firstWhere((c) => c.id == clienteId, orElse: () => null as dynamic);
      }

      if (cliente == null || cliente.cpfCnpj == null || cliente.cpfCnpj!.isEmpty || cliente.cep == null || cliente.cep!.isEmpty) {
        _exibirIdentificarDestinatario(item, dataService, cliente, () {
          final atualizados = todosItens.map((i) {
            if (i['id'] == item['id']) {
              if (i['tipo'] == 'Venda') {
                final v = dataService.vendasBalcao.firstWhere((v) => v.id == item['id']);
                return {
                  ...i,
                  'clienteId': v.clienteId,
                  'cliente': v.clienteNome ?? 'Consumidor Final',
                  'clienteCpfCnpj': v.clienteCpfCnpj,
                };
              } else {
                final p = dataService.pedidos.firstWhere((p) => p.id == item['id']);
                return {
                  ...i,
                  'clienteId': p.clienteId,
                  'cliente': p.clienteNome ?? 'Consumidor Final',
                  'clienteCpfCnpj': p.clienteCpfCnpj,
                };
              }
            }
            return i;
          }).toList();
          _validarEEmitir(atualizados, dataService);
        });
        return;
      }
    }

    _confirmarEmissaoLote();
  }

  void _exibirIdentificarDestinatario(
    Map<String, dynamic>? item, 
    DataService dataService, 
    Cliente? clienteExistente, 
    VoidCallback? onSalvo,
    {Function(Cliente)? onDestinatarioDefinido}
  ) {
    Cliente? clienteSelecionado = clienteExistente;
    final cpfCnpjController = TextEditingController(text: clienteExistente?.cpfCnpj ?? '');
    final nomeController = TextEditingController(text: clienteExistente?.nome ?? '');
    final ieController = TextEditingController(text: clienteExistente?.rgIe ?? '');
    final cepController = TextEditingController(text: clienteExistente?.cep ?? '');
    final enderecoController = TextEditingController(text: clienteExistente?.endereco ?? '');
    final numeroController = TextEditingController(text: clienteExistente?.numero ?? '');
    final bairroController = TextEditingController(text: clienteExistente?.bairro ?? '');
    final cidadeController = TextEditingController(text: clienteExistente?.cidade ?? '');
    final estadoController = TextEditingController(text: clienteExistente?.estado ?? 'SP');
    bool cadastrarPermanentemente = false;
    bool buscandoCNPJ = false;
    String buscaCliente = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final clientes = dataService.clientes.where((c) {
            final query = buscaCliente.toLowerCase();
            return c.nome.toLowerCase().contains(query) || (c.cpfCnpj?.contains(query) ?? false);
          }).toList()
            ..sort((a, b) => a.nome.compareTo(b.nome));

          Future<void> consultarCNPJ(String cnpj) async {
            final cnpjLimpo = cnpj.replaceAll(RegExp(r'[^0-9]'), '');
            if (cnpjLimpo.length != 14) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('⚠️ Digite um CNPJ válido de 14 dígitos para pesquisar.'), backgroundColor: Colors.orange),
              );
              return;
            }

            setDialogState(() => buscandoCNPJ = true);

            try {
              final response = await http.get(Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$cnpjLimpo')).timeout(const Duration(seconds: 8));
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                setDialogState(() {
                  nomeController.text = data['razao_social'] ?? '';
                  cepController.text = data['cep'] ?? '';
                  enderecoController.text = '${data['tipo_logradouro'] ?? ''} ${data['logradouro'] ?? ''}'.trim();
                  numeroController.text = data['numero'] ?? '';
                  bairroController.text = data['bairro'] ?? '';
                  cidadeController.text = data['municipio'] ?? '';
                  estadoController.text = data['uf'] ?? 'SP';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✓ Dados cadastrais puxados do CNPJ!'), backgroundColor: Colors.green),
                );
              } else {
                throw Exception('CNPJ não encontrado.');
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('⚠️ Erro ao buscar CNPJ: ${e.toString()}'), backgroundColor: Colors.red),
              );
            } finally {
              setDialogState(() => buscandoCNPJ = false);
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: Row(
              children: [
                const Icon(Icons.business_outlined, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text('Destinatário NF-e ${item != null ? "- Venda ${item['numero']}" : "Manual"}', style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
            content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (clienteExistente == null) ...[
                      const Text('Buscar ou Escolher Cliente Cadastrado:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      const SizedBox(height: 6),
                      TextField(
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        onChanged: (val) {
                          setDialogState(() => buscaCliente = val);
                        },
                        decoration: InputDecoration(
                          hintText: 'Pesquise por nome, CPF ou CNPJ...',
                          hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 16),
                          filled: true,
                          fillColor: const Color(0xFF13131A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13131A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Cliente>(
                            value: clienteSelecionado,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E1E2E),
                            hint: const Text('Selecione na lista...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            items: clientes.take(30).map((c) {
                              return DropdownMenuItem<Cliente>(
                                value: c,
                                child: Text(c.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                clienteSelecionado = val;
                                if (val != null) {
                                  nomeController.text = val.nome;
                                  cpfCnpjController.text = val.cpfCnpj ?? '';
                                  ieController.text = val.rgIe ?? '';
                                  cepController.text = val.cep ?? '';
                                  enderecoController.text = val.endereco ?? '';
                                  numeroController.text = val.numero ?? '';
                                  bairroController.text = val.bairro ?? '';
                                  cidadeController.text = val.cidade ?? '';
                                  estadoController.text = val.estado ?? 'SP';
                                }
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Divider(color: Colors.white10),
                    ],

                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cpfCnpjController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'CPF / CNPJ (Apenas números)',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: buscandoCNPJ
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.blue)))
                              : const Icon(Icons.search, color: Colors.blueAccent),
                          tooltip: 'Puxar dados do CNPJ na Receita',
                          onPressed: () => consultarCNPJ(cpfCnpjController.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nomeController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Razão Social / Nome Completo',
                        labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: ieController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Inscrição Estadual (IE) / RG',
                        labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                    ),
                    
                    const SizedBox(height: 14),
                    const Text('Endereço Destinatário:', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cepController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'CEP',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: enderecoController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Logradouro (Rua, Av, etc)',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: numeroController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Número',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: bairroController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Bairro',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: cidadeController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Cidade',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: estadoController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Estado (UF)',
                              labelStyle: TextStyle(color: Colors.grey, fontSize: 12),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    if (clienteExistente == null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Checkbox(
                            value: cadastrarPermanentemente,
                            activeColor: Colors.blue,
                            onChanged: (val) {
                              setDialogState(() => cadastrarPermanentemente = val ?? false);
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Cadastrar este cliente permanentemente no sistema',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  if (nomeController.text.trim().isEmpty || cepController.text.trim().isEmpty || enderecoController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('⚠️ Preencha Nome, CEP e Endereço obrigatórios.'), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  String finalClienteId = clienteSelecionado?.id ?? '';
                  String finalClienteNome = nomeController.text.trim();
                  String finalClienteCpfCnpj = cpfCnpjController.text.trim();

                  if (cadastrarPermanentemente && clienteSelecionado == null) {
                    final novoCliente = Cliente(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      nome: finalClienteNome,
                      cpfCnpj: finalClienteCpfCnpj,
                      rgIe: ieController.text.trim(),
                      telefone: '00000000000',
                      cep: cepController.text.trim(),
                      endereco: enderecoController.text.trim(),
                      numero: numeroController.text.trim(),
                      bairro: bairroController.text.trim(),
                      cidade: cidadeController.text.trim(),
                      estado: estadoController.text.trim(),
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    await dataService.addCliente(novoCliente);
                    finalClienteId = novoCliente.id;
                    clienteSelecionado = novoCliente;
                  } else if (clienteSelecionado != null) {
                    final clienteAtualizado = clienteSelecionado!.copyWith(
                      nome: finalClienteNome,
                      cpfCnpj: finalClienteCpfCnpj,
                      rgIe: ieController.text.trim(),
                      cep: cepController.text.trim(),
                      endereco: enderecoController.text.trim(),
                      numero: numeroController.text.trim(),
                      bairro: bairroController.text.trim(),
                      cidade: cidadeController.text.trim(),
                      estado: estadoController.text.trim(),
                    );
                    await dataService.updateCliente(clienteAtualizado);
                    finalClienteId = clienteAtualizado.id;
                    clienteSelecionado = clienteAtualizado;
                  }

                  if (onDestinatarioDefinido != null && clienteSelecionado != null) {
                    Navigator.pop(ctx);
                    onDestinatarioDefinido(clienteSelecionado!);
                    return;
                  }

                  final id = item!['id'] as String;
                  if (item['tipo'] == 'Venda') {
                    final index = dataService.vendasBalcao.indexWhere((v) => v.id == id);
                    if (index != -1) {
                      final vendaOriginal = dataService.vendasBalcao[index];
                      final vendaAtualizada = vendaOriginal.copyWith(
                        clienteId: finalClienteId,
                        clienteNome: finalClienteNome,
                        clienteCpfCnpj: finalClienteCpfCnpj,
                      );
                      await dataService.updateVendaBalcao(vendaAtualizada);
                    }
                  } else {
                    final index = dataService.pedidos.indexWhere((p) => p.id == id);
                    if (index != -1) {
                      final pedidoOriginal = dataService.pedidos[index];
                      final pedidoAtualizado = pedidoOriginal.copyWith(
                        clienteId: finalClienteId,
                        clienteNome: finalClienteNome,
                        clienteCpfCnpj: finalClienteCpfCnpj,
                      );
                      await dataService.updatePedido(pedidoAtualizado);
                    }
                  }

                  Navigator.pop(ctx);
                  onSalvo?.call();
                },
                child: const Text('Vincular & Avançar'),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _obterOrigemDinamica(NFCe nfe, DataService dataService) {
    // A origem só existe quando a nota foi faturada a partir de uma venda/pedido.
    // Notas lançadas manualmente NÃO têm origem — sem fallback por CPF/valor,
    // que associava notas manuais a pedidos errados (ex: "Pedido 49 - Nota 5").
    if (nfe.vendaNumero != null && nfe.vendaNumero!.isNotEmpty) {
      return nfe.vendaNumero;
    }
    if (nfe.vendaId != null && nfe.vendaId!.isNotEmpty) {
      try {
        final v = dataService.vendasBalcao.firstWhere((v) => v.id == nfe.vendaId);
        return v.numero;
      } catch (_) {}
      try {
        final p = dataService.pedidos.firstWhere((p) => p.id == nfe.vendaId);
        return p.numero;
      } catch (_) {}
    }
    return null;
  }

  void _solicitarSenhaMaster({
    required BuildContext context,
    required String titulo,
    required String mensagem,
    required VoidCallback onConfirmar,
  }) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    final senhaDefinida = empresa?.configuracoes?['senha_admin']?.toString() ?? '';

    if (senhaDefinida.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Configure uma Senha Master Admin nas configurações da empresa para liberar o desfaturamento.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensagem, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Senha Master Admin',
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (controller.text.trim() == senhaDefinida.trim()) {
                Navigator.pop(ctx);
                onConfirmar();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Senha Master Incorreta.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _desfaturarRegistro(String id, String numero, DataService dataService) async {
    // 1. Procurar NF-e associada
    NFCe? nfeAssociada;
    try {
      final todasNotasFiscais = [...dataService.nfes, ...dataService.nfces];
      nfeAssociada = todasNotasFiscais.firstWhere(
        (n) => n.vendaId == id || n.vendaNumero == numero,
      );
    } catch (_) {}

    if (nfeAssociada != null) {
      // Desvincular e cancelar nota fiscal local/Supabase
      final nfeAtualizada = nfeAssociada.copyWith(
        vendaId: null,
        vendaNumero: null,
        status: 'cancelada',
      );
      await dataService.atualizarNFCe(nfeAtualizada);

      // 2. Procurar e remover Conta a Receber correspondente
      try {
        final contas = dataService.contasPagar.where(
          (c) => c.numero == 'CR-' + nfeAssociada!.numero.toString() || c.descricao.contains('NF-e Nº ' + nfeAssociada.numero.toString()),
        ).toList();
        for (var c in contas) {
          dataService.deleteContaPagar(c.id);
        }
      } catch (_) {}
    }
  }

  void _abrirFaturamentoManual({
    Map<String, dynamic>? venda,
    Map<String, dynamic>? pedido,
    List<Map<String, dynamic>>? lote,
  }) {
    final dataService = Provider.of<DataService>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => _EmissaoManualPage(
        dataService: dataService,
        vendaFaturar: venda,
        pedidoFaturar: pedido,
        loteFaturar: lote,
        numeroController: _numeroController,
        serieController: _serieController,
        ambienteHomologacao: _ambienteHomologacao,
        onEmitida: () {
          setState(() {
            _selecionados.clear();
          });
        },
      ),
    );
  }

  void _confirmarEmissaoLote() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Confirmar Emissão', style: TextStyle(color: Colors.white)),
        content: Text(
          'Deseja faturar e emitir NF-e (Modelo 55) para os ${_selecionados.length} registros selecionados?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              Navigator.pop(ctx);
              
              final dataService = Provider.of<DataService>(context, listen: false);
              final authService = Provider.of<AuthService>(context, listen: false);
              final empresa = authService.empresaAtual;
              
              if (empresa == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Nenhuma empresa selecionada para faturamento.'), backgroundColor: Colors.red),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.blue)),
                      SizedBox(width: 16),
                      Text('Transmitindo NF-e para a SEFAZ...'),
                    ],
                  ),
                  duration: Duration(seconds: 4),
                  backgroundColor: Colors.black87,
                ),
              );

              final service = NFCeServiceFactory.criar();
              int emitidas = 0;
              int erros = 0;

              for (final id in _selecionados) {
                try {
                  final indexVenda = dataService.vendasBalcao.indexWhere((v) => v.id == id);
                  if (indexVenda != -1) {
                    final venda = dataService.vendasBalcao[indexVenda];
                    
                    // Recuperar número e série do input da tela
                    final numForcado = int.tryParse(_numeroController.text);
                    final serieForcada = int.tryParse(_serieController.text);

                    // Busca o cliente completo para obter o endereço (necessário NF-e mod. 55)
                    final clienteCompleto = venda.clienteId != null
                        ? dataService.clientes.where((c) => c.id == venda.clienteId).firstOrNull
                        : null;

                    final responseNfce = await service.emitir(
                      empresa: empresa,
                      produtos: venda.itens.map((i) => Produto(
                        id: i.id,
                        nome: i.nome,
                        preco: i.precoUnitario,
                        unidade: 'UN',
                        grupo: 'Geral',
                        estoque: 0,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                        exibirNaLoja: false,
                        emDestaque: false,
                        fotosUrls: [],
                        codigosFornecedor: [],
                      )).toList(),
                      quantidades: { for (var i in venda.itens) i.id : i.quantidade },
                      pagamentos: [
                        NFCePagamento(
                          tipo: '99',
                          valor: venda.valorTotal,
                        )
                      ],
                      valorTotal: venda.valorTotal,
                      cpfCnpjConsumidor: venda.clienteCpfCnpj,
                      nomeConsumidor: venda.clienteNome,
                      vendaId: venda.id,
                      vendaNumero: venda.numero,
                      ambienteHomologacao: _ambienteHomologacao,
                      modelo: 55, // Força Modelo 55 (NF-e)
                      serie: serieForcada,
                      numero: numForcado,
                      // Endereço do destinatário para NF-e modelo 55
                      destLogradouro: clienteCompleto?.endereco,
                      destNumero: clienteCompleto?.numero,
                      destComplemento: clienteCompleto?.complemento,
                      destBairro: clienteCompleto?.bairro,
                      destMunicipio: clienteCompleto?.cidade,
                      destUf: clienteCompleto?.estado,
                      destCep: clienteCompleto?.cep,
                    );

                    
                    final nfceFinal = responseNfce.copyWith(
                      nomeConsumidor: venda.clienteNome ?? responseNfce.nomeConsumidor,
                    );
                    
                    await dataService.adicionarNFCe(nfceFinal);
                    emitidas++;

                    // Se a emissão foi ok e forçamos o número, incrementa o contador local
                    if (numForcado != null) {
                      _numeroController.text = (numForcado + 1).toString();
                    }
                  }
                } catch (e) {
                  debugPrint('>>> [NfePage] ❌ Erro de transmissão no lote ID $id: $e');
                  erros++;
                }
              }

              if (!mounted) return;
              setState(() {
                _selecionados.clear();
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ Processamento concluído! Emitidas com sucesso: $emitidas. Falhas: $erros.'),
                  backgroundColor: erros > 0 ? Colors.orange : Colors.green,
                ),
              );
            },
            child: const Text('Emitir'),
          )
        ],
      ),
    );
  }

  void _abrirEmissaoManual(DataService dataService, {NFCe? nfeExistente, bool clonar = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _EmissaoManualPage(
          dataService: dataService,
          nfeExistente: nfeExistente,
          clonar: clonar,
          numeroController: _numeroController,
          serieController: _serieController,
          ambienteHomologacao: _ambienteHomologacao,
          onEmitida: () => setState(() {}),
        ),
      ),
    );
  }


  void _exibirDialogoErro(String mensagem) {

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Falha na Emissão',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensagem.replaceAll('Exception:', '').trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D2D3F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Entendido',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhesNfe(NFCe n, DataService dataService) {
    showDialog(
      context: context,
      builder: (context) {
        final isAutorizada = n.status == 'autorizada' || n.status == 'sucesso';
        final isCancelada = n.status == 'cancelada';
        
        return Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Detalhes da NF-e Nº ${n.numero}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Status
                  Row(
                    children: [
                      Icon(
                        isAutorizada 
                            ? Icons.check_circle 
                            : (isCancelada ? Icons.cancel : Icons.error),
                        color: isAutorizada 
                            ? Colors.green 
                            : (isCancelada ? Colors.grey : Colors.red),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        n.status?.toUpperCase() ?? 'PENDENTE / REJEITADA',
                        style: TextStyle(
                          color: isAutorizada 
                              ? Colors.green 
                              : (isCancelada ? Colors.grey : Colors.red),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  
                  // Informações Gerais
                  const Text('DADOS GERAIS', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Série:', n.serie),
                  _buildDetailRow('Modelo:', '55 (Nota Fiscal Eletrônica)'),
                  _buildDetailRow('Data de Emissão:', DateFormat('dd/MM/yyyy HH:mm').format(n.dataEmissao)),
                  if (n.chaveAcesso != null && n.chaveAcesso!.isNotEmpty)
                    _buildDetailRow('Chave de Acesso:', n.chaveAcesso!),
                  if (n.protocolo != null && n.protocolo!.isNotEmpty)
                    _buildDetailRow('Protocolo:', n.protocolo!),
                  Builder(
                    builder: (ctx) {
                      final origem = _obterOrigemDinamica(n, dataService);
                      return _buildDetailRow(
                        'Origem do Faturamento:',
                        origem ?? 'Manual (sem pedido)',
                      );
                    },
                  ),
                  
                  const Divider(color: Colors.white12, height: 24),
                  
                  // Destinatário
                  const Text('DESTINATÁRIO', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Nome/Razão Social:', n.nomeConsumidor ?? 'Não informado'),
                  _buildDetailRow('CPF/CNPJ:', n.cpfCnpjConsumidor ?? 'Não informado'),
                  
                  const Divider(color: Colors.white12, height: 24),
                  
                  // Itens
                  const Text('ITENS DA NOTA', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  if (n.itens.isEmpty)
                    const Text('Nenhum item adicionado', style: TextStyle(color: Colors.white60, fontSize: 13))
                  else
                    ...n.itens.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.descricao, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  Text('Cód: ${item.codigo} | NCM: ${item.ncm}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text(
                              '${item.quantidade}x R\$ ${item.valorUnitario.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      );
                    }),
                  
                  const Divider(color: Colors.white12, height: 24),
                  
                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('VALOR TOTAL:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      Text(
                        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(n.valorTotal),
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Botões de Ações
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar', style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 16, color: Colors.orangeAccent),
                        label: const Text('Clonar', style: TextStyle(color: Colors.orangeAccent)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orangeAccent),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _abrirEmissaoManual(dataService, nfeExistente: n, clonar: true);
                        },
                      ),
                      if (!isAutorizada) ...[
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Editar e Reemitir'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                          onPressed: () {
                            Navigator.pop(context);
                            _abrirEmissaoManual(dataService, nfeExistente: n);
                          },
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// TELA COMPLETA DE EMISSÃO MANUAL DE NF-e
// ─────────────────────────────────────────────────────────
class _EmissaoManualPage extends StatefulWidget {
  final DataService dataService;
  final NFCe? nfeExistente;
  final bool clonar; // true = clone de nota existente (número avança automaticamente)
  final Map<String, dynamic>? vendaFaturar;
  final Map<String, dynamic>? pedidoFaturar;
  final List<Map<String, dynamic>>? loteFaturar; // Para quando selecionar multiplos e consolidar
  final TextEditingController numeroController;
  final TextEditingController serieController;
  final bool ambienteHomologacao;
  final VoidCallback onEmitida;

  const _EmissaoManualPage({
    required this.dataService,
    this.nfeExistente,
    this.clonar = false,
    this.vendaFaturar,
    this.pedidoFaturar,
    this.loteFaturar,
    required this.numeroController,
    required this.serieController,
    required this.ambienteHomologacao,
    required this.onEmitida,
  });

  @override
  State<_EmissaoManualPage> createState() => _EmissaoManualPageState();
}

class _EmissaoManualPageState extends State<_EmissaoManualPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Finalidade e Devolução ──
  int _finalidade = 1; // 1 = Normal, 4 = Devolução
  final _natOpCtrl = TextEditingController(text: 'VENDA DE MERCADORIA');
  final _chaveRefCtrl = TextEditingController();

  // ── Modelo, Tipo de Emissão e Regime Tributário ──
  int _modelo = 55; // 55 = NF-e, 65 = NFC-e
  int _tpEmis = 1;  // 1=Normal, 2=FS, 3=SCAN, 4=DPEC, 5=FS-DA, 6=SVC-AN, 7=SVC-RS, 9=Off-line
  int _crt = 1;     // 1=Simples Nacional, 2=SN Excesso, 3=Regime Normal

  // ── Destinatário ──
  Cliente? _clienteSelecionado;
  final _nomeDestCtrl = TextEditingController();
  final _docDestCtrl = TextEditingController();
  final _logradouroCtrl = TextEditingController();
  final _numEndCtrl = TextEditingController();
  final _complCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _ufCtrl = TextEditingController();
  final _cepCtrl = TextEditingController();
  final _foneCtrl = TextEditingController();
  final _emailDestCtrl = TextEditingController();
  String _indIE = '9'; // 1=Contribuinte, 2=Isento, 9=Não contribuinte

  // ── Itens ──
  final List<Map<String, dynamic>> _itens = [];
  String _buscaProduto = '';
  Produto? _produtoTemp;
  final _qtdCtrl = TextEditingController(text: '1');
  final _precoCtrl = TextEditingController();
  final _ncmItemCtrl = TextEditingController(text: '00000000');
  final _cfopCtrl = TextEditingController(text: '5102');
  final _unidCtrl = TextEditingController(text: 'UN');
  final _descItemCtrl = TextEditingController();

  // ── Impostos globais (aplicados a todos os itens por padrão) ──
  final _csosnCtrl = TextEditingController(text: '400');
  final _icmsCstCtrl = TextEditingController();
  final _pisCstCtrl = TextEditingController(text: '07');
  final _cofinsCstCtrl = TextEditingController(text: '07');
  final _icmsAliqCtrl = TextEditingController(text: '0.00');
  final _ipiCstCtrl = TextEditingController();

  // Destaque de ICMS e Crédito do Simples Nacional (NT 2025.002 / CSOSN 900)
  final _icmsReducaoBcCtrl = TextEditingController(text: '0.00');
  final _icmsBaseCalculoCtrl = TextEditingController(text: '0.00');
  final _icmsValorCtrl = TextEditingController(text: '0.00');
  final _creditoAliqCtrl = TextEditingController(text: '0.00');
  final _creditoValorCtrl = TextEditingController(text: '0.00');
  bool _destacarIcmsNormalVal = false;

  // ── Despesas Acessórias ──
  final _freteValorCtrl = TextEditingController(text: '0.00');
  final _seguroValorCtrl = TextEditingController(text: '0.00');
  final _outrasDespCtrl = TextEditingController(text: '0.00');

  // ── Transportadora ──
  String _modFrete = '9'; // 9 = Sem ocorrência de transporte
  final _transpNomeCtrl = TextEditingController();
  final _transpCnpjCtrl = TextEditingController();
  final _transpInscEstCtrl = TextEditingController();
  final _transpEndCtrl = TextEditingController();
  final _transpMunicipioCtrl = TextEditingController();
  final _transpUfCtrl = TextEditingController();
  final _transpPlacaCtrl = TextEditingController();
  final _transpPlacaUfCtrl = TextEditingController();
  final _transpQtdVolCtrl = TextEditingController();
  final _transpEspecieVolCtrl = TextEditingController();
  final _transpPesoBVolCtrl = TextEditingController();
  final _transpPesoLVolCtrl = TextEditingController();

  // ── Pagamento ──
  String _tipoPagamento = '01'; // 01=Dinheiro, 03=Cartão Crédito, 04=Cartão Débito, 99=Outros

  // ── Emissão ──
  bool _emitindo = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Regime tributário padrão vindo do cadastro da empresa
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa != null) {
        final crtConfig = empresa.configuracoes?['crt'];
        final crtInt = int.tryParse(crtConfig?.toString() ?? '');
        if (crtInt != null && crtInt >= 1 && crtInt <= 3) {
          _crt = crtInt;
        } else if (empresa.crt != null && empresa.crt! >= 1 && empresa.crt! <= 3) {
          _crt = empresa.crt!;
        }
      }
    } catch (_) {}
    _popularDadosExistentes();
  }

  void _popularDadosExistentes() {
    // ─── CASO 1: FATURAR UMA VENDA OU PEDIDO ───
    if (widget.vendaFaturar != null || widget.pedidoFaturar != null || widget.loteFaturar != null) {
      final String? clienteId = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['clienteId'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['clienteId'] : null);
          
      final String? clienteNome = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['cliente'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['cliente'] : null);

      final String? clienteCpfCnpj = widget.vendaFaturar != null 
          ? widget.vendaFaturar!['clienteCpfCnpj'] 
          : (widget.pedidoFaturar != null ? widget.pedidoFaturar!['clienteCpfCnpj'] : null);

      if (clienteId != null) {
        try {
          _clienteSelecionado = widget.dataService.clientes.firstWhere((c) => c.id == clienteId);
        } catch (_) {}
      }

      _nomeDestCtrl.text = clienteNome ?? 'Consumidor Final';
      _docDestCtrl.text = clienteCpfCnpj ?? '';

      if (_clienteSelecionado != null) {
        _logradouroCtrl.text = _clienteSelecionado!.endereco ?? '';
        _numEndCtrl.text = _clienteSelecionado!.numero ?? '';
        _complCtrl.text = _clienteSelecionado!.complemento ?? '';
        _bairroCtrl.text = _clienteSelecionado!.bairro ?? '';
        _municipioCtrl.text = _clienteSelecionado!.cidade ?? '';
        _ufCtrl.text = _clienteSelecionado!.estado ?? '';
        _cepCtrl.text = _clienteSelecionado!.cep ?? '';
        _emailDestCtrl.text = _clienteSelecionado!.email ?? '';
        _foneCtrl.text = _clienteSelecionado!.telefone;
      }

      // Adicionar itens da venda/pedido
      List<dynamic> itensOriginais = [];
      if (widget.vendaFaturar != null) {
        final idVenda = widget.vendaFaturar!['id'];
        try {
          final v = widget.dataService.vendasBalcao.firstWhere((v) => v.id == idVenda);
          itensOriginais = v.itens;
        } catch (_) {}
      } else if (widget.pedidoFaturar != null) {
        final idPed = widget.pedidoFaturar!['id'];
        try {
          final p = widget.dataService.pedidos.firstWhere((p) => p.id == idPed);
          itensOriginais = p.produtos;
        } catch (_) {}
      } else if (widget.loteFaturar != null) {
        // Consolidação em lote
        for (var itemLote in widget.loteFaturar!) {
          final idLote = itemLote['id'];
          if (itemLote['tipo'] == 'Venda') {
            try {
              final v = widget.dataService.vendasBalcao.firstWhere((v) => v.id == idLote);
              itensOriginais.addAll(v.itens);
            } catch (_) {}
          } else {
            try {
              final p = widget.dataService.pedidos.firstWhere((p) => p.id == idLote);
              itensOriginais.addAll(p.produtos);
            } catch (_) {}
          }
        }
      }

      // Mapear itens para a listagem da UI
      for (final item in itensOriginais) {
        Produto? prod;
        try {
          prod = widget.dataService.produtos.firstWhere((p) => p.id == item.id);
        } catch (_) {
          prod = Produto(
            id: item.produtoId,
            nome: item.nome,
            preco: item.precoUnitario,
            unidade: 'UN',
            grupo: 'Geral',
            estoque: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            exibirNaLoja: false,
            emDestaque: false,
            fotosUrls: [],
            codigosFornecedor: [],
          );
        }
        
        _itens.add({
          'produto': prod,
          'qtd': item.quantidade,
          'preco': item.precoUnitario,
          'ncm': prod.ncm ?? '00000000',
          'cfop': _cfopCtrl.text,
          'unidade': prod.unidade ?? 'UN',
          'descricao': item.nome,
        });
      }
      return;
    }

    // ─── CASO 2: REEMISSÃO / CLONE DE NOTA EXISTENTE ───
    final nfe = widget.nfeExistente;
    if (nfe == null) return;

    // Modelo: 55 (NF-e) ou 65 (NFC-e) — vem da nota original
    if (nfe.modelo == 55 || nfe.modelo == 65) {
      _modelo = nfe.modelo!;
    }

    // Forma de pagamento original
    if (nfe.pagamentos.isNotEmpty) {
      final tipoOrig = nfe.pagamentos.first.tipo;
      const tiposValidos = ['01', '03', '04', '05', '15', '17', '99'];
      if (tiposValidos.contains(tipoOrig)) {
        _tipoPagamento = tipoOrig;
      }
    }

    // Destinatário
    if (nfe.cpfCnpjConsumidor != null && nfe.cpfCnpjConsumidor!.isNotEmpty) {
      final docLimpo = nfe.cpfCnpjConsumidor!.replaceAll(RegExp(r'[^\d]'), '');
      try {
        _clienteSelecionado = widget.dataService.clientes
            .firstWhere((c) => (c.cpfCnpj ?? '').replaceAll(RegExp(r'[^\d]'), '') == docLimpo);
      } catch (_) {}
      _docDestCtrl.text = nfe.cpfCnpjConsumidor!;
    }
    _nomeDestCtrl.text = nfe.nomeConsumidor ?? '';

    if (_clienteSelecionado != null) {
      _logradouroCtrl.text = _clienteSelecionado!.endereco ?? '';
      _numEndCtrl.text = _clienteSelecionado!.numero ?? '';
      _complCtrl.text = _clienteSelecionado!.complemento ?? '';
      _bairroCtrl.text = _clienteSelecionado!.bairro ?? '';
      _municipioCtrl.text = _clienteSelecionado!.cidade ?? '';
      _ufCtrl.text = _clienteSelecionado!.estado ?? '';
      _cepCtrl.text = _clienteSelecionado!.cep ?? '';
      _emailDestCtrl.text = _clienteSelecionado!.email ?? '';
      _foneCtrl.text = _clienteSelecionado!.telefone;
    }

    // Itens — mantém NCM/CFOP/CSOSN/CST e impostos da nota original
    for (final item in nfe.itens) {
      Produto? prod;
      try {
        prod = widget.dataService.produtos.firstWhere(
          (p) => p.id == item.produtoId || (p.codigo != null && p.codigo == item.codigo),
        );
      } catch (_) {
        prod = Produto(
          id: item.produtoId,
          nome: item.descricao,
          preco: item.valorUnitario,
          unidade: item.unidade,
          grupo: 'Geral',
          estoque: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          exibirNaLoja: false,
          emDestaque: false,
          fotosUrls: [],
          codigosFornecedor: [],
          ncm: item.ncm,
          csosn: item.csosn,
          icmsCst: item.icmsCst,
          icmsAliquota: item.icmsAliquota,
        );
      }
      _itens.add({
        'produto': prod,
        'qtd': item.quantidade,
        'preco': item.valorUnitario,
        'ncm': item.ncm.isNotEmpty ? item.ncm : (prod.ncm ?? '00000000'),
        'cfop': item.cfop.isNotEmpty ? item.cfop : '5102',
        'unidade': item.unidade,
        'descricao': item.descricao,
      });
    }

    // Número: no clone avança automaticamente (evita repetir o número da SEFAZ);
    // na reemissão de nota rejeitada/pendente mantém o número original
    if (widget.clonar) {
      final numOriginal = int.tryParse(nfe.numero) ?? 0;
      widget.numeroController.text = (numOriginal + 1).toString();
    } else {
      widget.numeroController.text = nfe.numero;
    }
    widget.serieController.text = nfe.serie;
  }

  void _preencherDestinatarioPorCliente(Cliente c) {
    setState(() {
      _clienteSelecionado = c;
      _nomeDestCtrl.text = c.nome;
      _docDestCtrl.text = c.cpfCnpj ?? '';
      _logradouroCtrl.text = c.endereco ?? '';
      _numEndCtrl.text = c.numero ?? '';
      _complCtrl.text = c.complemento ?? '';
      _bairroCtrl.text = c.bairro ?? '';
      _municipioCtrl.text = c.cidade ?? '';
      _ufCtrl.text = c.estado ?? '';
      _cepCtrl.text = c.cep ?? '';
      _emailDestCtrl.text = c.email ?? '';
      _foneCtrl.text = c.telefone;
    });
  }

  double get _total =>
      _itens.fold(0.0, (sum, i) => sum + ((i['preco'] as double) * (i['qtd'] as double)));

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF13131A),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blueAccent)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _nomeDestCtrl, _docDestCtrl, _logradouroCtrl, _numEndCtrl, _complCtrl,
      _bairroCtrl, _municipioCtrl, _ufCtrl, _cepCtrl, _foneCtrl, _emailDestCtrl,
      _qtdCtrl, _precoCtrl, _ncmItemCtrl, _cfopCtrl, _unidCtrl, _descItemCtrl,
      _csosnCtrl, _icmsCstCtrl, _pisCstCtrl, _cofinsCstCtrl, _icmsAliqCtrl, _ipiCstCtrl,
      _natOpCtrl, _chaveRefCtrl, _freteValorCtrl, _seguroValorCtrl, _outrasDespCtrl,
      _transpNomeCtrl, _transpCnpjCtrl, _transpInscEstCtrl, _transpEndCtrl,
      _transpMunicipioCtrl, _transpUfCtrl, _transpPlacaCtrl, _transpPlacaUfCtrl,
      _transpQtdVolCtrl, _transpEspecieVolCtrl, _transpPesoBVolCtrl, _transpPesoLVolCtrl,
      _icmsReducaoBcCtrl, _icmsBaseCalculoCtrl, _icmsValorCtrl, _creditoAliqCtrl, _creditoValorCtrl,
    ]) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF13131A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        elevation: 0,
        title: Text(
          widget.clonar
              ? 'Clonar Nota Nº ${widget.nfeExistente?.numero ?? ''}'
              : (widget.nfeExistente != null ? 'Editar e Reemitir NF-e' : 'Nova NF-e Manual'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Destinatário'),
            Tab(icon: Icon(Icons.list_alt), text: 'Itens'),
            Tab(icon: Icon(Icons.account_balance_outlined), text: 'Impostos'),
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Transporte'),
          ],
        ),
        actions: [
          // Número e Série
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: TextField(
                controller: widget.numeroController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Nº NF-e',
                  labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF13131A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 65,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: TextField(
                controller: widget.serieController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Série',
                  labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 10),
                  filled: true,
                  fillColor: const Color(0xFF13131A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (widget.clonar) ...[
            Container(
              width: double.infinity,
              color: const Color(0xFF33291A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.copy_all, size: 18, color: Colors.orangeAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Clonando a nota Nº ${widget.nfeExistente?.numero ?? ''} — os dados foram copiados e o número avançado automaticamente. Confira antes de emitir.',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabDestinatario(),
                _buildTabItens(),
                _buildTabImpostos(),
                _buildTabTransporte(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: const Color(0xFF1E1E2E),
        child: Row(
          children: [
            // Pagamento
            const Text('Pagamento:', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: _tipoPagamento,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '01', child: Text('Dinheiro')),
                DropdownMenuItem(value: '03', child: Text('Cartão Crédito')),
                DropdownMenuItem(value: '04', child: Text('Cartão Débito')),
                DropdownMenuItem(value: '05', child: Text('Crédito Loja')),
                DropdownMenuItem(value: '15', child: Text('Boleto')),
                DropdownMenuItem(value: '17', child: Text('PIX')),
                DropdownMenuItem(value: '99', child: Text('Outros')),
              ],
              onChanged: (v) => setState(() => _tipoPagamento = v!),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ICMS Estimado: R\$ ${( _total * (double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0) / 100 ).toStringAsFixed(2)}  ',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    if (double.tryParse(_freteValorCtrl.text) != null && double.tryParse(_freteValorCtrl.text)! > 0)
                      Text(
                        'Frete: R\$ ${double.tryParse(_freteValorCtrl.text)!.toStringAsFixed(2)}  ',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
                Text(
                  'Total Geral: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_total + (double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0) + (double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0))}',
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(width: 16),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
                side: const BorderSide(color: Colors.orangeAccent),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Gravar Nota', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _emitindo ? null : () => _gravarNotaSemTransmitir(authService),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _emitindo
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text(_emitindo ? 'Emitindo...' : 'Gerar e Emitir', style: const TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _emitindo ? null : () => _emitir(authService),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ABA 1: DESTINATÁRIO ────────────────────────────────
  Widget _buildTabDestinatario() {
    final clientes = widget.dataService.clientes
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── DADOS DA OPERAÇÃO ───
          const Text('DADOS DA OPERAÇÃO', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),

          // ── Modelo, Tipo de Emissão e Regime Tributário ──
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _modelo,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _dec('Modelo'),
                items: const [
                  DropdownMenuItem(value: 65, child: Text('65 – NFC-e (Consumidor)')),
                  DropdownMenuItem(value: 55, child: Text('55 – NF-e (Empresa)')),
                ],
                onChanged: (v) {
                  setState(() {
                    _modelo = v!;
                    if (_modelo == 65) {
                      _natOpCtrl.text = 'VENDA AO CONSUMIDOR';
                    } else {
                      _natOpCtrl.text = 'VENDA DE MERCADORIA';
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _tpEmis,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _dec('Tipo de Emissão'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 – Normal')),
                  DropdownMenuItem(value: 2, child: Text('2 – Contingência FS')),
                  DropdownMenuItem(value: 3, child: Text('3 – Contingência SCAN')),
                  DropdownMenuItem(value: 4, child: Text('4 – Contingência DPEC')),
                  DropdownMenuItem(value: 5, child: Text('5 – Contingência FS-DA')),
                  DropdownMenuItem(value: 6, child: Text('6 – Contingência SVC-AN')),
                  DropdownMenuItem(value: 7, child: Text('7 – Contingência SVC-RS')),
                  DropdownMenuItem(value: 9, child: Text('9 – Off-line')),
                ],
                onChanged: (v) => setState(() => _tpEmis = v!),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _crt,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _dec('Regime Tributário'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 – Simples Nacional')),
                  DropdownMenuItem(value: 2, child: Text('2 – Simples Nacional (Excesso Sublimite)')),
                  DropdownMenuItem(value: 3, child: Text('3 – Regime Normal')),
                ],
                onChanged: (v) => setState(() => _crt = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _finalidade,
                dropdownColor: const Color(0xFF1E1E2E),
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Finalidade de Emissão'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 – Normal')),
                  DropdownMenuItem(value: 4, child: Text('4 – Devolução')),
                ],
                onChanged: (v) {
                  setState(() {
                    _finalidade = v!;
                    if (_finalidade == 4) {
                      _natOpCtrl.text = 'DEVOLUCAO DE MERCADORIA';
                      _csosnCtrl.text = '900'; // Geralmente usado para devoluções
                      // Mudar CFOP dos itens existentes para Devolução (Ex: 5102 -> 5202)
                      for (var item in _itens) {
                        String cfopOriginal = item['cfop'] ?? '5102';
                        if (cfopOriginal == '5102' || cfopOriginal == '5101') {
                          item['cfop'] = '5202';
                        } else if (cfopOriginal == '6102' || cfopOriginal == '6101') {
                          item['cfop'] = '6202';
                        }
                      }
                      _cfopCtrl.text = '5202'; // Padrão para novos itens
                    } else {
                      _natOpCtrl.text = 'VENDA DE MERCADORIA';
                      _csosnCtrl.text = '400';
                      for (var item in _itens) {
                        String cfopOriginal = item['cfop'] ?? '5202';
                        if (cfopOriginal == '5202' || cfopOriginal == '5201') {
                          item['cfop'] = '5102';
                        } else if (cfopOriginal == '6202' || cfopOriginal == '6201') {
                          item['cfop'] = '6102';
                        }
                      }
                      _cfopCtrl.text = '5102';
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _natOpCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('Natureza da Operação', hint: 'Ex: VENDA, DEVOLUCAO'),
              ),
            ),
          ]),
          if (_finalidade == 4) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _chaveRefCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              maxLength: 44,
              decoration: _dec('Chave de Acesso Referenciada *', hint: 'Chave de 44 dígitos da nota original'),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 10),

          // Busca rápida de cliente
          Row(
            children: [
              Expanded(
                child: Autocomplete<Cliente>(
                  displayStringForOption: (c) => '${c.nome} — ${c.cpfCnpj ?? ""}',
                  optionsBuilder: (v) {
                    if (v.text.isEmpty) return const [];
                    final q = v.text.toLowerCase();
                    return clientes.where((c) =>
                        c.nome.toLowerCase().contains(q) ||
                        (c.cpfCnpj?.contains(q) ?? false));
                  },
                  onSelected: _preencherDestinatarioPorCliente,
                  fieldViewBuilder: (ctx, ctrl, node, onSubmit) => TextField(
                    controller: ctrl,
                    focusNode: node,
                    style: const TextStyle(color: Colors.white),
                    decoration: _dec('Buscar cliente cadastrado...'),
                  ),
                  optionsViewBuilder: (ctx, onSelected, opts) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: const Color(0xFF1E1E2E),
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 500,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: opts.length,
                          itemBuilder: (ctx, i) {
                            final c = opts.elementAt(i);
                            return ListTile(
                              title: Text(c.nome, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(c.cpfCnpj ?? '', style: const TextStyle(color: Colors.grey)),
                              onTap: () => onSelected(c),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('DADOS DO DESTINATÁRIO', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: TextField(controller: _nomeDestCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Nome / Razão Social *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _docDestCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('CPF / CNPJ *'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              value: _indIE,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white),
              decoration: _dec('Indicador IE'),
              items: const [
                DropdownMenuItem(value: '1', child: Text('1 – Contribuinte ICMS')),
                DropdownMenuItem(value: '2', child: Text('2 – Contribuinte Isento')),
                DropdownMenuItem(value: '9', child: Text('9 – Não Contribuinte')),
              ],
              onChanged: (v) => setState(() => _indIE = v!),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _foneCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Telefone'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _emailDestCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('E-mail'))),
          ]),
          const SizedBox(height: 20),
          const Text('ENDEREÇO DO DESTINATÁRIO (obrigatório para NF-e mod. 55)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: _logradouroCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Logradouro *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _numEndCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Número *'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _complCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Complemento'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _bairroCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Bairro *'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: TextField(controller: _municipioCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Município *'))),
            const SizedBox(width: 12),
            SizedBox(width: 80, child: TextField(controller: _ufCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('UF *'), inputFormatters: [])),
            const SizedBox(width: 12),
            SizedBox(width: 130, child: TextField(controller: _cepCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CEP *'))),
          ]),
        ],
      ),
    );
  }

  // ─── ABA 2: ITENS ───────────────────────────────────────
  Widget _buildTabItens() {
    final produtos = widget.dataService.produtos.where((p) {
      final q = _buscaProduto.toLowerCase();
      return q.isEmpty || p.nome.toLowerCase().contains(q) || (p.codigo?.toLowerCase().contains(q) ?? false);
    }).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    return Column(
      children: [
        // Painel de adição de item
        Container(
          color: const Color(0xFF1E1E2E),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ADICIONAR ITEM', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: Autocomplete<Produto>(
                    displayStringForOption: (p) => '${p.nome} — R\$ ${p.preco.toStringAsFixed(2)}',
                    optionsBuilder: (v) {
                      if (v.text.isEmpty) return const [];
                      final q = v.text.toLowerCase();
                      return produtos.where((p) => p.nome.toLowerCase().contains(q) || (p.codigo?.toLowerCase().contains(q) ?? false));
                    },
                    onSelected: (p) {
                      setState(() {
                        _produtoTemp = p;
                        _precoCtrl.text = p.preco.toStringAsFixed(2);
                        _ncmItemCtrl.text = p.ncm ?? '00000000';
                        _descItemCtrl.text = p.nome;
                        _unidCtrl.text = p.unidade ?? 'UN';
                      });
                    },
                    fieldViewBuilder: (ctx, ctrl, node, onSubmit) => TextField(
                      controller: ctrl,
                      focusNode: node,
                      onChanged: (v) => setState(() => _buscaProduto = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _dec('Pesquisar produto...'),
                    ),
                    optionsViewBuilder: (ctx, onSelected, opts) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: const Color(0xFF1E1E2E),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 450,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: opts.length > 15 ? 15 : opts.length,
                            itemBuilder: (ctx, i) {
                              final p = opts.elementAt(i);
                              return ListTile(
                                dense: true,
                                title: Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                subtitle: Text('R\$ ${p.preco.toStringAsFixed(2)} | NCM: ${p.ncm ?? "---"}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                onTap: () => onSelected(p),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 80, child: TextField(controller: _qtdCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dec('Qtd'))),
                const SizedBox(width: 10),
                SizedBox(width: 110, child: TextField(controller: _precoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontSize: 13), decoration: _dec('Preço Unit.'))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(flex: 2, child: TextField(controller: _descItemCtrl, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _dec('Descrição do item'))),
                const SizedBox(width: 10),
                SizedBox(width: 120, child: TextField(controller: _ncmItemCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _dec('NCM *'))),
                const SizedBox(width: 10),
                SizedBox(width: 90, child: TextField(controller: _cfopCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _dec('CFOP *'))),
                const SizedBox(width: 10),
                SizedBox(width: 80, child: TextField(controller: _unidCtrl, style: const TextStyle(color: Colors.white, fontSize: 12), decoration: _dec('Unidade'))),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                  onPressed: () {
                    final qtd = double.tryParse(_qtdCtrl.text.replaceAll(',', '.')) ?? 1.0;
                    final preco = double.tryParse(_precoCtrl.text.replaceAll(',', '.')) ?? (_produtoTemp?.preco ?? 0.0);
                    final ncm = _ncmItemCtrl.text.trim().isEmpty ? '00000000' : _ncmItemCtrl.text.trim();
                    final cfop = _cfopCtrl.text.trim().isEmpty ? '5102' : _cfopCtrl.text.trim();
                    final desc = _descItemCtrl.text.trim().isNotEmpty ? _descItemCtrl.text.trim() : (_produtoTemp?.nome ?? 'Item');

                    if (_produtoTemp == null && desc.isEmpty) return;

                    final itemProd = _produtoTemp ?? Produto(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      nome: desc,
                      preco: preco,
                      unidade: _unidCtrl.text.trim().isNotEmpty ? _unidCtrl.text.trim() : 'UN',
                      grupo: 'Geral',
                      estoque: 0,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                      exibirNaLoja: false,
                      emDestaque: false,
                      fotosUrls: [],
                      codigosFornecedor: [],
                      ncm: ncm,
                    );

                    setState(() {
                      _itens.add({'produto': itemProd, 'qtd': qtd, 'preco': preco, 'ncm': ncm, 'cfop': cfop, 'unidade': _unidCtrl.text.trim().isNotEmpty ? _unidCtrl.text.trim() : 'UN', 'descricao': desc});
                      _produtoTemp = null;
                      _qtdCtrl.text = '1';
                      _precoCtrl.clear();
                      _descItemCtrl.clear();
                      _ncmItemCtrl.text = '00000000';
                      _cfopCtrl.text = '5102';
                      _unidCtrl.text = 'UN';
                      _buscaProduto = '';
                    });
                  },
                ),
              ]),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        // Lista de itens
        Expanded(
          child: _itens.isEmpty
              ? const Center(child: Text('Nenhum item adicionado.', style: TextStyle(color: Colors.white30)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _itens.length,
                  itemBuilder: (ctx, idx) {
                    final item = _itens[idx];
                    final prod = item['produto'] as Produto;
                    final qtd = item['qtd'] as double;
                    final preco = item['preco'] as double;
                    return Card(
                      color: const Color(0xFF1E1E2E),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        title: Text(item['descricao'] ?? prod.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Qtd: $qtd  |  Unit: R\$ ${preco.toStringAsFixed(2)}  |  Total: R\$ ${(qtd * preco).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Text('NCM: ${item['ncm']}  |  CFOP: ${item['cfop']}  |  UN: ${item['unidade']}',
                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Editar
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18),
                              tooltip: 'Editar item',
                              onPressed: () => _editarItem(idx),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                              tooltip: 'Remover',
                              onPressed: () => setState(() => _itens.removeAt(idx)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _editarItem(int idx) {
    final item = _itens[idx];
    final qtdCtrl = TextEditingController(text: (item['qtd'] as double).toString());
    final precoCtrl = TextEditingController(text: (item['preco'] as double).toStringAsFixed(2));
    final ncmCtrl = TextEditingController(text: item['ncm'] ?? '00000000');
    final cfopCtrl = TextEditingController(text: item['cfop'] ?? '5102');
    final unCtrl = TextEditingController(text: item['unidade'] ?? 'UN');
    final descCtrl = TextEditingController(text: item['descricao'] ?? (item['produto'] as Produto).nome);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Editar Item', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: descCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Descrição')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: qtdCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Quantidade'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: precoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Preço Unit.'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: ncmCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('NCM'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: cfopCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('CFOP'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: unCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Unidade'))),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () {
              setState(() {
                _itens[idx] = {
                  ..._itens[idx],
                  'qtd': double.tryParse(qtdCtrl.text.replaceAll(',', '.')) ?? item['qtd'],
                  'preco': double.tryParse(precoCtrl.text.replaceAll(',', '.')) ?? item['preco'],
                  'ncm': ncmCtrl.text.trim(),
                  'cfop': cfopCtrl.text.trim(),
                  'unidade': unCtrl.text.trim(),
                  'descricao': descCtrl.text.trim(),
                };
              });
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Método auxiliar para recalcular base e valores tributáveis do Simples Nacional / CSOSN 900
  void _recalcularValoresFiscais() {
    final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? _total;
    if (_icmsBaseCalculoCtrl.text.isEmpty || _icmsBaseCalculoCtrl.text == '0.00') {
      _icmsBaseCalculoCtrl.text = _total.toStringAsFixed(2);
    }
    
    // 1. Recalcular ICMS destacado
    final double aliqIcms = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (aliqIcms > 0.0) {
      final double valIcms = bc * (aliqIcms / 100.0);
      _icmsValorCtrl.text = valIcms.toStringAsFixed(2);
    } else {
      _icmsValorCtrl.text = '0.00';
    }

    // 2. Recalcular Crédito do Simples Nacional
    final double aliqCred = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
    if (aliqCred > 0.0) {
      final double valCred = bc * (aliqCred / 100.0);
      _creditoValorCtrl.text = valCred.toStringAsFixed(2);
    } else {
      _creditoValorCtrl.text = '0.00';
    }
  }

  // ─── ABA 3: IMPOSTOS ────────────────────────────────────
  Widget _buildTabImpostos() {
    // Inicializar a base de cálculo se estiver vazia
    if (_icmsBaseCalculoCtrl.text == '0.00' || _icmsBaseCalculoCtrl.text.isEmpty) {
      _icmsBaseCalculoCtrl.text = _total.toStringAsFixed(2);
    }

    return StatefulBuilder(
      builder: (context, setStateImpostos) {
        // Listeners para auto-cálculos ao digitar
        _icmsBaseCalculoCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliqIcms = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliqCred = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          
          if (aliqIcms > 0.0) {
            _icmsValorCtrl.text = (bc * (aliqIcms / 100.0)).toStringAsFixed(2);
          }
          if (aliqCred > 0.0) {
            _creditoValorCtrl.text = (bc * (aliqCred / 100.0)).toStringAsFixed(2);
          }
        });

        _icmsAliqCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliq = double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          _icmsValorCtrl.text = (bc * (aliq / 100.0)).toStringAsFixed(2);
        });

        _creditoAliqCtrl.addListener(() {
          final double bc = double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final double aliq = double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0;
          _creditoValorCtrl.text = (bc * (aliq / 100.0)).toStringAsFixed(2);
        });

        final bool isCsosn900 = _csosnCtrl.text.trim() == '900';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONFIGURAÇÃO TRIBUTÁRIA (aplicada a todos os itens)', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              const Text('Preencha conforme o regime tributário da empresa. Deixe em branco o que não se aplicar.', style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 20),

              // ICMS
              const Text('ICMS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _csosnCtrl, 
                    keyboardType: TextInputType.number, 
                    style: const TextStyle(color: Colors.white), 
                    decoration: _dec('CSOSN (Simples)', hint: 'Ex: 400'),
                    onChanged: (val) {
                      setStateImpostos(() {});
                    },
                  )
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _icmsCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST ICMS (Lucro Real)', hint: 'Ex: 00, 40'))),
              ]),
              const SizedBox(height: 20),

              // Destaque de ICMS Normal para Simples Nacional (Exigido no CSOSN 900)
              if (isCsosn900) ...[
                Row(
                  children: [
                    Checkbox(
                      value: _destacarIcmsNormalVal,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) {
                        setStateImpostos(() {
                          _destacarIcmsNormalVal = val ?? false;
                        });
                      },
                    ),
                    const Text(
                      'Destaca ICMS Normal (Exigido para CSOSN 900)',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_destacarIcmsNormalVal) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13131A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Destaque do ICMS Normal', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _icmsReducaoBcCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('% Redução BC', hint: '0.00'))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: _icmsBaseCalculoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Base de Cálculo', hint: '0.00'))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: _icmsAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota ICMS %', hint: '0.00'))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: _icmsValorCtrl, readOnly: true, style: const TextStyle(color: Colors.greenAccent), decoration: _dec('Valor do ICMS R\$', hint: '0.00'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Crédito do Simples Nacional
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Crédito Simples Nacional', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _creditoAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota Crédito %', hint: 'Ex: 1.25'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _creditoValorCtrl, readOnly: true, style: const TextStyle(color: Colors.greenAccent), decoration: _dec('Valor do Crédito R\$', hint: '0.00'))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: TextField(controller: _icmsAliqCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Alíquota ICMS %', hint: '0.00'))),
                  ],
                ),
                const SizedBox(height: 20),
              ],

          // PIS / COFINS
          const Text('PIS / COFINS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _pisCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST PIS', hint: 'Ex: 07 (isento), 01'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _cofinsCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST COFINS', hint: 'Ex: 07 (isento), 01'))),
          ]),
          const SizedBox(height: 20),

          // IPI (opcional)
          const Text('IPI (opcional)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _ipiCstCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('CST IPI', hint: 'Ex: 53'))),
            const Expanded(flex: 2, child: SizedBox()),
          ]),
          const SizedBox(height: 20),

          // Despesas Acessórias
          const Text('DESPESAS E ACRÉSCIMOS GLOBAIS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _freteValorCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Valor do Frete (R\$)', hint: '0.00'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _seguroValorCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Valor do Seguro (R\$)', hint: '0.00'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _outrasDespCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Outras Despesas (R\$)', hint: '0.00'))),
          ]),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blueAccent, size: 16), SizedBox(width: 6), Text('Referência rápida', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13))]),
                SizedBox(height: 8),
                Text('• Simples Nacional: use CSOSN (400 = tributado sem crédito, 102 = tributado sem ICMS)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('• Lucro Presumido/Real: use CST ICMS (00 = tributado, 40 = isento, 41 = não tributado)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('• PIS/COFINS isentos: CST 07 | tributados: CST 01 (cumulativo) ou 50 (não cumulativo)', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  // ─── ABA 4: TRANSPORTE ────────────────────────────────────
  Widget _buildTabTransporte() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DADOS DE TRANSPORTE E FRETE', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          const Text('Preencha as informações da transportadora e do frete se aplicável.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),

          // Modalidade de Frete
          DropdownButtonFormField<String>(
            value: _modFrete,
            dropdownColor: const Color(0xFF1E1E2E),
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Modalidade do Frete'),
            items: const [
              DropdownMenuItem(value: '0', child: Text('0 – Remetente (CIF)')),
              DropdownMenuItem(value: '1', child: Text('1 – Destinatário (FOB)')),
              DropdownMenuItem(value: '2', child: Text('2 – Terceiros')),
              DropdownMenuItem(value: '3', child: Text('3 – Próprio por conta do Remetente')),
              DropdownMenuItem(value: '4', child: Text('4 – Próprio por conta do Destinatário')),
              DropdownMenuItem(value: '9', child: Text('9 – Sem Ocorrência de Transporte')),
            ],
            onChanged: (v) => setState(() => _modFrete = v!),
          ),
          const SizedBox(height: 20),

          if (_modFrete != '9') ...[
            // Transportadora
            const Text('TRANSPORTADORA', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: _transpNomeCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Razão Social / Nome'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpCnpjCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('CNPJ / CPF'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: _transpEndCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Logradouro / Endereço'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpInscEstCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Inscrição Estadual'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _transpMunicipioCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Município'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpUfCtrl, style: const TextStyle(color: Colors.white), maxLength: 2, decoration: _dec('UF'))),
            ]),
            const SizedBox(height: 20),

            // Veículo
            const Text('VEÍCULO', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _transpPlacaCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Placa do Veículo'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpPlacaUfCtrl, style: const TextStyle(color: Colors.white), maxLength: 2, decoration: _dec('UF da Placa'))),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 20),

            // Volumes e Pesos
            const Text('VOLUMES E PESOS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _transpQtdVolCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: _dec('Quantidade de Volumes'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpEspecieVolCtrl, style: const TextStyle(color: Colors.white), decoration: _dec('Espécie (ex: Caixa, Palete)'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _transpPesoBVolCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Peso Bruto (kg)'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _transpPesoLVolCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white), decoration: _dec('Peso Líquido (kg)'))),
            ]),
          ],
        ],
      ),
    );
  }


  // ─── EMISSÃO ─────────────────────────────────────────────
  Future<void> _emitir(AuthService authService) async {
    // Validações Inteligentes Avançadas (Evita Rejeição da SEFAZ)
    if (_nomeDestCtrl.text.trim().isEmpty || _docDestCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Preencha Nome e CPF/CNPJ do destinatário.'), backgroundColor: Colors.orange));
      return;
    }
    
    // CNPJ/CPF Destinatário Limpo
    final docLimpo = _docDestCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (docLimpo.length != 11 && docLimpo.length != 14) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ CPF/CNPJ do destinatário inválido.'), backgroundColor: Colors.orange));
      return;
    }

    if (_logradouroCtrl.text.trim().isEmpty || _municipioCtrl.text.trim().isEmpty || _ufCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ O endereço do destinatário é obrigatório e deve estar completo (Rua, Cidade, UF).'), backgroundColor: Colors.orange));
      return;
    }
    if (_cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length != 8) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ CEP do destinatário deve conter 8 dígitos.'), backgroundColor: Colors.orange));
      return;
    }

    // Validação de Devolução
    if (_finalidade == 4) {
      final chaveRef = _chaveRefCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (chaveRef.isEmpty) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Nota de Devolução exige a Chave de Acesso Referenciada.'), backgroundColor: Colors.orange));
        return;
      }
      if (chaveRef.length != 44) {
        _tabController.animateTo(0);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ A Chave de Acesso Referenciada deve ter exatamente 44 dígitos (atual: ${chaveRef.length}).'), backgroundColor: Colors.orange));
        return;
      }
    }

    if (_itens.isEmpty) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Adicione pelo menos um item à nota.'), backgroundColor: Colors.orange));
      return;
    }
    final empresa = authService.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Empresa não encontrada.'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _emitindo = true);

    // Identificador do registro pendente criado ao iniciar a nota (usado no catch
    // para marcar como 'rejeitada' se a SEFAZ rejeitar)
    String? idPendente;
    NFCe? nfcePendente;
    // Indica que a SEFAZ autorizou a nota (evita marcar como rejeitada se a
    // gravação local/Supabase falhar DEPOIS da autorização)
    bool emitiuOk = false;

    try {
      final service = NFCeServiceFactory.criar();
      final dataService = widget.dataService;

      // Monta lista de produtos enriquecidos com impostos
      final List<Produto> listProd = _itens.map((i) {
        final base = i['produto'] as Produto;
        return Produto(
          id: base.id,
          nome: i['descricao'] ?? base.nome,
          preco: i['preco'] as double,
          unidade: i['unidade'] ?? base.unidade ?? 'UN',
          grupo: base.grupo,
          estoque: base.estoque,
          createdAt: base.createdAt,
          updatedAt: base.updatedAt,
          exibirNaLoja: base.exibirNaLoja,
          emDestaque: base.emDestaque,
          fotosUrls: base.fotosUrls,
          codigosFornecedor: base.codigosFornecedor,
          ncm: i['ncm'] ?? base.ncm ?? '00000000',
          cfop: i['cfop'] ?? base.cfop ?? '5102',
          csosn: _csosnCtrl.text.trim().isNotEmpty ? _csosnCtrl.text.trim() : base.csosn,
          icmsCst: _icmsCstCtrl.text.trim().isNotEmpty ? _icmsCstCtrl.text.trim() : base.icmsCst,
          pisCst: _pisCstCtrl.text.trim().isNotEmpty ? _pisCstCtrl.text.trim() : base.pisCst,
          cofinsCst: _cofinsCstCtrl.text.trim().isNotEmpty ? _cofinsCstCtrl.text.trim() : base.cofinsCst,
          icmsAliquota: double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? base.icmsAliquota,
          ipiCst: _ipiCstCtrl.text.trim().isNotEmpty ? _ipiCstCtrl.text.trim() : base.ipiCst,
        );
      }).toList();

      final Map<String, double> qtdeMap = {for (var i in _itens) (i['produto'] as Produto).id: i['qtd'] as double};
      final total = _total;
      final numForcado = int.tryParse(widget.numeroController.text);
      final serieForcada = int.tryParse(widget.serieController.text);

      // Determinar ID e Número da venda/pedido de origem
      String? vId;
      String? vNum;
      if (widget.vendaFaturar != null) {
        vId = widget.vendaFaturar!['id'];
        vNum = widget.vendaFaturar!['numero'];
      } else if (widget.pedidoFaturar != null) {
        vId = widget.pedidoFaturar!['id'];
        vNum = widget.pedidoFaturar!['numero'];
      } else if (widget.loteFaturar != null) {
        vId = widget.loteFaturar!.map((i) => i['id']).join(', ');
        vNum = widget.loteFaturar!.map((i) => i['numero']).join(', ');
      }

      // ── Salvar PENDENTE no histórico assim que a nota é iniciada (nunca se perde) ──
      final nowPend = DateTime.now();
      idPendente = 'pend-' + nowPend.millisecondsSinceEpoch.toString();
      final numeroPendente = (numForcado != null && numForcado > 0)
          ? numForcado.toString()
          : (nowPend.millisecondsSinceEpoch % 999999999).toString();
      final seriePendente = (serieForcada != null && serieForcada > 0) ? serieForcada.toString() : '1';

      nfcePendente = NFCe(
        id: idPendente!,
        numero: numeroPendente,
        serie: seriePendente,
        dataEmissao: nowPend,
        empresaId: empresa.id,
        itens: _itens.map((i) {
          final base = i['produto'] as Produto;
          return NFCeItem(
            produtoId: base.id,
            codigo: base.codigo ?? base.id,
            descricao: (i['descricao'] ?? base.nome).toString(),
            ncm: (i['ncm'] ?? base.ncm ?? '00000000').toString(),
            cfop: (i['cfop'] ?? '5102').toString(),
            unidade: (i['unidade'] ?? base.unidade ?? 'UN').toString(),
            quantidade: (i['qtd'] as double?) ?? 1.0,
            valorUnitario: (i['preco'] as double?) ?? base.preco,
            valorTotal: ((i['preco'] as double?) ?? base.preco) * ((i['qtd'] as double?) ?? 1.0),
          );
        }).toList(),
        valorTotal: total,
        cpfCnpjConsumidor: _docDestCtrl.text.trim().isEmpty ? null : _docDestCtrl.text.trim(),
        nomeConsumidor: _nomeDestCtrl.text.trim().isEmpty ? null : _nomeDestCtrl.text.trim(),
        pagamentos: [NFCePagamento(tipo: _tipoPagamento, valor: total)],
        modelo: _modelo,
        status: 'pendente',
        vendaId: vId,
        vendaNumero: vNum,
        createdAt: nowPend,
        updatedAt: nowPend,
      );
      await dataService.adicionarNFCe(nfcePendente);
      debugPrint('>>> [HISTORICO] Nota pendente gravada ao iniciar: ${nfcePendente.id}');

      final responseNfce = await service.emitir(
        empresa: empresa,
        produtos: listProd,
        quantidades: qtdeMap,
        pagamentos: [NFCePagamento(tipo: _tipoPagamento, valor: total)],
        valorTotal: total,
        cpfCnpjConsumidor: _docDestCtrl.text.trim(),
        nomeConsumidor: _nomeDestCtrl.text.trim(),
        ambienteHomologacao: widget.ambienteHomologacao,
        modelo: _modelo, // 55 = NF-e, 65 = NFC-e (selecionável)
        tpEmis: _tpEmis, // Todos os tipos de emissão (1,2,3,4,5,6,7,9)
        crt: _crt,       // Regime Tributário (1,2,3)
        serie: serieForcada,
        numero: numForcado,
        destLogradouro: _logradouroCtrl.text.trim(),
        destNumero: _numEndCtrl.text.trim().isEmpty ? 'S/N' : _numEndCtrl.text.trim(),
        destComplemento: _complCtrl.text.trim(),
        destBairro: _bairroCtrl.text.trim().isEmpty ? 'Centro' : _bairroCtrl.text.trim(),
        destMunicipio: _municipioCtrl.text.trim(),
        destUf: _ufCtrl.text.trim().toUpperCase(),
        destCep: _cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destTelefone: _foneCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
        destEmail: _emailDestCtrl.text.trim(),
        // ─── Novos campos de Devolução, Impostos e Transporte ───
        finalidade: _finalidade,
        naturezaOperacao: _natOpCtrl.text.trim(),
        chaveReferenciada: _finalidade == 4 ? _chaveRefCtrl.text.trim() : null,
        valorFrete: double.tryParse(_freteValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        valorSeguro: double.tryParse(_seguroValorCtrl.text.replaceAll(',', '.')) ?? 0.0,
        outrasDespesas: double.tryParse(_outrasDespCtrl.text.replaceAll(',', '.')) ?? 0.0,
        modFrete: int.tryParse(_modFrete) ?? 9,
        transpNome: _transpNomeCtrl.text.trim().isNotEmpty ? _transpNomeCtrl.text.trim() : null,
        transpCnpjCpf: _transpCnpjCtrl.text.trim().isNotEmpty ? _transpCnpjCtrl.text.trim() : null,
        transpInscEst: _transpInscEstCtrl.text.trim().isNotEmpty ? _transpInscEstCtrl.text.trim() : null,
        transpEndereco: _transpEndCtrl.text.trim().isNotEmpty ? _transpEndCtrl.text.trim() : null,
        transpMunicipio: _transpMunicipioCtrl.text.trim().isNotEmpty ? _transpMunicipioCtrl.text.trim() : null,
        transpUf: _transpUfCtrl.text.trim().isNotEmpty ? _transpUfCtrl.text.trim() : null,
        transpPlaca: _transpPlacaCtrl.text.trim().isNotEmpty ? _transpPlacaCtrl.text.trim() : null,
        transpPlacaUf: _transpPlacaUfCtrl.text.trim().isNotEmpty ? _transpPlacaUfCtrl.text.trim() : null,
        transpQtdVolumes: double.tryParse(_transpQtdVolCtrl.text),
        transpEspecie: _transpEspecieVolCtrl.text.trim().isNotEmpty ? _transpEspecieVolCtrl.text.trim() : null,
        transpPesoBruto: double.tryParse(_transpPesoBVolCtrl.text.replaceAll(',', '.')),
        transpPesoLiquido: double.tryParse(_transpPesoLVolCtrl.text.replaceAll(',', '.')),
        vendaId: vId,
        vendaNumero: vNum,
        
        // Parâmetros tributários de Destaque de ICMS e Crédito
        icmsReducaoBc: _destacarIcmsNormalVal ? (double.tryParse(_icmsReducaoBcCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        icmsBaseCalculo: _destacarIcmsNormalVal ? (double.tryParse(_icmsBaseCalculoCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        icmsAliquota: double.tryParse(_icmsAliqCtrl.text.replaceAll(',', '.')) ?? 0.0,
        icmsValor: _destacarIcmsNormalVal ? (double.tryParse(_icmsValorCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        creditoAliquota: _csosnCtrl.text.trim() == '900' ? (double.tryParse(_creditoAliqCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        creditoValor: _csosnCtrl.text.trim() == '900' ? (double.tryParse(_creditoValorCtrl.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
      );

      // SEFAZ autorizou: não marcar como rejeitada em caso de falha na gravação local
      emitiuOk = true;

      // Nota autorizada: grava automaticamente no histórico (id do bridge = 1 registro)
      final nfceFinal = responseNfce.copyWith(
        nomeConsumidor: _nomeDestCtrl.text.trim(),
      );
      await dataService.adicionarNFCe(nfceFinal);
      // Remove o registro pendente criado ao iniciar (era o mesmo rascunho; evita duplicidade)
      if (idPendente != null && idPendente != nfceFinal.id) {
        await dataService.removerNFCe(idPendente!);
      }
      debugPrint('>>> [HISTORICO] Nota autorizada gravada no histórico: ${nfceFinal.numero}');

      // Gerar a Conta a Receber correspondente no Financeiro se estiver ativado
      try {
        final prefs = await SharedPreferences.getInstance();
        final gerarRecebivel = prefs.getBool('gerar_recebivel_nfe') ?? true;
        if (gerarRecebivel) {
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
        } else {
          debugPrint('>>> [FINANCEIRO] Geração de Conta a Receber automática desativada nas configurações.');
        }
      } catch (eFin) {
        debugPrint('>>> [FINANCEIRO] ⚠️ Falha ao registrar Conta a Receber: $eFin');
      }

      if (numForcado != null) {
        widget.numeroController.text = (numForcado + 1).toString();
      }

      widget.onEmitida();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('✓ NF-e Nº ${responseNfce.numero} emitida e autorizada com sucesso! Protocolo: ${responseNfce.protocolo ?? "---"}')),
            ]),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      // A nota já iniciada fica registrada no histórico: marca como REJEITADA
      // (o registro pendente criado ao iniciar nunca se perde)
      // Só marca como 'rejeitada' se a SEFAZ de fato NÃO autorizou
      if (!emitiuOk) {
        try {
          if (nfcePendente != null) {
            await widget.dataService.atualizarNFCe(
              nfcePendente!.copyWith(
                status: 'rejeitada',
                updatedAt: DateTime.now(),
              ),
            );
            debugPrint('>>> [HISTORICO] Nota pendente marcada como rejeitada: ${nfcePendente!.id}');
          }
        } catch (e2) {
          debugPrint('>>> [HISTORICO] ⚠️ Não foi possível marcar a nota como rejeitada: $e2');
        }
      } else {
        debugPrint('>>> [HISTORICO] ⚠️ Nota autorizada, mas houve falha ao gravar localmente (será sincronizada depois).');
      }
      if (mounted) {
        setState(() => _emitindo = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Row(children: [Icon(Icons.error_outline, color: Colors.redAccent), SizedBox(width: 8), Text('Falha na Emissão', style: TextStyle(color: Colors.white))]),
            content: SelectableText(e.toString().replaceAll('Exception:', '').trim(), style: const TextStyle(color: Colors.white70, height: 1.5)),
            actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
      }
    }
  }

  /// Grava a nota localmente como PENDENTE (rascunho), sem transmitir para a SEFAZ.
  Future<void> _gravarNotaSemTransmitir(AuthService authService) async {
    if (_itens.isEmpty) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Adicione pelo menos um item à nota.'), backgroundColor: Colors.orange));
      return;
    }
    final empresa = authService.empresaAtual;
    if (empresa == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Empresa não encontrada.'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _emitindo = true);
    try {
      final now = DateTime.now();
      final numForcado = int.tryParse(widget.numeroController.text) ?? 0;
      final serieForcada = int.tryParse(widget.serieController.text) ?? 1;

      final nfceRascunho = NFCe(
        id: now.millisecondsSinceEpoch.toString(),
        numero: (numForcado > 0 ? numForcado : now.millisecondsSinceEpoch % 999999999).toString(),
        serie: serieForcada.toString(),
        dataEmissao: now,
        empresaId: empresa.id,
        itens: _itens.map((i) {
          final base = i['produto'] as Produto;
          return NFCeItem(
            produtoId: base.id,
            codigo: base.codigo ?? base.id,
            descricao: (i['descricao'] ?? base.nome).toString(),
            ncm: (i['ncm'] ?? base.ncm ?? '00000000').toString(),
            cfop: (i['cfop'] ?? '5102').toString(),
            unidade: (i['unidade'] ?? base.unidade ?? 'UN').toString(),
            quantidade: (i['qtd'] as double?) ?? 1.0,
            valorUnitario: (i['preco'] as double?) ?? base.preco,
            valorTotal: ((i['preco'] as double?) ?? base.preco) * ((i['qtd'] as double?) ?? 1.0),
          );
        }).toList(),
        valorTotal: _total,
        cpfCnpjConsumidor: _docDestCtrl.text.trim().isEmpty ? null : _docDestCtrl.text.trim(),
        nomeConsumidor: _nomeDestCtrl.text.trim().isEmpty ? null : _nomeDestCtrl.text.trim(),
        pagamentos: [NFCePagamento(tipo: _tipoPagamento, valor: _total)],
        modelo: _modelo,
        status: 'pendente',
        vendaId: widget.vendaFaturar?['id'] ?? widget.pedidoFaturar?['id'],
        vendaNumero: widget.vendaFaturar?['numero'] ?? widget.pedidoFaturar?['numero'],
        createdAt: now,
        updatedAt: now,
      );

      await widget.dataService.adicionarNFCe(nfceRascunho);
      setState(() => _emitindo = false);
      widget.onEmitida();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💾 Nota gravada como PENDENTE (não foi enviada à SEFAZ). Você pode reemitir depois.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _emitindo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Erro ao gravar nota: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
