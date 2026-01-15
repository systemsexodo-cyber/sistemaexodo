# 📋 LISTA COMPLETA DE SCRIPTS

## 🎯 Scripts de Salvamento Automático

### 1. **`salvar_alteracoes.ps1`**
**Função:** Salva manualmente todas as alterações do projeto
- Faz commit de todas as mudanças
- Adiciona todos os arquivos modificados
- Cria commit com timestamp
- Mostra hash do commit para restauração
- **Uso:** Execute quando quiser salvar manualmente

---

### 2. **`salvamento_automatico.ps1`**
**Função:** Salvamento automático periódico (versão antiga)
- Verifica alterações a cada X minutos (padrão: 30 min)
- Faz commit automaticamente se houver mudanças
- Roda em loop infinito
- **Uso:** `.\salvamento_automatico.ps1 -IntervalMinutes 30`

---

### 3. **`salvamento_inteligente.ps1`**
**Função:** Salvamento inteligente com intervalos diferentes
- Commit automático a cada 20 minutos (se houver alterações)
- Push automático a cada 30 minutos (se houver commits)
- Backups automáticos antes de cada operação
- Logs detalhados
- **Uso:** `.\salvamento_inteligente.ps1 -CommitIntervalMinutes 20 -PushIntervalMinutes 30`

---

### 4. **`salvamento_tempo_real.ps1`** ⭐ **RECOMENDADO**
**Função:** Salvamento em tempo real (monitora arquivos)
- Monitora alterações de arquivos em tempo real
- Faz commit automaticamente 5 segundos após última alteração
- Push automático a cada 30 minutos
- Ignora arquivos desnecessários (.git, build, etc.)
- **Uso:** `.\salvamento_tempo_real.ps1`

---

## 🛡️ Scripts de Proteção e Configuração

### 5. **`protecao_automatica.ps1`**
**Função:** Configura proteções automáticas via Git hooks
- Configura hook `pre-commit` (salva antes de cada commit)
- Configura hook `pre-push` (backup antes de cada push)
- Proteção contra reset acidental
- Cria script de salvamento periódico
- **Uso:** Execute uma vez para configurar

---

### 6. **`configurar_protecao.ps1`**
**Função:** Configura proteções automáticas (alternativa)
- Similar ao `protecao_automatica.ps1`
- Configura hooks do Git
- **Uso:** Execute uma vez para configurar

---

### 7. **`inicializar_protecoes.ps1`**
**Função:** Inicializa proteções no perfil PowerShell
- Adiciona função de salvamento rápido ao PowerShell
- Carrega automaticamente ao abrir PowerShell
- **Uso:** Execute uma vez e adicione ao perfil

---

### 8. **`iniciar_protecao.ps1`**
**Função:** Inicia o sistema de proteção em background
- Inicia `salvamento_tempo_real.ps1` em janela minimizada
- Facilita o início do salvamento automático
- **Uso:** `.\iniciar_protecao.ps1`

---

## 🔄 Scripts de Restauração

### 9. **`restaurar_versao.ps1`**
**Função:** Restaura para uma versão anterior (básico)
- Lista commits recentes
- Permite escolher commit para restaurar
- Cria backup antes de restaurar
- **Uso:** `.\restaurar_versao.ps1`

---

### 10. **`restaurar_sistema.ps1`**
**Função:** Sistema completo de restauração (avançado)
- Lista versões disponíveis
- Cria backup completo antes de restaurar
- Cria branch de segurança
- Restauração segura com confirmação
- **Uso:** `.\restaurar_sistema.ps1`

---

### 11. **`criar_ponto_restauracao.ps1`** ⭐ **NOVO**
**Função:** Cria ponto de restauração manual
- Cria snapshot completo do projeto
- Você escolhe o nome/descrição
- Salva bundle completo do Git
- Ponto fica salvo permanentemente
- **Uso:** `.\criar_ponto_restauracao.ps1`

---

### 12. **`restaurar_ponto.ps1`** ⭐ **NOVO**
**Função:** Restaura para um ponto de restauração
- Lista todos os pontos criados
- Permite escolher qual ponto restaurar
- Cria backup antes de restaurar
- Restauração completa do sistema
- **Uso:** `.\restaurar_ponto.ps1`

---

### 13. **`listar_pontos_restauracao.ps1`** ⭐ **NOVO**
**Função:** Lista todos os pontos de restauração
- Mostra todos os pontos disponíveis
- Informações detalhadas de cada ponto
- Tamanho e status de cada ponto
- **Uso:** `.\listar_pontos_restauracao.ps1`

---

## 💾 Scripts de Backup

### 14. **`backup_completo.ps1`**
**Função:** Cria backup completo do projeto
- Backup do repositório Git completo (bundle)
- Backup de todos os arquivos do projeto
- Informações detalhadas do backup
- Salva em `../backups_exodo/`
- **Uso:** `.\backup_completo.ps1`

---

## 🔧 Scripts de Configuração

### 15. **`configurar_git.ps1`**
**Função:** Configura credenciais do Git
- Configura nome do usuário
- Configura email do usuário
- Necessário para commits
- **Uso:** Execute uma vez para configurar

---

### 16. **`habilitar_developer_mode.ps1`**
**Função:** Habilita Developer Mode no Windows
- Necessário para symlinks no Flutter
- Requer privilégios de administrador
- **Uso:** Execute como administrador

---

## 📤 Scripts de Push/Deploy

### 17. **`push_para_github.ps1`**
**Função:** Faz push para GitHub com tratamento de erros
- Tenta fazer push
- Trata erros de histórico grande
- Força push se necessário
- **Uso:** `.\push_para_github.ps1`

---

## 📊 Resumo por Categoria

### **Salvamento Automático:**
- `salvar_alteracoes.ps1` - Manual
- `salvamento_automatico.ps1` - Periódico (antigo)
- `salvamento_inteligente.ps1` - Intervalos diferentes
- `salvamento_tempo_real.ps1` - ⭐ Tempo real (RECOMENDADO)

### **Proteção:**
- `protecao_automatica.ps1` - Configura hooks
- `configurar_protecao.ps1` - Configura hooks (alternativa)
- `inicializar_protecoes.ps1` - Inicializa no PowerShell
- `iniciar_protecao.ps1` - Inicia sistema

### **Restauração:**
- `restaurar_versao.ps1` - Básico
- `restaurar_sistema.ps1` - Avançado
- `criar_ponto_restauracao.ps1` - ⭐ Criar ponto manual
- `restaurar_ponto.ps1` - ⭐ Restaurar ponto
- `listar_pontos_restauracao.ps1` - ⭐ Listar pontos

### **Backup:**
- `backup_completo.ps1` - Backup completo

### **Configuração:**
- `configurar_git.ps1` - Configurar Git
- `habilitar_developer_mode.ps1` - Developer Mode

### **Deploy:**
- `push_para_github.ps1` - Push para GitHub

---

## 🚀 Fluxo Recomendado

### **Primeira vez:**
1. `configurar_git.ps1` - Configurar Git
2. `protecao_automatica.ps1` - Configurar proteções
3. `iniciar_protecao.ps1` - Iniciar salvamento automático

### **Uso diário:**
- O sistema salva automaticamente em tempo real
- Use `criar_ponto_restauracao.ps1` antes de grandes mudanças
- Use `restaurar_ponto.ps1` se precisar voltar

### **Backup periódico:**
- `backup_completo.ps1` - Fazer backup completo periodicamente

---

## 📝 Notas

- ⭐ = Scripts novos ou recomendados
- Todos os scripts salvam dentro da pasta do projeto
- Logs são salvos em `.salvamento_logs/`
- Backups são salvos em `.backups/` e `backups_exodo/`
- Pontos de restauração são salvos em `.pontos_restauracao/`

---

**Última atualização:** $(Get-Date -Format "yyyy-MM-dd")


