import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import '../services/data_service.dart';
import 'package:intl/intl.dart';

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
                        final isAutorizada = nfce.status == 'autorizada';
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
                                    if (isErro && nfce.xmlRetorno != null)
                                      Text('${nfce.xmlRetorno}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
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
}
