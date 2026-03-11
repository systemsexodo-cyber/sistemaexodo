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
  List<NFCe> _nfces = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await FirebaseFirestore.instance.collection('empresas').doc(widget.empresa.id).collection('nfce').orderBy('createdAt', descending: true).limit(50).get();
      setState(() {
         _nfces = results.docs.map((d) => (() {
            var map = d.data();
            map['id'] = d.id;
            return NFCe.fromMap(map);
         })()).toList();
         _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar NFCes: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('NFC-e Emitidas / Rejeitadas', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _nfces.isEmpty 
                  ? const Center(child: Text('Nenhuma NFC-e encontrada.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _nfces.length,
                      itemBuilder: (context, index) {
                        final nfce = _nfces[index];
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
                                color: isAutorizada ? Colors.green : (isErro ? Colors.red : Colors.orange),
                                size: 36,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Data: $dt  |  Série ${nfce.serie ?? "-"} / Nº ${nfce.numero ?? "-"}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('Venda ID: ${nfce.id ?? "Avulsa"}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    if (nfce.nomeConsumidor != null && nfce.nomeConsumidor!.isNotEmpty)
                                      Text('Cliente: ${nfce.nomeConsumidor}', style: const TextStyle(color: Colors.white70)),
                                    if (nfce.pagamentos.isNotEmpty)
                                      Text('Pagamento: ${nfce.pagamentos.map((p) => p.tipoDescricao).join(", ")}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text('Status: ${nfce.status?.toUpperCase()}', style: TextStyle(color: isAutorizada ? Colors.green : (isErro ? Colors.red : Colors.orange))),
                                    if (isErro && nfce.xmlRetorno != null)
                                      Text('${nfce.xmlRetorno}', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Text(
                                NumberFormat.currency(locale: "pt_BR", symbol: "R\$").format(nfce.valorTotal),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18),
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
