# Como Fazer Push para o GitHub

## ⚡ Salvar Alterações Automaticamente (Recomendado Primeiro)

Antes de fazer push, salve suas alterações localmente:

```powershell
.\salvar_alteracoes.ps1
```

Este script:
- ✅ Salva automaticamente todas as suas alterações
- ✅ Cria um commit com data e hora
- ✅ Permite voltar a qualquer ponto anterior
- ✅ Rápido e seguro (não envia para internet)

**Dica:** Execute este script sempre que fizer alterações importantes!

## Método Rápido para Push (Recomendado)

Execute o script automático:

```powershell
.\push_para_github.ps1
```

Este script:
- ✅ Cria um repositório limpo apenas com o último commit
- ✅ Faz push para o GitHub automaticamente
- ✅ Sincroniza seu repositório local
- ✅ Sempre funciona, mesmo com histórico grande

## Método Manual

Se preferir fazer manualmente:

1. **Verificar status:**
   ```powershell
   git status
   ```

2. **Fazer commit das alterações (se houver):**
   ```powershell
   git add .
   git commit -m "Sua mensagem de commit"
   ```

3. **Fazer push:**
   ```powershell
   git push -u origin main
   ```

## Solução de Problemas

### Erro: "pack exceeds maximum allowed size"
- Use o script `push_para_github.ps1` que resolve isso automaticamente

### Erro: "non-fast-forward"
- O script usa `--force` automaticamente quando necessário

### Erro de conexão
- Verifique sua chave SSH: `ssh -T git@github.com`
- Verifique se o remote está correto: `git remote -v`

## Informações do Repositório

- **URL:** git@github.com:systemsexodo-cyber/sistemaexodo.git
- **Branch padrão:** main
- **Método:** SSH

---

## 📝 Fluxo Recomendado de Trabalho

1. **Fazer suas alterações no código**
2. **Salvar localmente:** `.\salvar_alteracoes.ps1`
3. **Quando quiser enviar para o GitHub:** `.\push_para_github.ps1`

## 🔄 Como Voltar para uma Versão Anterior

Se você salvou suas alterações e quer voltar:

```powershell
# Ver todos os commits salvos
git log --oneline

# Voltar para um commit específico (substitua HASH pelo hash do commit)
git checkout HASH

# Voltar para a versão mais recente
git checkout main
```

---

**Dica:** Sempre use o script `salvar_alteracoes.ps1` antes de fazer push para garantir que tudo está salvo!

