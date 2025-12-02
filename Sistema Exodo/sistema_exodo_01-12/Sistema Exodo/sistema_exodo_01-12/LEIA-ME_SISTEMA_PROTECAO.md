# 🛡️ SISTEMA DE PROTEÇÃO E SALVAMENTO AUTOMÁTICO

## 📋 Visão Geral

Sistema completo de proteção, salvamento automático e restauração para o projeto Exodo.

---

## 🚀 Início Rápido

### **1. Iniciar Salvamento Automático**

Execute o script de inicialização:

```powershell
.\iniciar_protecao.ps1
```

Ou execute diretamente:

```powershell
.\salvamento_inteligente.ps1
```

**O que faz:**
- ✅ Commit automático a cada **20 minutos** (se houver alterações)
- ✅ Push automático a cada **30 minutos** (se houver commits)
- ✅ Backup automático antes de cada operação
- ✅ Logs detalhados de todas as operações

---

## 📁 Scripts Disponíveis

### **1. `salvamento_inteligente.ps1`**
Script principal de salvamento automático.

**Características:**
- Commit a cada 20 minutos
- Push a cada 30 minutos
- Backups automáticos
- Logs detalhados
- Tratamento de erros

**Uso:**
```powershell
.\salvamento_inteligente.ps1
```

**Parâmetros opcionais:**
```powershell
.\salvamento_inteligente.ps1 -CommitIntervalMinutes 15 -PushIntervalMinutes 45
```

---

### **2. `restaurar_sistema.ps1`**
Sistema completo de restauração para versões anteriores.

**Características:**
- Backup automático antes de restaurar
- Lista de versões disponíveis
- Restauração segura
- Branch de segurança

**Uso:**
```powershell
.\restaurar_sistema.ps1
```

**Opções:**
- Digite o **hash do commit** para restaurar
- Digite **'lista'** para ver versões disponíveis
- Digite **'atual'** para voltar para a versão mais recente
- Digite **'sair'** para cancelar

---

### **3. `backup_completo.ps1`**
Cria backup completo do projeto.

**Características:**
- Backup do repositório Git completo
- Backup de todos os arquivos
- Informações detalhadas
- Bundle do Git

**Uso:**
```powershell
.\backup_completo.ps1
```

**Localização do backup:**
```
../backups_exodo/backup_YYYYMMDD_HHMMSS/
```

---

### **4. `iniciar_protecao.ps1`**
Inicia o sistema de proteção em background.

**Uso:**
```powershell
.\iniciar_protecao.ps1
```

---

## 📂 Estrutura de Arquivos

```
sistema_exodo_01-12/
├── salvamento_inteligente.ps1    # Script principal
├── restaurar_sistema.ps1          # Restauração
├── backup_completo.ps1            # Backup completo
├── iniciar_protecao.ps1           # Inicialização
├── PLANO_RESTAURACAO.md          # Documentação completa
│
├── .backups/                      # Backups automáticos
│   ├── backup_pre_commit_*.txt
│   └── backup_pre_push_*.txt
│
├── .restore_backups/              # Backups de restauração
│   └── backup_antes_restauracao_*/
│
├── .salvamento_logs/               # Logs do sistema
│   ├── commits.log                 # Histórico de commits
│   ├── pushes.log                  # Histórico de pushes
│   ├── erros.log                   # Erros ocorridos
│   └── sessao.log                  # Log da sessão atual
│
└── ../backups_exodo/               # Backups completos
    └── backup_YYYYMMDD_HHMMSS/
```

---

## 🔄 Fluxo de Trabalho

### **Fluxo Normal:**
1. Você trabalha no projeto
2. A cada 20 minutos: sistema verifica alterações e faz commit
3. A cada 30 minutos: sistema verifica commits e faz push
4. Backups são criados automaticamente antes de cada operação

### **Em Caso de Problema:**
1. Execute `.\restaurar_sistema.ps1`
2. Escolha a versão para restaurar
3. Sistema cria backup automático antes de restaurar
4. Restauração é feita de forma segura

---

## 📊 Monitoramento

### **Ver Logs de Commits:**
```powershell
Get-Content .salvamento_logs\commits.log
```

### **Ver Logs de Pushes:**
```powershell
Get-Content .salvamento_logs\pushes.log
```

### **Ver Log da Sessão:**
```powershell
Get-Content .salvamento_logs\sessao.log
```

### **Ver Erros:**
```powershell
Get-Content .salvamento_logs\erros.log
```

---

## 🛠️ Configuração

### **Alterar Intervalos:**

Edite `salvamento_inteligente.ps1` ou use parâmetros:

```powershell
# Commit a cada 15 minutos, push a cada 45 minutos
.\salvamento_inteligente.ps1 -CommitIntervalMinutes 15 -PushIntervalMinutes 45
```

---

## ⚠️ Avisos Importantes

1. **O script precisa estar rodando**
   - Execute `.\iniciar_protecao.ps1` para iniciar
   - Mantenha a janela PowerShell aberta (pode ser minimizada)

2. **Backups são locais**
   - Backups automáticos ficam em `.backups/`
   - Para backup completo, execute `.\backup_completo.ps1`

3. **Logs podem crescer**
   - Revise e limpe logs periodicamente se necessário

4. **Commits automáticos**
   - Mensagens de commit são automáticas
   - Formato: "Salvamento automático - YYYY-MM-DD HH:mm:ss"

---

## 🔍 Verificação de Status

### **Verificar se está rodando:**
```powershell
Get-Process | Where-Object {$_.ProcessName -eq "powershell"} | 
    ForEach-Object { 
        $proc = Get-WmiObject Win32_Process -Filter "ProcessId = $($_.Id)"
        if ($proc.CommandLine -like "*salvamento_inteligente*") {
            Write-Host "Rodando: PID $($_.Id)"
        }
    }
```

### **Ver último commit:**
```powershell
git log -1
```

### **Ver commits pendentes de push:**
```powershell
git log origin/main..HEAD --oneline
```

---

## 📚 Documentação Completa

Para informações detalhadas sobre restauração, consulte:
- **`PLANO_RESTAURACAO.md`** - Guia completo de restauração

---

## 🆘 Solução de Problemas

### **Script não está salvando:**
1. Verifique se está rodando: `Get-Process powershell`
2. Verifique logs: `Get-Content .salvamento_logs\erros.log`
3. Verifique se há alterações: `git status`

### **Erro ao fazer push:**
1. Verifique conexão com repositório remoto: `git remote -v`
2. Verifique credenciais Git
3. Veja logs de erro: `Get-Content .salvamento_logs\erros.log`

### **Precisa restaurar:**
1. Execute: `.\restaurar_sistema.ps1`
2. Siga as instruções na tela
3. Sistema cria backup automático antes de restaurar

---

## ✅ Checklist de Uso

- [ ] Execute `.\iniciar_protecao.ps1` para iniciar
- [ ] Verifique se está rodando (janela minimizada)
- [ ] Trabalhe normalmente no projeto
- [ ] Sistema salva automaticamente
- [ ] Em caso de problema, use `.\restaurar_sistema.ps1`

---

**Última atualização:** $(Get-Date -Format "yyyy-MM-dd")

**Versão:** 2.0

