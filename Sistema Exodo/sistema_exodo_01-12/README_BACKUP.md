# Sistema de Backup e Versionamento

Sistema completo para criar backups e restaurar versões anteriores do projeto Sistema Exodo.

## 📋 Funcionalidades

- ✅ **Backup Automático**: Cria backups completos do projeto
- ✅ **Versionamento**: Mantém histórico de versões com timestamps
- ✅ **Restauração**: Restaura qualquer versão anterior
- ✅ **Limpeza Automática**: Remove versões antigas (mantém últimas 20)
- ✅ **Informações do Git**: Inclui informações do Git em cada backup

## 🚀 Como Usar

### Criar um Backup

```powershell
.\sistema_backup_versionamento.ps1 -Acao backup
```

### Listar Versões Disponíveis

```powershell
.\sistema_backup_versionamento.ps1 -Acao listar
```

### Restaurar uma Versão

```powershell
.\sistema_backup_versionamento.ps1 -Acao restaurar -VersaoId v_20251202_120000
```

### Limpar Versões Antigas

```powershell
.\sistema_backup_versionamento.ps1 -Acao limpar
```

## 📁 Estrutura de Backups

Os backups são armazenados em:
```
.backups_versionamento/
├── versoes/
│   ├── v_20251202_120000/
│   │   ├── lib/
│   │   ├── pubspec.yaml
│   │   ├── info.txt
│   │   └── git_info.txt
│   └── v_20251202_130000/
│       └── ...
└── indice_versoes.json
```

## 📝 Informações Armazenadas

Cada backup contém:
- ✅ Código fonte (`lib/`)
- ✅ Configurações (`pubspec.yaml`, `firebase.json`, etc.)
- ✅ Scripts importantes
- ✅ Informações do Git (commit, branch, status)
- ✅ Metadados (data, tamanho, quantidade de arquivos)

## ⚠️ Importante

- **Antes de restaurar**: O sistema cria automaticamente um backup de segurança
- **Limpeza**: Mantém apenas as últimas 20 versões por padrão
- **Localização**: Backups ficam em `.backups_versionamento/` (não versionado no Git)

## 🔄 Integração com Git

O sistema captura informações do Git em cada backup:
- Commit atual
- Branch ativo
- Status do repositório

Isso ajuda a identificar qual versão do código está em cada backup.

## 💡 Dicas

1. **Backup antes de grandes mudanças**: Sempre crie um backup antes de fazer alterações significativas
2. **Nomes descritivos**: O sistema usa timestamps, mas você pode adicionar descrições manualmente no arquivo `info.txt`
3. **Limpeza periódica**: Execute a limpeza periodicamente para economizar espaço
4. **Backup de segurança**: O sistema cria backup automático antes de restaurar

## 📊 Exemplo de Uso

```powershell
# 1. Criar backup antes de fazer alterações
.\sistema_backup_versionamento.ps1 -Acao backup

# 2. Fazer suas alterações no código...

# 3. Se algo der errado, listar versões
.\sistema_backup_versionamento.ps1 -Acao listar

# 4. Restaurar versão anterior
.\sistema_backup_versionamento.ps1 -Acao restaurar -VersaoId v_20251202_120000
```

