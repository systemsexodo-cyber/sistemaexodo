# Guia de Testes - Persistência do Caixa

## ✅ Correção Implementada

O sistema agora tem **salvamento robusto do caixa** com:
- ✓ Persistência imediata em localStorage (sem debounce)
- ✓ Sincronização automática com Firebase
- ✓ Fallback local se Firebase estiver indisponível
- ✓ Retry automático na fila de sincronização

## 🧪 Testes a Executar

### Teste 1: Abertura de Caixa Persiste
**Objetivo**: Verificar se caixa aberto no início do dia persiste após app reopen

1. Abrir a aplicação
2. Fazer login
3. Ir para tela de Caixa
4. Clicar em **"Abrir Caixa"** (com valor inicial, ex: R$ 100)
5. Verificar que caixa aparece como **ABERTO** ✓
6. **Fechar completamente a aplicação** (Kill task no Android/iOS ou Cmd+W no Web)
7. **Reabrir a aplicação**
8. Fazer login novamente
9. Ir para tela de Caixa
10. **Esperar 2-3 segundos** (dados carregam do localStorage)
11. Verificar que caixa **AINDA ESTÁ ABERTO** ✓

**Resultado Esperado**: Caixa deve permanecer ABERTO

---

### Teste 2: Fechamento de Caixa Persiste
**Objetivo**: Verificar se caixa fechado é persistido corretamente

1. Com o caixa aberto (do Teste 1)
2. Ir para tela de Caixa
3. Clicar em **"Fechar Caixa"**
4. Preencher valores:
   - Valor Esperado: R$ 100 (ou valor que abriu)
   - Valor Real: R$ 100
   - Diferença: R$ 0
5. Confirmar fechamento
6. Verificar que caixa aparece como **FECHADO** ✓
7. **Fechar completamente a aplicação**
8. **Reabrir a aplicação**
9. Fazer login novamente
10. Ir para tela de Caixa
11. Verificar que caixa **AINDA ESTÁ FECHADO** ✓

**Resultado Esperado**: Caixa deve permanecer FECHADO

---

### Teste 3: Sem Internet (Offline Mode)
**Objetivo**: Verificar se dados são salvos localmente mesmo sem Firebase

1. **Desabilitar internet** (Airplane Mode ou desconectar WiFi)
2. Abrir a aplicação
3. Fazer login (pode usar credenciais em cache)
4. Ir para tela de Caixa
5. Clicar em **"Abrir Caixa"** com R$ 50
6. Verificar que abre normalmente ✓
7. Ver no console que diz: "**ℹ️ Firebase não habilitado - apenas salvamento local**" ou similar ✓
8. **Fechar app completamente**
9. **Reabilitar internet**
10. **Reabrir app**
11. Fazer login
12. Ir para Caixa
13. Verificar que caixa **AINDA ESTÁ ABERTO** ✓

**Resultado Esperado**: Dados locais são restaurados mesmo sem Firebase

---

### Teste 4: Sincronização com Firebase (Online Mode)
**Objetivo**: Verificar que dados sincronizam com Firebase quando volta online

1. **Desabilitar internet**
2. Abrir caixa com R$ 75
3. **Reabilitar internet**
4. **Esperar 5-10 segundos** (sincronização acontece)
5. Verificar no console logs como:
   - "🔥 Salvando abertura current no Firebase..."
   - "✅✅✅ Abertura SALVA NO FIREBASE COM SUCESSO!"
6. Verificar no Firebase Console (se tiver acesso):
   - Ir para Firestore Database
   - Coleção: `empresas/{empresa_id}/abertura_caixa`
   - Deve conter documento com ID do caixa aberto ✓

**Resultado Esperado**: Sincronização automática com Firebase após reconnect

---

### Teste 5: Histórico de Sangrias e Suprimentos
**Objetivo**: Verificar se sangrias/suprimentos do caixa persistem

1. Abrir caixa
2. Registrar Sangria: R$ 20 - Motivo: "Troco"
3. Registrar Suprimento: R$ 30 - Motivo: "Reposição"
4. Fechar caixa
5. **Fechar app**
6. **Reabrir app**
7. Ir para Caixa → Histórico/Fechamento
8. Verificar que **sangrias e suprimentos aparecem** ✓

**Resultado Esperado**: Histórico completo é restaurado

---

## 📊 Checklist de Validação

- [ ] Teste 1: Abertura persiste após app reopen
- [ ] Teste 2: Fechamento persiste após app reopen  
- [ ] Teste 3: Offline mode salva localmente
- [ ] Teste 4: Online mode sincroniza com Firebase
- [ ] Teste 5: Histórico de sangrias/suprimentos persiste

## 🔍 Rastreamento de Debug

Se algo não funcionar, verificar os logs:

### Console - Abertura
```
>>> [Caixa] 💾 Salvando aberturas de caixa imediatamente...
>>> [Caixa] ✅ Aberturas salvas localmente (total: 1)
>>> [Caixa] ✅ Status do caixa salvo: true
>>> [Caixa] 🔥 Salvando abertura current no Firebase...
>>> [Caixa] ✅✅✅ Abertura SALVA NO FIREBASE COM SUCESSO!
```

### Console - Carregamento
```
>>> ✓ 1 aberturas de caixa carregadas (total: 1)
>>> Caixa atual: ABERTO
```

### Console - Erro (localstack salvou, Firebase falhou)
```
>>> [Caixa] ⚠️ Erro ao salvar no Firebase: ...
>>> [Caixa] ✓ Dados já salvos LOCALMENTE - sincronizarão depois
```

## 🐛 Troubleshooting

| Problema | Solução |
|----------|---------|
| Caixa não persiste após reopen | Verificar localStorage no DevTools (Application → Local Storage) |
| Firebase sync não funciona | Verificar conexão de internet e credenciais Firebase |
| Histórico vazio após reopen | Verificar se sangrias/suprimentos foram salvas antes de fechar |
| Múltiplas aberturas aparecem | Verificar se estava limpando lista em vez de fazer upsert |

## 📝 Notas Importantes

1. **Primeira carga** pode levar 2-3 segundos (localStorage + Firebase)
2. **Sem internet**: App funciona 100% (dados locais)
3. **Com internet**: Sincroniza automático a cada 10 segundos
4. **Dados isolados por empresa**: Cada empresa tem seu próprio caixa

## ✨ Benefícios da Solução

- ✅ **Robusto**: Salvamento com fallback local + Firebase
- ✅ **Rápido**: Não bloqueia UI (async operations)
- ✅ **Offline**: Funciona sem internet
- ✅ **Auditável**: Logs detalhados para debug
- ✅ **Escalável**: Funciona com múltiplas aberturas/fechamentos

---

**Implementado em**: January 2025
**Métodos Criados**: `_salvarAberturaCaixaImediatamente()`, `_salvarFechamentoCaixaImediatamente()`
**Status**: ✅ Pronto para Testes
