#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script final para adicionar as 3 tabelas novas
"""

with open('lib/services/database_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

print("=" * 70)
print("ATUALIZANDO DATABASE_SERVICE.DART")
print("=" * 70)

# ============================================
# 1. ATUALIZAR CARREGARLISTA - Adicionar mapeamento de tabelas
# ============================================
print("\n[1] Atualizando carregarLista...")

old_carregar_servicos = """else if (chave.contains('servicos')) tabela = 'servicos_local';
      if (tabela != null) {"""

new_carregar_servicos = """else if (chave.contains('servicos')) tabela = 'servicos_local';
      // NOVAS TABELAS - MAPEAMENTO
      else if (chave.contains('notas_entrada')) tabela = 'notas_entrada_local';
      else if (chave.contains('ordens_servico')) tabela = 'ordens_servico_local';
      else if (chave.contains('trocas_devolucoes')) tabela = 'trocas_devolucoes_local';
      if (tabela != null) {"""

if old_carregar_servicos in content:
    content = content.replace(old_carregar_servicos, new_carregar_servicos)
    print("   ✅ Mapeamento de tabelas adicionado ao carregarLista")
else:
    print("   ⚠️ Padrão não encontrado, verificando se já existe...")
    if "notas_entrada_local'" in content and "carregarLista" in content:
        print("   ℹ️ Já parece estar atualizado")

# ============================================
# 2. ATUALIZAR SALVARLISTA - Adicionar blocos de salvamento
# ============================================
print("\n[2] Atualizando salvarLista...")

# Procurar pelo último else if (pedidos) e adicionar depois
old_salvar_pedidos = """else if (chave.contains('pedidos')) {
          await db.transaction((txn) async {
            await txn.execute('DELETE FROM pedidos_local WHERE empresa_id = ?', [empresaId]);
            for (final item in dados) {
              await txn.execute('''
        INSERT INTO pedidos_local (id, empresa_id, cliente_id, total, status, data, data_json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
                item['id'] ?? _gerarId(),
                empresaId,
                item['cliente_id'] ?? '',
                item['total'] ?? 0.0,
                item['status'] ?? 'Pendente',
                item['data'] ?? DateTime.now().toIso8601String(),
                jsonEncode(item),
              ]);
            }
          });
        }
        return;"""

new_salvar_pedidos = """else if (chave.contains('pedidos')) {
          await db.transaction((txn) async {
            await txn.execute('DELETE FROM pedidos_local WHERE empresa_id = ?', [empresaId]);
            for (final item in dados) {
              await txn.execute('''
        INSERT INTO pedidos_local (id, empresa_id, cliente_id, total, status, data, data_json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
                item['id'] ?? _gerarId(),
                empresaId,
                item['cliente_id'] ?? '',
                item['total'] ?? 0.0,
                item['status'] ?? 'Pendente',
                item['data'] ?? DateTime.now().toIso8601String(),
                jsonEncode(item),
              ]);
            }
          });
        }
        // NOVAS TABELAS - SALVAR
        else if (chave.contains('notas_entrada')) {
          await db.transaction((txn) async {
            await txn.execute('DELETE FROM notas_entrada_local WHERE empresa_id = ?', [empresaId]);
            for (final item in dados) {
              await txn.execute('''
        INSERT INTO notas_entrada_local (id, empresa_id, numero, fornecedor, valor_total, data_emissao, data_json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
                item['id'] ?? _gerarId(),
                empresaId,
                item['numero'] ?? '',
                item['fornecedor'] ?? '',
                item['valor_total'] ?? 0.0,
                item['data_emissao'] ?? DateTime.now().toIso8601String(),
                jsonEncode(item),
              ]);
            }
          });
        }
        else if (chave.contains('ordens_servico')) {
          await db.transaction((txn) async {
            await txn.execute('DELETE FROM ordens_servico_local WHERE empresa_id = ?', [empresaId]);
            for (final item in dados) {
              await txn.execute('''
        INSERT INTO ordens_servico_local (id, empresa_id, numero, cliente_nome, status, valor_total, data_abertura, data_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
                item['id'] ?? _gerarId(),
                empresaId,
                item['numero'] ?? '',
                item['cliente_nome'] ?? '',
                item['status'] ?? 'Aberta',
                item['valor_total'] ?? 0.0,
                item['data_abertura'] ?? DateTime.now().toIso8601String(),
                jsonEncode(item),
              ]);
            }
          });
        }
        else if (chave.contains('trocas_devolucoes')) {
          await db.transaction((txn) async {
            await txn.execute('DELETE FROM trocas_devolucoes_local WHERE empresa_id = ?', [empresaId]);
            for (final item in dados) {
              await txn.execute('''
        INSERT INTO trocas_devolucoes_local (id, empresa_id, numero, tipo, cliente_nome, valor, status, data, data_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
                item['id'] ?? _gerarId(),
                empresaId,
                item['numero'] ?? '',
                item['tipo'] ?? '',
                item['cliente_nome'] ?? '',
                item['valor'] ?? 0.0,
                item['status'] ?? 'Pendente',
                item['data'] ?? DateTime.now().toIso8601String(),
                jsonEncode(item),
              ]);
            }
          });
        }
        return;"""

if old_salvar_pedidos in content:
    content = content.replace(old_salvar_pedidos, new_salvar_pedidos)
    print("   ✅ Blocos de salvamento adicionados ao salvarLista")
else:
    print("   ⚠️ Padrão de pedidos não encontrado, verificando se já existe...")
    if "DELETE FROM notas_entrada_local" in content:
        print("   ℹ️ Já parece estar atualizado")

# ============================================
# SALVAR ARQUIVO
# ============================================
print("\n[3] Salvando arquivo...")
with open('lib/services/database_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("✅ Arquivo salvo!")

# ============================================
# VERIFICAÇÃO FINAL
# ============================================
print("\n" + "=" * 70)
print("VERIFICAÇÃO FINAL")
print("=" * 70)

with open('lib/services/database_service.dart', 'r', encoding='utf-8') as f:
    final_content = f.read()

checks = [
    ("notas_entrada_local no mapeamento carregar", "notas_entrada_local'" in final_content),
    ("ordens_servico_local no mapeamento carregar", "ordens_servico_local'" in final_content),
    ("trocas_devolucoes_local no mapeamento carregar", "trocas_devolucoes_local'" in final_content),
    ("DELETE notas_entrada_local", "DELETE FROM notas_entrada_local" in final_content),
    ("DELETE ordens_servico_local", "DELETE FROM ordens_servico_local" in final_content),
    ("DELETE trocas_devolucoes_local", "DELETE FROM trocas_devolucoes_local" in final_content),
]

all_ok = True
for name, status in checks:
    symbol = "✅" if status else "❌"
    print(f"  {symbol} {name}")
    if not status:
        all_ok = False

print("=" * 70)
if all_ok:
    print("🎉 TODAS AS ATUALIZAÇÕES CONCLUÍDAS!")
else:
    print("⚠️ ALGUMAS ATUALIZAÇÕES PRECISAM SER VERIFICADAS")
print("=" * 70)
