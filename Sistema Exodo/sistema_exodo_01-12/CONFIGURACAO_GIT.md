# 🔧 Guia Completo de Configuração do Git e GitHub

Este guia irá ajudá-lo a configurar o Git e GitHub do zero para este projeto.

## 📋 Pré-requisitos

1. **Git instalado** - Baixe em: https://git-scm.com/downloads
2. **Conta no GitHub** - Crie em: https://github.com/signup
3. **Acesso ao repositório** - Este projeto já está conectado ao repositório:
   - URL: `https://github.com/systemsexodo-cyber/exodosystems.git`

## 🎯 Passo 1: Configurar suas Credenciais do Git

### Configuração Global (recomendado)

Execute os seguintes comandos no terminal, substituindo pelos seus dados:

```bash
git config --global user.name "Seu Nome Completo"
git config --global user.email "seu.email@example.com"
```

**Exemplo:**
```bash
git config --global user.name "João Silva"
git config --global user.email "joao.silva@exemplo.com"
```

### Verificar Configuração

Para verificar se foi configurado corretamente:

```bash
git config --global user.name
git config --global user.email
```

### Configuração Local (apenas para este projeto)

Se preferir configurar apenas para este projeto específico:

```bash
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_novo"
git config user.name "Seu Nome"
git config user.email "seu.email@example.com"
```

## 🔐 Passo 2: Configurar Autenticação no GitHub

### Opção 1: Personal Access Token (PAT) - Recomendado

1. **Criar um Personal Access Token:**
   - Acesse: https://github.com/settings/tokens
   - Clique em "Generate new token" → "Generate new token (classic)"
   - Dê um nome ao token (ex: "Sistema Exodo")
   - Selecione os escopos: `repo` (acesso completo aos repositórios)
   - Clique em "Generate token"
   - **COPIE O TOKEN** (você só verá uma vez!)

2. **Usar o token ao fazer push:**
   - Quando o Git pedir senha, use o token no lugar da senha
   - Ou configure no URL do repositório:

```bash
git remote set-url origin https://SEU_TOKEN@github.com/systemsexodo-cyber/exodosystems.git
```

### Opção 2: SSH Keys (mais seguro)

1. **Gerar chave SSH:**
```bash
ssh-keygen -t ed25519 -C "seu.email@example.com"
```

2. **Adicionar chave SSH ao GitHub:**
   - Copie o conteúdo do arquivo: `C:\Users\USER\.ssh\id_ed25519.pub`
   - Acesse: https://github.com/settings/keys
   - Clique em "New SSH key"
   - Cole a chave pública
   - Salve

3. **Alterar URL do repositório para SSH:**
```bash
git remote set-url origin git@github.com:systemsexodo-cyber/exodosystems.git
```

## 📂 Passo 3: Navegar para o Diretório do Projeto

Sempre que for trabalhar no projeto, navegue até o diretório:

```bash
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_novo"
```

## ✅ Passo 4: Verificar Estado Atual

Verifique o status do repositório:

```bash
git status
```

Você verá:
- Arquivos modificados
- Arquivos não rastreados
- Branch atual

## 🔄 Passo 5: Trabalho Diário com Git

### Verificar mudanças

```bash
git status
```

### Adicionar arquivos ao stage

```bash
# Adicionar um arquivo específico
git add nome_do_arquivo.dart

# Adicionar todos os arquivos modificados
git add .

# Adicionar todos os arquivos (incluindo novos)
git add -A
```

### Fazer commit

```bash
git commit -m "Descrição clara do que foi alterado"
```

**Exemplos de mensagens de commit:**
```bash
git commit -m "feat: adiciona busca inteligente de produtos"
git commit -m "fix: corrige bug no cálculo de preços"
git commit -m "refactor: melhora estrutura do código de pedidos"
git commit -m "docs: atualiza README com instruções de instalação"
```

### Enviar para o GitHub

```bash
# Enviar para o branch atual
git push

# Enviar para um branch específico
git push origin main

# Primeira vez em um branch novo
git push -u origin nome-do-branch
```

### Baixar atualizações do GitHub

```bash
# Buscar e fazer merge
git pull

# Apenas buscar (sem fazer merge)
git fetch
```

## 🌿 Passo 6: Trabalhando com Branches

### Criar novo branch

```bash
git checkout -b nome-do-branch
```

**Exemplo:**
```bash
git checkout -b feature/nova-funcionalidade
git checkout -b fix/corrige-bug
```

### Listar branches

```bash
git branch
```

### Trocar de branch

```bash
git checkout nome-do-branch
```

### Ver branch atual

```bash
git branch --show-current
```

## 📊 Passo 7: Comandos Úteis

### Ver histórico de commits

```bash
# Últimos 10 commits
git log --oneline -10

# Histórico completo com detalhes
git log

# Histórico em gráfico
git log --graph --oneline --all
```

### Ver diferenças

```bash
# Diferenças não commitadas
git diff

# Diferenças de um arquivo específico
git diff nome_do_arquivo.dart
```

### Desfazer mudanças

```bash
# Desfazer mudanças não commitadas (cuidado!)
git restore nome_do_arquivo.dart

# Desfazer todas as mudanças não commitadas
git restore .

# Desfazer último commit (mantém as mudanças)
git reset --soft HEAD~1
```

## 🚨 Resolver Conflitos

Quando `git pull` encontrar conflitos:

1. **Abra os arquivos com conflito** (procure por `<<<<<<<`, `=======`, `>>>>>>>`)
2. **Resolva manualmente** escolhendo qual código manter
3. **Remova os marcadores de conflito**
4. **Adicione os arquivos resolvidos:**
```bash
git add arquivo_com_conflito.dart
```
5. **Complete o merge:**
```bash
git commit
```

## 🔗 Estado Atual do Repositório

- **Repositório Remoto:** https://github.com/systemsexodo-cyber/exodosystems.git
- **Branch Principal:** `main`
- **Status:** Conectado e funcionando

Você tem 9 commits locais que ainda não foram enviados. Para enviá-los:

```bash
git push origin main
```

## 📝 Checklist de Configuração

- [ ] Git instalado e funcionando
- [ ] Nome e email configurados no Git
- [ ] Conta no GitHub criada
- [ ] Token de acesso ou SSH configurado
- [ ] Repositório clonado/localizado
- [ ] Primeiro commit realizado
- [ ] Primeiro push realizado

## 🆘 Solução de Problemas

### Erro: "fatal: not a git repository"

```bash
# Inicializar repositório (se necessário)
git init
```

### Erro: "permission denied (publickey)"

- Configure SSH keys ou use Personal Access Token

### Erro: "remote origin already exists"

```bash
# Ver remotes configurados
git remote -v

# Alterar URL do remote
git remote set-url origin NOVA_URL
```

### Esqueceu de configurar nome/email antes do commit?

```bash
# Alterar autor do último commit
git commit --amend --author="Seu Nome <seu.email@example.com>"
```

## 📚 Recursos Adicionais

- [Documentação Oficial do Git](https://git-scm.com/doc)
- [GitHub Guides](https://guides.github.com/)
- [Flutter Git Workflow](https://docs.flutter.dev/development/tools/version-control)

---

**Última atualização:** 2024

**Próximo passo:** Configure suas credenciais e faça seu primeiro push!

