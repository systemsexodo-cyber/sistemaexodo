# 🚀 Como Enviar Apenas o Último Commit

## ⚠️ Problema de Autenticação

O erro HTTP 500 indica que você precisa configurar autenticação no GitHub.

## 🔐 Passo 1: Criar Personal Access Token

1. Acesse: https://github.com/settings/tokens
2. Clique em **"Generate new token"** → **"Generate new token (classic)"**
3. Dê um nome: `Sistema Exodo`
4. Selecione o escopo: **`repo`** (acesso completo aos repositórios)
5. Clique em **"Generate token"**
6. **COPIE O TOKEN** (você só verá uma vez!)

## 🔧 Passo 2: Configurar Token no Git

### Opção A: Usar no URL do remote

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_novo"

# Substitua SEU_TOKEN pelo token que você copiou
git remote set-url origin https://SEU_TOKEN@github.com/systemsexodo-cyber/exodosystems.git
```

### Opção B: Usar Gerenciador de Credenciais

Quando fizer push, use o token como senha quando solicitado.

## 📤 Passo 3: Enviar Apenas o Último Commit

Para enviar apenas o último commit (sem os outros 9), temos algumas opções:

### Opção 1: Criar branch temporário (recomendado)

```powershell
# Criar um branch a partir do último commit do remoto
git fetch origin
git checkout -b temp-last-commit origin/main

# Fazer cherry-pick do último commit
git cherry-pick 2129279

# Enviar para o main (sobrescrever apenas com esse commit)
git push origin temp-last-commit:main --force-with-lease

# Voltar para o branch main
git checkout main

# Limpar o branch temporário
git branch -D temp-last-commit
```

### Opção 2: Reset e push forçado (cuidado!)

```powershell
# Isso vai descartar os outros 9 commits localmente
git fetch origin
git reset --hard origin/main
git cherry-pick 2129279
git push origin main --force-with-lease
```

### Opção 3: Enviar todos os commits (mais simples)

```powershell
git push origin main
```

Isso enviará os 10 commits, mas você pode deletar os 9 anteriores no GitHub se necessário.

## ✅ Verificar

Após o push:

```powershell
git log origin/main --oneline -5
```

---

**⚠️ Importante:** 
- O token tem acesso total ao repositório - mantenha-o seguro!
- Não compartilhe o token publicamente
- Você pode revogar o token a qualquer momento no GitHub


