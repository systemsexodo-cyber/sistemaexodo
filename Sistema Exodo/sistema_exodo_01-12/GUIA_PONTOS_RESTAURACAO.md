# 📌 GUIA DE PONTOS DE RESTAURAÇÃO

## 🎯 O que são Pontos de Restauração?

Pontos de restauração são "snapshots" completos do seu projeto que você pode criar manualmente e restaurar a qualquer momento. Eles são diferentes dos backups automáticos - você decide quando criar e eles ficam salvos permanentemente.

---

## 🚀 Como Usar

### **1. Criar um Ponto de Restauração**

Quando você quiser salvar o estado atual do projeto para restaurar depois:

```powershell
.\criar_ponto_restauracao.ps1
```

**O que acontece:**
- Você digita um nome/descrição para o ponto (ex: "Antes de implementar feature X")
- O sistema cria um backup completo do repositório
- Salva todas as informações necessárias para restaurar
- O ponto fica salvo permanentemente

**Exemplo:**
```
Nome do ponto: Versão estável antes de mudanças
```

---

### **2. Listar Pontos de Restauração**

Para ver todos os pontos disponíveis:

```powershell
.\listar_pontos_restauracao.ps1
```

**Mostra:**
- Nome de cada ponto
- Data de criação
- Tag única
- Commit hash
- Tamanho do backup
- Status (disponível ou não)

---

### **3. Restaurar um Ponto**

Para restaurar o sistema para um ponto anterior:

```powershell
.\restaurar_ponto.ps1
```

**O que acontece:**
1. Lista todos os pontos disponíveis
2. Você escolhe o número do ponto
3. Sistema cria backup do estado atual (antes de restaurar)
4. Restaura o sistema para o ponto escolhido
5. Todas as alterações após aquele ponto são perdidas

**⚠️ ATENÇÃO:** Esta operação é irreversível! O sistema cria um backup antes, mas você perderá todas as alterações feitas após o ponto escolhido.

---

## 📁 Onde são Salvos?

Os pontos de restauração são salvos em:
```
.pontos_restauracao/
├── RESTORE_20251201_163045/
│   ├── info.txt              # Informações do ponto
│   ├── repositorio.bundle    # Backup completo do Git
│   └── arquivos.txt          # Lista de arquivos
├── RESTORE_20251201_170230/
│   └── ...
└── indice.json               # Índice de todos os pontos
```

---

## 💡 Quando Criar um Ponto?

Crie pontos de restauração em momentos importantes:

- ✅ **Antes de grandes mudanças** - "Antes de refatorar código"
- ✅ **Versões estáveis** - "Versão 1.0 funcionando"
- ✅ **Antes de experimentos** - "Antes de testar nova feature"
- ✅ **Marcos importantes** - "Após implementar sistema de pagamento"
- ✅ **Antes de atualizações** - "Antes de atualizar dependências"

---

## 🔄 Diferença entre Sistemas

| Tipo | Quando | Como |
|------|--------|------|
| **Salvamento Automático** | A cada alteração (tempo real) | Automático |
| **Pontos de Restauração** | Quando você quiser | Manual (você decide) |
| **Backup Completo** | Quando quiser backup completo | Manual |

---

## 📋 Exemplos de Uso

### **Cenário 1: Antes de uma Grande Mudança**

```powershell
# 1. Criar ponto antes de começar
.\criar_ponto_restauracao.ps1
# Nome: "Antes de implementar sistema de desconto"

# 2. Fazer suas alterações...
# (trabalhar no código)

# 3. Se algo der errado, restaurar:
.\restaurar_ponto.ps1
# Escolher o ponto criado
```

### **Cenário 2: Versão Estável**

```powershell
# 1. Quando o sistema está funcionando perfeitamente
.\criar_ponto_restauracao.ps1
# Nome: "Versão estável - Sistema completo funcionando"

# 2. Continuar trabalhando normalmente
# (o ponto fica salvo para sempre)

# 3. Se precisar voltar para a versão estável:
.\restaurar_ponto.ps1
```

---

## ⚠️ Avisos Importantes

1. **Pontos ocupam espaço** - Cada ponto cria um backup completo (pode ser grande)
2. **Restauração é irreversível** - Você perderá alterações após o ponto
3. **Sempre há backup** - O sistema cria backup antes de restaurar
4. **Não substitui Git** - Use junto com commits Git, não substitui

---

## 🛠️ Comandos Rápidos

```powershell
# Criar ponto
.\criar_ponto_restauracao.ps1

# Listar pontos
.\listar_pontos_restauracao.ps1

# Restaurar ponto
.\restaurar_ponto.ps1
```

---

## 📊 Gerenciamento

### **Ver tamanho dos pontos:**
```powershell
Get-ChildItem .pontos_restauracao -Directory | ForEach-Object {
    $tamanho = (Get-ChildItem $_.FullName -Recurse | 
        Measure-Object -Property Length -Sum).Sum / 1MB
    Write-Host "$($_.Name): $([math]::Round($tamanho, 2)) MB"
}
```

### **Remover ponto antigo:**
```powershell
# Remover manualmente a pasta do ponto em:
.pontos_restauracao\RESTORE_XXXXXX\
```

---

**Última atualização:** $(Get-Date -Format "yyyy-MM-dd")


