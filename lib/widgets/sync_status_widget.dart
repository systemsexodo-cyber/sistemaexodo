import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, service, _) {
        final temErro = service.ultimoErroSync != null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de Sincronização
            Tooltip(
              message: temErro ? 'Erro: ${service.ultimoErroSync}' : service.getSyncStatusText,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: temErro ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: temErro ? Border.all(color: Colors.red.withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    if (service.syncEmAndamento)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      )
                    else
                      Icon(
                        temErro ? Icons.cloud_off : Icons.cloud_done,
                        color: temErro 
                            ? Colors.red 
                            : (service.ultimaSincronizacaoSucesso != null ? Colors.green : Colors.grey),
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      temErro ? 'V2 - Erro na sincronização' : 'V2 - ${service.getSyncStatusText}',
                      style: TextStyle(
                        color: temErro ? Colors.redAccent : Colors.white.withOpacity(0.6),
                        fontSize: 10,
                        fontWeight: temErro ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh, 
                size: 20,
                color: temErro ? Colors.redAccent : Colors.white70,
              ),
              tooltip: 'Tentar sincronizar novamente',
              onPressed: () => service.forceSync(),
            ),
          ],
        );
      },
    );
  }
}
