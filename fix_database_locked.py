#!/usr/bin/env python3
"""
Correção para problema de database locked no RealtimeSync
"""

with open('lib/services/realtime_sync_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 60)
print("Corrigindo RealtimeSync - Database Locked")
print("=" * 60)

# O problema é que _atualizarSQLiteLocal chama salvarLista que usa _synchronized
# mas não espera a conclusão antes de processar o próximo evento

old_atualizar = """/// Atualiza o cache SQLite local com o dado recebido em tempo real
  Future<void> _atualizarSQLiteLocal(String tabela, String evento, Map<String, dynamic> dados) async {
    try {
      // Mapear tabela Supabase → chave DatabaseService
      final chave = _mapearTabelaParaChave(tabela);
      if (chave == null) return;

      if (evento == 'DELETE') {
        // Remover do SQLite - o DatabaseService não tem delete individual ainda
        // Mas a próxima sincronização completa vai resolver
        debugPrint('>>> [Realtime] 🗑️ DELETE em $tabela (SQLite será limpo na próxima sync)');
        return;
      }

      // INSERT ou UPDATE: salvar/atualizar no SQLite
      await _dbService.salvarLista(chave, [dados]);
      debugPrint('>>> [Realtime] 💾 SQLite atualizado: $tabela');
    } catch (e) {
      debugPrint('>>> [Realtime] ⚠️ Erro ao atualizar SQLite para $tabela: $e');
    }
  }"""

new_atualizar = """/// Atualiza o cache SQLite local com o dado recebido em tempo real
  Future<void> _atualizarSQLiteLocal(String tabela, String evento, Map<String, dynamic> dados) async {
    try {
      // Mapear tabela Supabase → chave DatabaseService
      final chave = _mapearTabelaParaChave(tabela);
      if (chave == null) return;

      if (evento == 'DELETE') {
        // Remover do SQLite - o DatabaseService não tem delete individual ainda
        // Mas a próxima sincronização completa vai resolver
        debugPrint('>>> [Realtime] 🗑️ DELETE em $tabela (SQLite será limpo na próxima sync)');
        return;
      }

      // INSERT ou UPDATE: salvar/atualizar no SQLite
      // Adicionar delay para evitar concorrência com operações do app
      await Future.delayed(const Duration(milliseconds: 50));
      await _dbService.salvarLista(chave, [dados]);
      debugPrint('>>> [Realtime] 💾 SQLite atualizado: $tabela');
    } on DatabaseException catch (e) {
      // Ignorar erros de database locked - dados serão sincronizados na próxima sync completa
      if (e.toString().contains('locked')) {
        debugPrint('>>> [Realtime] ⏭️ SQLite ocupado, ignorando update de $tabela (sync completa resolverá)');
      } else {
        debugPrint('>>> [Realtime] ⚠️ Erro de banco ao atualizar $tabela: $e');
      }
    } catch (e) {
      debugPrint('>>> [Realtime] ⚠️ Erro ao atualizar SQLite para $tabela: $e');
    }
  }"""

if old_atualizar in content:
    content = content.replace(old_atualizar, new_atualizar)
    print("✅ Método _atualizarSQLiteLocal atualizado")
else:
    print("⚠️ Padrão não encontrado")

# Adicionar import para DatabaseException se não existir
if "import 'package:sqflite_common_ffi/sqflite_ffi.dart'" not in content:
    if "import 'dart:async';" in content:
        content = content.replace(
            "import 'dart:async';",
            "import 'dart:async';\nimport 'package:sqflite_common_ffi/sqflite_ffi.dart';"
        )
        print("✅ Import adicionado")

with open('lib/services/realtime_sync_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Arquivo salvo!")
print("=" * 60)
