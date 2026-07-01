import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import '../services/data_service.dart';
import '../services/supabase_service.dart';
import 'package:flutter/material.dart';
import '../widgets/historico_nfce_pdv_dialog.dart';

class FiscalAutomationService {
  static bool _jaVerificouEsteMes = false;

  static void verificarEEnviar(BuildContext context) async {
    if (!kIsWeb) return; // Desativado no Windows por enquanto para evitar crashes
    if (_jaVerificouEsteMes) return;
    
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return;

    if (!empresa.envioFiscalAutomatico || empresa.emailContabilidade == null || empresa.emailContabilidade!.isEmpty) {
      return;
    }

    final agora = DateTime.now();
    
    // Se não for dia 1, não faz nada (mas podemos permitir dia 2 ou 3 se não enviou ainda)
    if (agora.day > 5) { // Limite de segurança para não tentar enviar no meio do mês sem querer
       return;
    }

    final mesAnterior = DateTime(agora.year, agora.month - 1);
    final mesTag = DateFormat('yyyy-MM').format(mesAnterior);
    
    // Verificar se já enviou este mês nas configurações da empresa
    final ultimoEnvio = empresa.configuracoes?['ultimo_envio_fiscal_auto'];
    if (ultimoEnvio == mesTag) {
      _jaVerificouEsteMes = true;
      debugPrint('>>> [FiscalAuto] ✅ Arquivos de $mesTag já foram enviados anteriormente.');
      return;
    }

    debugPrint('>>> [FiscalAuto] 🚀 Iniciando envio automático de arquivos fiscais para $mesTag');
    
    try {
      // Buscar todas as NFC-es do mês anterior via Supabase
      final results = await SupabaseService.instance.select(
        SupabaseService.tableNFCes,
        filters: {
          'empresaId': empresa.id,
        },
      );

      final nfces = results
          .map((map) => NFCe.fromMap(map))
          .where((n) {
            final dateStr = n.dataEmissao.toIso8601String();
            return dateStr.compareTo(mesAnterior.toIso8601String()) >= 0 &&
                   dateStr.compareTo(DateTime(agora.year, agora.month).toIso8601String()) < 0;
          })
          .toList();

      if (nfces.isEmpty) {
        debugPrint('>>> [FiscalAuto] ℹ️ Nenhuma nota encontrada para $mesTag. Pulando.');
        _marcarMesComoEnviado(dataService, empresa, mesTag);
        return;
      }

      // No Flutter Web, sem backend real para enviar e-mail em background,
      // vamos avisar o usuário para ele autorizar o envio ou abrir o diálogo.
      // Em uma aplicação real com backend, aqui chamaríamos a API de e-mail.
      
      _notificarUsuario(context, empresa, mesTag, nfces);
      _jaVerificouEsteMes = true;
      
    } catch (e) {
      debugPrint('>>> [FiscalAuto] ❌ Erro na automação fiscal: $e');
    }
  }

  static void _notificarUsuario(BuildContext context, Empresa empresa, String mesTag, List<NFCe> nfces) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.orange),
              const SizedBox(width: 10),
              const Text('Automação Fiscal', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Identificamos que hoje é dia ${DateTime.now().day} de ${DateFormat('MMMM', 'pt_BR').format(DateTime.now())}.', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              Text('Deseja gerar e enviar agora os arquivos fiscais de $mesTag para a contabilidade (${empresa.emailContabilidade})?', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 10),
              Text('${nfces.length} notas processadas.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Marcar como se tivesse ignorado ou enviado para não incomodar mais
                final dataService = Provider.of<DataService>(context, listen: false);
                _marcarMesComoEnviado(dataService, empresa, mesTag);
              },
              child: const Text('IGNORAR ESTE MÊS', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => HistoricoNFCePDVDialog(empresa: empresa),
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('ABRIR HISTÓRICO E EXPORTAR'),
            ),
          ],
        ),
      );
    });
  }

  static void _marcarMesComoEnviado(DataService dataService, Empresa empresa, String mesTag) async {
    final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
    novasConfigs['ultimo_envio_fiscal_auto'] = mesTag;
    
    await dataService.atualizarDadosEmpresa(empresa.copyWith(configuracoes: novasConfigs));
    _jaVerificouEsteMes = true;
  }
}
