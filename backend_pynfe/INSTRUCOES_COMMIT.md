# 📋 Instruções para Fazer Commit das Alterações

## ⚠️ Problema Identificado

O script de proteção/salvamento automático está criando um arquivo `.git/index.lock` continuamente, impedindo operações do Git.

## ✅ Solução

### **Opção 1: Parar o Script de Proteção (Recomendado)**

1. **Pare o script de proteção** que está rodando
2. **Remova o lock manualmente:**
   ```powershell
   Remove-Item "C:\Users\USER\Downloads\Sistema Exodo\.git\index.lock" -Force
   ```
3. **Faça o commit:**
   ```powershell
   cd "C:\Users\USER\Downloads\Sistema Exodo"
   git add "sistema_exodo_01-12/backend_pynfe/services/nfce_service.py"
   git add "sistema_exodo_01-12/backend_pynfe/*.md"
   git commit -m "Correcao erro 225 NFC-e: validacao automatica cMunFG CRT idLote decimais estrutura lote"
   git push --set-upstream origin modo-dev
   ```

### **Opção 2: Usar Git com Bypass do Lock (Temporário)**

Se não conseguir parar o script, tente:

```powershell
# Remover lock
Remove-Item ".git/index.lock" -Force

# Usar variável de ambiente para bypass temporário
$env:GIT_INDEX_FILE = ".git/index.temp"
git add "sistema_exodo_01-12/backend_pynfe/services/nfce_service.py"
git add "sistema_exodo_01-12/backend_pynfe/*.md"
git commit -m "Correcao erro 225 NFC-e: validacao automatica cMunFG CRT idLote decimais estrutura lote"
git push --set-upstream origin modo-dev
```

## 📝 Arquivos Modificados

- `sistema_exodo_01-12/backend_pynfe/services/nfce_service.py`
- `sistema_exodo_01-12/backend_pynfe/*.md` (documentação)

## 🔧 Correções Implementadas

1. ✅ Correção automática de `cMunFG` (nome → código IBGE)
2. ✅ Correção automática de `CRT` (vazio → "1")
3. ✅ Correção de `idLote` (1 dígito → 15 dígitos)
4. ✅ Correção de valores decimais (formato TDec_1302)
5. ✅ Validação e correção da estrutura do lote XML
6. ✅ Interceptação e correção do XML antes de enviar para SEFAZ

## ⚠️ Nota sobre o Hook pre-push

O hook `pre-push` está com código PowerShell mas sendo executado em shell bash. Se o push falhar, você pode:

1. **Desabilitar temporariamente:**
   ```powershell
   Rename-Item ".git/hooks/pre-push" ".git/hooks/pre-push.disabled"
   ```

2. **Ou corrigir o hook** para usar bash ao invés de PowerShell


























