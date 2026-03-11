import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';

class SyncStatusWidget extends StatelessWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, service, _) {
        final isOffline = service.isOffline;
        final temErro = service.ultimoErroSync != null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de Sincronização
            Tooltip(
              message: isOffline ? 'Internet desconectada. Modo Offline.' : (temErro ? 'Erro: ${service.ultimoErroSync}' : service.getSyncStatusText),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isOffline ? Colors.orange.withOpacity(0.1) : (temErro ? Colors.red.withOpacity(0.1) : Colors.white.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(20),
                  border: isOffline ? Border.all(color: Colors.orange.withOpacity(0.3)) : (temErro ? Border.all(color: Colors.red.withOpacity(0.3)) : null),
                ),
                child: Row(
                  children: [
                    if (!isOffline && service.syncEmAndamento)
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
                        isOffline ? Icons.wifi_off : (temErro ? Icons.cloud_off : Icons.cloud_done),
                        color: isOffline 
                            ? Colors.orange
                            : (temErro 
                                ? Colors.red 
                                : (service.ultimaSincronizacaoSucesso != null ? Colors.green : Colors.grey)),
                        size: 16,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      isOffline ? 'MODO OFFLINE' : (temErro ? 'Erro na sincronização' : service.getSyncStatusText),
                      style: TextStyle(
                        color: isOffline ? Colors.orangeAccent : (temErro ? Colors.redAccent : Colors.white.withOpacity(0.6)),
                        fontSize: 10,
                        fontWeight: isOffline ? FontWeight.w900 : (temErro ? FontWeight.bold : FontWeight.normal),
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
