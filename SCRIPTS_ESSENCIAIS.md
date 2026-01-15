# 🎯 SCRIPTS ESSENCIAIS PARA PROTEGER SEU PROJETO

## ⚡ Execução Rápida (Recomendado)

Execute este script para configurar tudo automaticamente:

```powershell
.\configurar_projeto_completo.ps1
```

Este script executa todos os passos importantes automaticamente!

---

## 📋 Scripts Mais Importantes (Ordem de Prioridade)

### **1. `configurar_projeto_completo.ps1`** ⭐ **EXECUTE PRIMEIRO**
**Função:** Configura tudo automaticamente
- Configura Git (se necessário)
- Configura proteções automáticas
- Cria ponto de restauração inicial
- Verifica alterações não salvas
- Inicia sistema de proteção (opcional)
- **Uso:** Execute uma vez para configurar tudo

---

### **2. `configurar_git.ps1`** (Se Git não estiver configurado)
**Função:** Configura credenciais do Git
- Configura nome do usuário
- Configura email do usuário
- **Quando usar:** Primeira vez ou se Git não estiver configurado
- **Uso:** `.\configurar_git.ps1`

---

### **3. `protecao_automatica.ps1`** (Configuração inicial)
**Função:** Configura hooks de proteção do Git
- Hook pre-commit (salva antes de cada commit)
- Hook pre-push (backup antes de cada push)
- Proteção contra reset acidental
- **Quando usar:** Uma vez para configurar
- **Uso:** `.\protecao_automatica.ps1`

---

### **4. `iniciar_protecao.ps1`** ⭐ **EXECUTE SEMPRE**
**Função:** Inicia salvamento automático em tempo real
- Monitora alterações em tempo real
- Salva automaticamente quando você altera arquivos
- Push automático a cada 30 minutos
- **Quando usar:** Sempre que estiver trabalhando
- **Uso:** `.\iniciar_protecao.ps1`

---

### **5. `criar_ponto_restauracao.ps1`** (Antes de grandes mudanças)
**Função:** Cria ponto de restauração manual
- Salva estado completo do projeto
- Você escolhe o nome/descrição
- Ponto fica salvo permanentemente
- **Quando usar:** Antes de grandes mudanças ou versões importantes
- **Uso:** `.\criar_ponto_restauracao.ps1`

---

### **6. `restaurar_ponto.ps1`** (Se precisar voltar)
**Função:** Restaura para um ponto anterior
- Lista todos os pontos disponíveis
- Restaura sistema completo
- **Quando usar:** Se algo der errado e precisar voltar
- **Uso:** `.\restaurar_ponto.ps1`

---

### **7. `backup_completo.ps1`** (Backup periódico)
**Função:** Cria backup completo do projeto
- Backup do repositório Git
- Backup de todos os arquivos
- **Quando usar:** Periodicamente (semanal/mensal)
- **Uso:** `.\backup_completo.ps1`

---

## 🚀 Fluxo Recomendado

### **Primeira Vez (Configuração Inicial):**
```powershell
# 1. Execute o script de configuração completa
.\configurar_projeto_completo.ps1
```

Isso vai:
- ✅ Configurar Git (se necessário)
- ✅ Configurar proteções
- ✅ Criar ponto de restauração inicial
- ✅ Verificar alterações
- ✅ Perguntar se quer iniciar salvamento automático

---

### **Uso Diário:**
```powershell
# 1. Iniciar salvamento automático (sempre que for trabalhar)
.\iniciar_protecao.ps1

# 2. Trabalhar normalmente no projeto
# (O sistema salva automaticamente em tempo real)

# 3. Antes de grandes mudanças, criar ponto de restauração:
.\criar_ponto_restauracao.ps1
```

---

### **Se Algo Der Errado:**
```powershell
# 1. Restaurar para um ponto anterior
.\restaurar_ponto.ps1

# 2. Escolher o ponto para restaurar
# 3. Sistema restaura automaticamente
```

---

## 📊 Resumo dos Scripts Essenciais

| Script | Quando Usar | Prioridade |
|--------|-------------|------------|
| `configurar_projeto_completo.ps1` | Primeira vez | ⭐⭐⭐ CRÍTICO |
| `iniciar_protecao.ps1` | Sempre que trabalhar | ⭐⭐⭐ CRÍTICO |
| `criar_ponto_restauracao.ps1` | Antes de grandes mudanças | ⭐⭐ IMPORTANTE |
| `restaurar_ponto.ps1` | Se precisar voltar | ⭐⭐ IMPORTANTE |
| `backup_completo.ps1` | Periodicamente | ⭐ RECOMENDADO |
| `configurar_git.ps1` | Se Git não configurado | ⭐ OPCIONAL |
| `protecao_automatica.ps1` | Configuração inicial | ⭐ OPCIONAL |

---

## ✅ Checklist de Proteção

- [ ] Execute `configurar_projeto_completo.ps1` (primeira vez)
- [ ] Execute `iniciar_protecao.ps1` (sempre que trabalhar)
- [ ] Crie pontos de restauração antes de grandes mudanças
- [ ] Faça backup completo periodicamente

---

## 🎯 Script Único Mais Importante

**`configurar_projeto_completo.ps1`**

Execute este script e ele configura tudo automaticamente!

---

**Última atualização:** $(Get-Date -Format "yyyy-MM-dd")


