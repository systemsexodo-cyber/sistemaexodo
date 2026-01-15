# 📋 Como Instalar PHP e Composer (Windows)

## ⚠️ Requisitos Não Encontrados

O sistema não encontrou o **PHP** e/ou **Composer** instalados no seu computador.

## 🚀 Instalação Passo a Passo

### 1. Instalar PHP

#### Opção A: Download Direto (Recomendado)

1. **Baixar PHP:**
   - Acesse: https://windows.php.net/download/
   - Baixe a versão **Thread Safe** (TS) em ZIP
   - Recomendado: PHP 8.1 ou 8.2 (x64)

2. **Extrair:**
   - Extraia o arquivo ZIP em `C:\php`
   - Exemplo: `C:\php\php8.1`

3. **Adicionar ao PATH:**
   - Pressione `Win + R`
   - Digite: `sysdm.cpl` e pressione Enter
   - Aba "Avançado" → "Variáveis de Ambiente"
   - Em "Variáveis do sistema", selecione "Path" → "Editar"
   - Clique em "Novo" e adicione: `C:\php`
   - Clique em "OK" em todas as janelas

4. **Verificar:**
   - Abra um novo PowerShell/CMD
   - Execute: `php --version`
   - Deve mostrar a versão do PHP

#### Opção B: Usar XAMPP (Mais Fácil)

1. **Baixar XAMPP:**
   - Acesse: https://www.apachefriends.org/download.html
   - Baixe e instale o XAMPP

2. **Adicionar ao PATH:**
   - O PHP do XAMPP fica em: `C:\xampp\php`
   - Adicione ao PATH conforme instruções acima

### 2. Instalar Composer

#### Opção A: Instalador Windows (Recomendado)

1. **Baixar Instalador:**
   - Acesse: https://getcomposer.org/download/
   - Clique em "Composer-Setup.exe"
   - Baixe e execute o instalador

2. **Seguir Instruções:**
   - O instalador detecta o PHP automaticamente
   - Clique em "Next" até concluir

3. **Verificar:**
   - Abra um novo PowerShell/CMD
   - Execute: `composer --version`
   - Deve mostrar a versão do Composer

#### Opção B: Instalação Manual

1. **Baixar Composer:**
   - Acesse: https://getcomposer.org/download/
   - Baixe `composer.phar`

2. **Mover para pasta do PHP:**
   - Copie `composer.phar` para `C:\php\`
   - Renomeie para `composer.bat`
   - Crie um arquivo `composer.bat` com:
   ```batch
   @echo off
   php "%~dp0composer.phar" %*
   ```

3. **Verificar:**
   - Execute: `composer --version`

## ✅ Após Instalar

### 1. Instalar Dependências do Projeto

Abra o PowerShell/CMD na pasta `backend_php` e execute:

```bash
composer install
```

Ou se usar composer.phar local:

```bash
php composer.phar install
```

### 2. Verificar Instalação

```bash
php --version
composer --version
```

## 🎯 Instalação Rápida (Usando Scripts)

Execute na pasta `backend_php`:

```bash
# Se tiver PHP mas não tiver Composer:
instalar_composer.bat

# Depois instalar dependências:
instalar_dependencias.bat
```

## 📝 Requisitos do PHP

O PHP precisa das seguintes extensões:
- ext-curl
- ext-dom
- ext-json
- ext-mbstring
- ext-openssl
- ext-soap
- ext-xml
- ext-zip

**Nota:** O XAMPP já vem com todas essas extensões habilitadas.

## ❓ Problemas Comuns

### "PHP não reconhecido"
- Certifique-se de que adicionou o PHP ao PATH
- Feche e abra um novo terminal
- Verifique se o caminho está correto

### "Composer não reconhecido"
- Certifique-se de que instalou o Composer
- Feche e abra um novo terminal
- Tente usar `php composer.phar` ao invés de `composer`

### "Extensões não encontradas"
- Edite o arquivo `php.ini`
- Descomente as extensões necessárias (remova o `;` no início)
- Reinicie o terminal

## ✅ Pronto!

Após instalar PHP e Composer, você poderá instalar as dependências e usar o backend PHP para emissão de NFC-e!











