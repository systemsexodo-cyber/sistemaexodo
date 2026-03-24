import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import '../services/data_service.dart';
import '../services/nfce_service_factory.dart';
import '../services/nfce_backend_service.dart';
import '../services/danfe_service.dart';
import 'package:intl/intl.dart';
import '../models/produto.dart';
import 'exodo_cancel_success_dialog.dart';

class HistoricoNFCePDVDialog extends StatefulWidget {
  final Empresa empresa;

  const HistoricoNFCePDVDialog({Key? key, required this.empresa}) : super(key: key);

  @override
  _HistoricoNFCePDVDialogState createState() => _HistoricoNFCePDVDialogState();
}

class _HistoricoNFCePDVDialogState extends State<HistoricoNFCePDVDialog> {
  bool _isLoading = true;
  List<NFCe> _todasNfces = [];
  List<NFCe> _nfcesFiltradas = [];

  final TextEditingController _buscaController = TextEditingController();
  DateTime? _dataFiltro;

  @override
  void initState() {
    super.initState();
    _loadData();
    _buscaController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await FirebaseFirestore.instance
          .collection('empresas')
          .doc(widget.empresa.id)
          .collection('nfces')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();
          
      setState(() {
         _todasNfces = results.docs.map((d) => (() {
            var map = d.data();
            map['id'] = d.id;
            return NFCe.fromMap(map);
         })()).toList();
         _isLoading = false;
         _filtrar();
      });
    } catch (e) {
      debugPrint('Erro ao carregar NFCes: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filtrar() {
    final termo = _buscaController.text.toLowerCase().trim();
    setState(() {
      _nfcesFiltradas = _todasNfces.where((nfce) {
        bool matchTermo = true;
        if (termo.isNotEmpty) {
          final n = nfce.numero?.toLowerCase() ?? '';
          final idVenda = nfce.vendaId?.toLowerCase() ?? nfce.id.toLowerCase();
          final numVenda = nfce.vendaNumero?.toLowerCase() ?? '';
          matchTermo = n.contains(termo) || idVenda.contains(termo) || numVenda.contains(termo);
        }

        bool matchData = true;
        if (_dataFiltro != null && nfce.createdAt != null) {
          matchData = nfce.createdAt!.year == _dataFiltro!.year && 
                      nfce.createdAt!.month == _dataFiltro!.month && 
                      nfce.createdAt!.day == _dataFiltro!.day;
        }

        return matchTermo && matchData;
      }).toList();
    });
  }

  Future<void> _selecionarData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataFiltro ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orange,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E2E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dataFiltro = picked;
        _filtrar();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 800,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Histórico de NFC-e', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            
            // Área de Filtros
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _buscaController,
                      decoration: InputDecoration(
                        hintText: 'Buscar por Nº da NFC-e ou ID da Venda...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _selecionarData,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _dataFiltro != null 
                        ? DateFormat('dd/MM/yyyy').format(_dataFiltro!) 
                        : 'Filtrar Data',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dataFiltro != null ? Colors.orange : Colors.white10,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_dataFiltro != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.redAccent),
                      tooltip: 'Limpar Data',
                      onPressed: () {
                        setState(() {
                          _dataFiltro = null;
                          _filtrar();
                        });
                      },
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _nfcesFiltradas.isEmpty 
                  ? const Center(child: Text('Nenhuma NFC-e encontrada com os filtros atuais.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _nfcesFiltradas.length,
                      itemBuilder: (context, index) {
                        final nfce = _nfcesFiltradas[index];
                        final isAutorizada = nfce.status == 'autorizada' || nfce.status == 'sucesso';
                        final isErro = nfce.status == 'erro' || nfce.status == 'rejeitada';
                        final dt = nfce.createdAt != null ? DateFormat('dd/MM HH:mm').format(nfce.createdAt!) : '-';
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isAutorizada ? Icons.check_circle : (isErro ? Icons.error : Icons.hourglass_empty),
                                color: isAutorizada ? Colors.green : (isErro ? Colors.redAccent : Colors.orange),
                                size: 36,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Data: $dt  |  Série ${nfce.serie ?? "-"} / Nº ${nfce.numero ?? "-"}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('Venda: ${nfce.vendaNumero ?? nfce.vendaId ?? nfce.id}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    if (nfce.chaveAcesso != null && nfce.chaveAcesso!.isNotEmpty)
                                      SelectableText('Chave: ${nfce.chaveAcesso}', style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic)),
                                    if (nfce.nomeConsumidor != null && nfce.nomeConsumidor!.isNotEmpty)
                                      Text('Cliente: ${nfce.nomeConsumidor}', style: const TextStyle(color: Colors.white70)),
                                    if (nfce.pagamentos.isNotEmpty)
                                      Text('Pagamento: ${nfce.pagamentos.map((p) => p.tipoDescricao).join(", ")}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text('Status: ${nfce.status?.toUpperCase()}', style: TextStyle(color: isAutorizada ? Colors.green : (isErro ? Colors.redAccent : Colors.orange), fontWeight: FontWeight.bold)),
                                    if (nfce.status?.toUpperCase() == 'ERRO' && nfce.xmlRetorno != null)
                                      Text('${nfce.xmlRetorno}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                    
                                    if (isAutorizada || nfce.status == 'cancelada' || nfce.status == 'sucesso' || isErro)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Row(
                                          children: [
                                            if (isAutorizada)
                                              TextButton.icon(
                                                onPressed: () => _confirmarCancelamento(context, nfce),
                                                icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                                                label: const Text('CANCELAR', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                              ),
                                            const SizedBox(width: 8),
                                            if (isAutorizada || nfce.status == 'sucesso')
                                              TextButton.icon(
                                                onPressed: () => _reimprimir(context, nfce),
                                                icon: const Icon(Icons.print, color: Colors.blueAccent, size: 18),
                                                label: const Text('REIMPRIMIR', style: TextStyle(color: Colors.blueAccent, fontSize: 11)),
                                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                              ),
                                            if (isErro)
                                              TextButton.icon(
                                                onPressed: () => _reemitirNFCe(context, nfce),
                                                icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                                                label: const Text('REEMITIR AGORA', style: TextStyle(color: Colors.orange, fontSize: 11)),
                                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(nfce.valorTotal),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmarCancelamento(BuildContext context, NFCe nfce) async {
    final justificativaController = TextEditingController(text: 'Cancelamento por erro de emissao ou devolucao de mercadoria');
    
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirmar Cancelamento', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja realmente cancelar esta NFC-e na SEFAZ?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextField(
              controller: justificativaController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Justificativa (mín. 15 caracteres)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('VOLTAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (justificativaController.text.length < 15) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A justificativa deve ter pelo menos 15 caracteres.')));
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('CONFIRMAR CANCELAMENTO'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      _cancelarNFCe(nfce, justificativaController.text);
    }
  }

  void _cancelarNFCe(NFCe nfce, String justificativa) async {
    setState(() => _isLoading = true);
    try {
      final nfceService = NFCeServiceFactory.criar();
      
      if (nfceService is! NFCeBackendService) {
         throw Exception('O cancelamento só está disponível no modo Bridge (Python).');
      }

      final resultado = await nfceService.cancelarNFCe(
        nfce: nfce,
        empresa: widget.empresa,
        justificativa: justificativa,
      );

      if (resultado['success'] == true) {
        if (!mounted) return;
        // Atualizar localmente via DataService para garantir atualização do contador de números
        final dataService = Provider.of<DataService>(context, listen: false);
        final nfceCancelada = nfce.copyWith(
          status: 'cancelada',
          updatedAt: DateTime.now(),
        );
        await dataService.atualizarNFCe(nfceCancelada);
        
        if (!mounted) return;
        ExodoCancelSuccessDialog.mostrar(context, nfceCancelada);
        _loadData(); // Recarregar lista
      } else {
        if (!mounted) return;
        _mostrarErro('Erro ao cancelar: ${resultado['message']}');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Falha técnica: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _consultarNFCe(NFCe nfce) async {
    setState(() => _isLoading = true);
    try {
      final nfceService = NFCeServiceFactory.criar();
      
      if (nfceService is! NFCeBackendService) {
         throw Exception('A consulta só está disponível no modo Bridge (Python).');
      }

      final resultado = await nfceService.consultar(
        chaveAcesso: nfce.chaveAcesso!,
        empresa: widget.empresa,
      );

      if (resultado['success'] == true) {
        final cStat = resultado['cStat'];
        final xMotivo = resultado['xMotivo'];
        final novoStatus = resultado['status']; // 'cancelada' ou 'autorizada'

        if (!mounted) return;

        // Se o status na SEFAZ for diferente do local, perguntar se quer atualizar
        if (novoStatus != nfce.status && (novoStatus == 'cancelada' || novoStatus == 'autorizada')) {
           final bool? atualizar = await showDialog<bool>(
             context: context,
             builder: (context) => AlertDialog(
               backgroundColor: const Color(0xFF1E1E1E),
               title: const Text('Divergência de Status', style: TextStyle(color: Colors.white)),
               content: Text('Na SEFAZ esta nota consta como: $novoStatus.\nNo sistema local ela está como: ${nfce.status}.\n\nDeseja atualizar o sistema local?', style: const TextStyle(color: Colors.white70)),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NÃO')),
                 ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('SIM, ATUALIZAR')),
               ],
             ),
           );

           if (atualizar == true) {
              final dataService = Provider.of<DataService>(context, listen: false);
              final nfceAtualizada = nfce.copyWith(
                status: novoStatus,
                updatedAt: DateTime.now(),
              );
              await dataService.atualizarNFCe(nfceAtualizada);
              _loadData();
           }
        }

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Consulta SEFAZ: [$cStat] $xMotivo'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.teal,
        ));
      } else {
        if (!mounted) return;
        _mostrarErro('Erro ao consultar: ${resultado['error']}');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Falha técnica: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reimprimir(BuildContext context, NFCe nfce) async {
    try {
      await DANFEService.imprimir(
        nfce: nfce,
        empresa: widget.empresa,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao imprimir: $e')));
    }
  }

  void _reemitirNFCe(BuildContext context, NFCe nfce) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final proximoNum = dataService.getProximoNumeroNfce().toString();
    final controller = TextEditingController(text: proximoNum);

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Reemitir NFC-e', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deseja realmente retransmitir esta NFC-e agora?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text('O sistema sugere o próximo número oficial disponível (notas com erro NÃO seguram número):', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Número da Nota',
                labelStyle: TextStyle(color: Colors.orange),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('VOLTAR', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('REEMITIR AGORA'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _isLoading = true);
      try {
        final nfceService = NFCeServiceFactory.criar();
        
        // Reconstruir produtos a partir dos itens da NFC-e falha
        final List<Produto> produtos = nfce.itens.map((item) => Produto(
          id: item.produtoId,
          codigo: item.codigo,
          nome: item.descricao,
          preco: item.valorUnitario,
          unidade: item.unidade,
          ncm: item.ncm,
          cfop: item.cfop,
          estoque: 0,
          grupo: 'Geral', // Campo obrigatório
          createdAt: DateTime.now(), // Campo obrigatório
          updatedAt: DateTime.now(), // Campo obrigatório
        )).toList();

        final Map<String, double> quantidades = {};
        for (final item in nfce.itens) {
          quantidades[item.produtoId] = item.quantidade;
        }

        final novaNfce = await nfceService.emitir(
          empresa: widget.empresa,
          produtos: produtos,
          quantidades: quantidades,
          pagamentos: nfce.pagamentos,
          valorTotal: nfce.valorTotal,
          cpfCnpjConsumidor: nfce.cpfCnpjConsumidor,
          nomeConsumidor: nfce.nomeConsumidor,
          vendaId: nfce.vendaId,
          vendaNumero: controller.text, // NOVO NÚMERO
          ambienteHomologacao: widget.empresa.configuracoes?['ambiente_nfe'] == 'Produção' ? false : true,
        );

        await dataService.adicionarNFCe(novaNfce);
        
        if (novaNfce.status == 'autorizada') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC-e reemitida com sucesso!')));
          _loadData();
        } else {
           _mostrarErro('Status da emissão: ${novaNfce.status?.toUpperCase()}\n\nRetorno: ${novaNfce.xmlRetorno ?? "Falha na reemissão"}');
        }
      } catch (e) {
        _mostrarErro('Erro ao reemitir: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _mostrarErro(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Atenção', style: TextStyle(color: Colors.white)),
        content: Text(msg, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
