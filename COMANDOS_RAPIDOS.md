# ⚡ Comandos Rápidos - Configuração do Git

## 🔧 Passo 1: Configurar Credenciais

Execute estes comandos no PowerShell/Terminal (substitua pelos seus dados):

```powershell
git config --global user.name "SEU NOME COMPLETO"
git config --global user.email "SEU_EMAIL@EXAMPLE.COM"
```

### Exemplo:
```powershell
git config --global user.name "Maria Santos"
git config --global user.email "maria.santos@gmail.com"
```

## ✅ Verificar se configurou corretamente:

```powershell
git config --global user.name
git config --global user.email
```

## 📦 Passo 2: Adicionar e Fazer Commit das Mudanças

```powershell
# Navegar para o projeto
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_novo"

# Adicionar todos os arquivos
git add .

# Fazer commit
git commit -m "docs: atualiza configuração e documentação do Git"

# Ver status
git status
```

## 🚀 Passo 3: Enviar para o GitHub

```powershell
git push origin main
```

**Nota:** Se pedir autenticação, use um Personal Access Token do GitHub como senha.

---

**💡 Dica:** Veja o arquivo `CONFIGURACAO_GIT.md` para instruções detalhadas!

