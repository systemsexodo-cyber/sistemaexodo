# 📋 PLANO DE RESTAURAÇÃO DO SISTEMA

## 🎯 Visão Geral

Este documento descreve como restaurar o sistema para versões anteriores de forma segura, caso algo dê errado durante o desenvolvimento.

---

## 🛡️ Proteções Automáticas

### 1. **Backup Antes de Operações**
- ✅ Backup automático antes de cada commit
- ✅ Backup automático antes de cada push
- ✅ Backup completo antes de restaurações

### 2. **Salvamento Automático**
- ✅ Commit automático a cada 20 minutos
- ✅ Push automático a cada 30 minutos
- ✅ Logs detalhados de todas as operações

### 3. **Backups Completos**
- ✅ Backup completo do repositório Git
- ✅ Backup de todos os arquivos do projeto
- ✅ Histórico de commits preservado

---

## 🔄 Métodos de Restauração

### **Método 1: Restauração Rápida (Recomendado)**

Use o script `restaurar_sistema.ps1`:

```powershell
.\restaurar_sistema.ps1
```

**Opções disponíveis:**
1. Digite o **hash do commit** para restaurar uma versão específica
2. Digite **'lista'** para ver todas as versões disponíveis
3. Digite **'atual'** para voltar para a versão mais recente
4. Digite **'sair'** para cancelar

**O que o script faz automaticamente:**
- ✅ Cria backup completo antes de restaurar
- ✅ Cria branch de segurança
- ✅ Salva estado atual
- ✅ Restaura a versão escolhida

---

### **Método 2: Restauração Manual via Git**

#### **Ver commits disponíveis:**
```powershell
git log --oneline
```

#### **Restaurar para um commit específico:**
```powershell
git checkout <hash-do-commit>
```

#### **Voltar para a versão mais recente:**
```powershell
git checkout main
```

#### **Criar branch de segurança antes de restaurar:**
```powershell
git branch backup_antes_restauracao_$(Get-Date -Format "yyyyMMdd_HHmmss")
```

---

### **Método 3: Restauração de Backup Completo**

Se você fez backup completo usando `backup_completo.ps1`:

#### **Restaurar o repositório Git:**
```powershell
git clone backups_exodo\backup_YYYYMMDD_HHMMSS\git\repositorio_completo.bundle projeto_restaurado
```

#### **Restaurar arquivos do projeto:**
Copie os arquivos da pasta `projeto` do backup para o diretório desejado.

---

## 📁 Estrutura de Backups

```
sistema_exodo_01-12/
├── .backups/                    # Backups antes de commits/pushes
│   └── backup_pre_commit_*.txt
│   └── backup_pre_push_*.txt
├── .restore_backups/            # Backups antes de restaurações
│   └── backup_antes_restauracao_*/
├── .salvamento_logs/            # Logs de operações
│   ├── commits.log
│   ├── pushes.log
│   ├── erros.log
│   └── sessao.log
└── ../backups_exodo/            # Backups completos
    └── backup_YYYYMMDD_HHMMSS/
```

---

## 🚨 Cenários de Emergência

### **Cenário 1: Alterações Indesejadas**

**Problema:** Fez alterações que quebraram o sistema

**Solução:**
```powershell
# 1. Ver commits recentes
git log --oneline -10

# 2. Restaurar para commit anterior
.\restaurar_sistema.ps1
# Digite o hash do commit anterior

# OU manualmente:
git checkout <hash-do-commit-anterior>
```

---

### **Cenário 2: Perda de Arquivos**

**Problema:** Arquivos importantes foram deletados

**Solução:**
```powershell
# 1. Ver histórico de commits onde o arquivo existia
git log --all --full-history -- <caminho-do-arquivo>

# 2. Restaurar arquivo de um commit específico
git checkout <hash-do-commit> -- <caminho-do-arquivo>

# 3. Fazer commit da restauração
git add <caminho-do-arquivo>
git commit -m "Restaurar arquivo perdido"
```

---

### **Cenário 3: Commit Errado**

**Problema:** Fez commit de algo que não deveria

**Solução:**
```powershell
# 1. Ver último commit
git log -1

# 2. Desfazer último commit (mantém alterações)
git reset --soft HEAD~1

# 3. OU desfazer completamente
git reset --hard HEAD~1
# ⚠️ CUIDADO: Isso apaga as alterações!
```

---

### **Cenário 4: Push Errado**

**Problema:** Fez push de commits que não deveria

**Solução:**
```powershell
# 1. Ver commits no remoto
git log origin/main --oneline

# 2. Reverter para commit anterior
git revert <hash-do-commit-errado>

# 3. Fazer push da reversão
git push origin main
```

---

## 📝 Checklist de Restauração

Antes de restaurar, verifique:

- [ ] ✅ Backup foi criado automaticamente?
- [ ] ✅ Você sabe qual commit quer restaurar?
- [ ] ✅ Você tem o hash do commit?
- [ ] ✅ Alterações não salvas foram commitadas?
- [ ] ✅ Você tem acesso ao repositório remoto?

---

## 🔍 Verificações Pós-Restauração

Após restaurar, verifique:

1. **Status do Git:**
   ```powershell
   git status
   ```

2. **Commits recentes:**
   ```powershell
   git log --oneline -5
   ```

3. **Arquivos importantes:**
   - Verifique se os arquivos principais estão presentes
   - Teste se o projeto compila/executa

4. **Dependências:**
   - Se necessário, reinstale dependências:
   ```powershell
   flutter pub get
   ```

---

## 📞 Comandos Úteis

### **Ver histórico completo:**
```powershell
git log --oneline --graph --all
```

### **Ver alterações de um commit:**
```powershell
git show <hash-do-commit>
```

### **Ver diferenças entre commits:**
```powershell
git diff <commit1> <commit2>
```

### **Listar branches:**
```powershell
git branch -a
```

### **Ver branches de backup:**
```powershell
git branch | Select-String "backup"
```

---

## ⚠️ Avisos Importantes

1. **Sempre faça backup antes de restaurar**
   - O script `restaurar_sistema.ps1` faz isso automaticamente

2. **Commits não commitados serão perdidos**
   - Sempre faça commit antes de restaurar

3. **Pushes já enviados não podem ser desfeitos facilmente**
   - Use `git revert` em vez de `git reset` para commits já enviados

4. **Teste após restaurar**
   - Sempre teste o projeto após restaurar uma versão

---

## 🎯 Resumo Rápido

**Para restaurar rapidamente:**
```powershell
.\restaurar_sistema.ps1
```

**Para fazer backup completo:**
```powershell
.\backup_completo.ps1
```

**Para ver logs de operações:**
```powershell
Get-Content .salvamento_logs\sessao.log
```

---

## 📚 Documentação Adicional

- **Scripts disponíveis:**
  - `salvamento_inteligente.ps1` - Salvamento automático
  - `restaurar_sistema.ps1` - Restauração segura
  - `backup_completo.ps1` - Backup completo

- **Logs:**
  - `.salvamento_logs/commits.log` - Histórico de commits
  - `.salvamento_logs/pushes.log` - Histórico de pushes
  - `.salvamento_logs/erros.log` - Erros ocorridos

---

**Última atualização:** $(Get-Date -Format "yyyy-MM-dd")

