# 💾 Como Salvar Suas Alterações Automaticamente

## 🚀 Uso Rápido

Para salvar todas as suas alterações automaticamente, execute:

```powershell
.\salvar_alteracoes.ps1
```

Isso vai:
- ✅ Verificar todas as alterações no projeto
- ✅ Adicionar todos os arquivos modificados
- ✅ Criar um commit com data e hora
- ✅ Permitir que você volte a qualquer versão anterior

## 📋 Quando Usar

Execute este script sempre que:
- Fizer alterações importantes no código
- Terminar uma funcionalidade
- Antes de testar algo arriscado
- Ao final do dia de trabalho
- Sempre que quiser ter um "ponto de restauração"

## 🔄 Como Voltar para uma Versão Anterior

### Ver todos os commits salvos:
```powershell
git log --oneline
```

### Voltar para um commit específico:
```powershell
git checkout HASH_DO_COMMIT
```

### Voltar para a versão mais recente:
```powershell
git checkout main
```

### Ver o que mudou em um commit:
```powershell
git show HASH_DO_COMMIT
```

## ⚠️ Importante

- Este script **salva localmente** (não envia para internet)
- Para enviar para o GitHub, use: `.\push_para_github.ps1`
- Os commits são salvos com data e hora automática
- Você pode salvar quantas vezes quiser

## 💡 Dica

Crie um atalho ou alias para executar mais rápido:
```powershell
# Adicionar ao seu perfil PowerShell (opcional)
Set-Alias -Name salvar -Value ".\salvar_alteracoes.ps1"
```

Depois é só digitar `salvar` para executar!



