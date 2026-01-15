# ⚠️ LEIA PRIMEIRO - Instalação do Backend PHP

## 🔍 Verificação de Requisitos

Antes de instalar as dependências, você precisa ter:

1. ✅ **PHP 7.4+** instalado e no PATH
2. ✅ **Composer** instalado

## ❌ Status Atual

O sistema detectou que:
- ❌ PHP não está instalado ou não está no PATH
- ❌ Composer não está instalado ou não está no PATH

## 🚀 Como Resolver

### Opção 1: Instalação Completa (Recomendado)

1. **Instale o XAMPP** (vem com PHP + extensões):
   - Download: https://www.apachefriends.org/download.html
   - Instale normalmente
   - O PHP fica em: `C:\xampp\php`
   - Adicione ao PATH: `C:\xampp\php`

2. **Instale o Composer**:
   - Download: https://getcomposer.org/download/
   - Execute `Composer-Setup.exe`
   - O instalador detecta o PHP automaticamente

3. **Instale as dependências**:
   ```bash
   cd backend_php
   composer install
   ```

### Opção 2: Instalação Manual

Consulte o arquivo: **`COMO_INSTALAR_PHP_E_COMPOSER.md`**

## 📋 Arquivos Úteis

- `COMO_INSTALAR_PHP_E_COMPOSER.md` - Guia completo de instalação
- `instalar_composer.bat` - Script para instalar Composer localmente
- `instalar_dependencias.bat` - Script para instalar dependências
- `instalar.bat` - Script completo de instalação

## ✅ Após Instalar PHP e Composer

Execute:

```bash
cd backend_php
composer install
```

## 🎯 Próximos Passos

1. Instale PHP e Composer (veja guias acima)
2. Execute `composer install`
3. Execute `iniciar.bat` para iniciar o servidor
4. Teste em: http://localhost:8000/health

## ❓ Precisa de Ajuda?

Consulte a documentação completa:
- `COMO_INSTALAR_PHP_E_COMPOSER.md` - Instalação detalhada
- `README.md` - Documentação geral
- `INSTALAR.md` - Guia de instalação











