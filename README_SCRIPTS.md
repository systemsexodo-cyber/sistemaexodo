# 📘 Guia de Scripts - Sistema Êxodo

Este projeto inclui scripts automatizados para facilitar a configuração e execução do Flutter em diferentes máquinas.

## 📋 Scripts Disponíveis

### 🚀 `setup_flutter.ps1` - Configuração Completa
**Use na primeira vez ou em uma máquina nova**

Este script realiza a configuração completa do ambiente:
- ✅ Verifica se Git e Flutter estão instalados
- ✅ Corrige problemas com Dart SDK
- ✅ Instala todas as dependências do projeto
- ✅ Oferece opção para executar o projeto imediatamente

**Como usar:**
```powershell
.\setup_flutter.ps1
```

---

### ⚡ `run_project.ps1` - Execução Rápida
**Use para executar o projeto rapidamente**

Script simplificado para execução diária:
- ✅ Encerra processos Flutter anteriores
- ✅ Remove lock files
- ✅ Executa o projeto

**Como usar:**
```powershell
# Executar no Edge (padrão)
.\run_project.ps1

# Executar em dispositivo específico
.\run_project.ps1 -Device edge
.\run_project.ps1 -Device windows
.\run_project.ps1 -Device chrome
```

---

### 🔧 `fix_flutter.ps1` - Correção de Problemas
**Use quando o Flutter apresentar erros**

Script de diagnóstico e correção para problemas comuns:
- ✅ Corrige erro "Unable to 'pub upgrade' flutter tool"
- ✅ Corrige erro "O sistema não pode encontrar o caminho especificado"
- ✅ Reinstala Dart SDK automaticamente
- ✅ Executa flutter doctor

**Como usar:**
```powershell
.\fix_flutter.ps1
```

---

## 🎯 Fluxo de Trabalho Recomendado

### Em uma máquina nova:
1. Instale Git: https://git-scm.com/download/win
2. Instale Flutter: https://flutter.dev/docs/get-started/install/windows
3. Clone o projeto
4. Execute `.\setup_flutter.ps1`

### No dia a dia:
```powershell
.\run_project.ps1
```

### Quando houver problemas:
```powershell
.\fix_flutter.ps1
```

---

## 🖥️ Dispositivos Disponíveis

### Microsoft Edge (Recomendado para Web)
```powershell
.\run_project.ps1 -Device edge
```

### Windows Desktop
```powershell
.\run_project.ps1 -Device windows
```

### Google Chrome (se instalado)
```powershell
.\run_project.ps1 -Device chrome
```

---

## ⚠️ Problemas Comuns

### "Não é possível executar scripts neste sistema"
**Causa:** Política de execução do PowerShell restritiva

**Solução:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Flutter não encontrado"
**Causa:** Flutter não está no PATH do sistema

**Solução:**
1. Adicione `C:\src\flutter\bin` às variáveis de ambiente PATH
2. Reinicie o PowerShell
3. Execute `flutter --version` para confirmar

### "Git não encontrado"
**Causa:** Git não está instalado ou não está no PATH

**Solução:**
1. Baixe e instale: https://git-scm.com/download/win
2. Reinicie o PowerShell

---

## 📝 Requisitos do Sistema

- ✅ Windows 10 ou superior
- ✅ Git instalado
- ✅ Flutter SDK instalado
- ✅ PowerShell 5.1 ou superior
- ✅ Microsoft Edge (para execução web)

---

## 🆘 Suporte

Se os scripts não resolverem o problema:

1. Execute `flutter doctor -v` para diagnóstico completo
2. Verifique os logs em `flutter.log`
3. Tente limpar o cache: `flutter clean && flutter pub get`

---

## 📄 Licença

Scripts desenvolvidos para o projeto Sistema Êxodo.
Uso livre para fins de desenvolvimento e deployment do projeto.
