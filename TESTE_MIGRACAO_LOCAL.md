# Guia de Testes - Migração NFC-e 100% Local

## 📋 Objetivo
Validar que o sistema de emissão NFC-e funciona 100% localmente, sem depender de túneis Firebase, mantendo salvamento dual (SQLite + Supabase).

## 🔧 Pré-requisitos
1. **ExodoNfceBridge.exe** rodando em `localhost:8000`
2. **Flutter app** compilado e executando
3. **Supabase** configurado (opcional para fallback)
4. **Certificado digital** válido configurado na empresa

## 🧪 Casos de Teste

### 1. Teste Básico - Emissão Local
- [ ] Abrir o bridge NFC-e em `localhost:8000`
- [ ] Acessar o app Flutter
- [ ] Realizar uma venda simples
- [ ] Emitir NFC-e
- [ ] **Verificar**: NFC-e emitida com sucesso
- [ ] **Verificar**: Dados salvos no SQLite local
- [ ] **Verificar**: Dados salvos no Supabase (se online)

### 2. Teste Offline - Apenas SQLite
- [ ] Desconectar internet
- [ ] Manter bridge NFC-e rodando
- [ ] Realizar venda e emitir NFC-e
- [ ] **Verificar**: NFC-e emitida com sucesso
- [ ] **Verificar**: Dados salvos apenas no SQLite
- [ ] **Verificar**: Log "Supabase offline" no console

### 3. Teste de Conexão - Bridge Offline
- [ ] Parar o bridge NFC-e
- [ ] Tentar emitir NFC-e
- [ ] **Verificar**: Mensagem de erro clara
- [ ] **Verificar**: Sistema não crasha

### 4. Teste de Performance - Múltiplas Emissões
- [ ] Realizar 5 emissões seguidas
- [ ] **Verificar**: Performance aceitável (< 10s por emissão)
- [ ] **Verificar**: Todos os dados salvos corretamente

### 5. Teste de Configuração - URL Customizada
- [ ] Configurar URL diferente do bridge (ex: `http://localhost:9000`)
- [ ] Rodar bridge na porta configurada
- [ ] **Verificar**: Sistema conecta na porta correta

## 📊 Logs Esperados

### Emissão Sucesso:
```
>>> [NFCeLocal] Preparando payload...
>>> [NFCeLocal] Enviando para http://localhost:8000/api/nfce/emitir...
>>> [NFCeLocal] ✅ NFC-e emitida: [chave_acesso]
>>> [NFCeLocal] ✅ NFC-e salva no Supabase.
>>> [NFCeLocal] ✅ NFC-e salva no SQLite.
```

### Offline (apenas SQLite):
```
>>> [NFCeLocal] Supabase offline - NFC-e ficará só no SQLite.
>>> [NFCeLocal] ✅ NFC-e salva no SQLite.
```

### Bridge Offline:
```
Não foi possível conectar ao Emissor NFC-e.

Certifique-se que o ExodoNfceBridge.exe está aberto.

Detalhe: Connection refused
```

## 🗂️ Verificação de Dados

### SQLite Local:
```sql
SELECT * FROM nfces_local ORDER BY created_at DESC LIMIT 5;
```

### Supabase:
```sql
SELECT * FROM nfces ORDER BY created_at DESC LIMIT 5;
```

## ✅ Critérios de Sucesso
- [ ] Emissão funciona 100% localmente
- [ ] Sistema opera offline (apenas SQLite)
- [ ] Salvamento dual funciona quando online
- [ ] Mensagens de erro são claras
- [ ] Performance aceitável
- [ ] Nenhuma referência a túneis Firebase

## 🚨 Pontos de Atenção
1. **Bridge deve estar sempre rodando** para emissão
2. **Certificado digital** deve ser válido e acessível
3. **Porta 8000** deve estar disponível
4. **Firewall** não deve bloquear localhost

## 📝 Relatório de Testes
Data: _____/_____/______
Testador: ________________________

| Teste | Status | Observações |
|-------|--------|-------------|
| Emissão Básica | ✅/❌ | |
| Offline SQLite | ✅/❌ | |
| Bridge Offline | ✅/❌ | |
| Múltiplas Emissões | ✅/❌ | |
| URL Customizada | ✅/❌ | |

**Resultado Final:** APROVADO/REPROVADO
_________________________
