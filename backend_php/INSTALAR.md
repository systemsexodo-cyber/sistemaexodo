# 🚀 Guia de Instalação - Backend PHP NFC-e

## Passo 1: Verificar Requisitos

### PHP
```bash
php -v
```
Deve ser PHP 7.4 ou superior (recomendado 8.0+)

### Composer
```bash
composer --version
```
Se não tiver, instale em: https://getcomposer.org/download/

### Extensões PHP Necessárias

Execute:
```bash
php -m
```

Verifique se estas extensões estão instaladas:
- curl
- dom
- json
- mbstring
- openssl
- soap
- xml
- zip

**Instalar extensões (Ubuntu/Debian):**
```bash
sudo apt-get install php-curl php-dom php-mbstring php-openssl php-soap php-xml php-zip
```

**Instalar extensões (Windows):**
Edite o `php.ini` e descomente as extensões necessárias.

## Passo 2: Instalar Dependências

```bash
cd backend_php
composer install
```

Isso instalará:
- nfephp-org/sped-nfe (biblioteca de emissão NFC-e)
- monolog/monolog (logs)
- vlucas/phpdotenv (variáveis de ambiente)

## Passo 3: Configurar

```bash
cp .env.example .env
```

Edite o `.env` se necessário (geralmente não precisa alterar para desenvolvimento).

## Passo 4: Testar

### Opção 1: PHP Built-in Server (Recomendado para desenvolvimento)

```bash
php -S localhost:8000 -t .
```

### Opção 2: Apache/Nginx

Configure seu servidor web para apontar para o diretório `backend_php`.

## Passo 5: Verificar se Está Funcionando

Abra no navegador ou use curl:

```bash
curl http://localhost:8000/health
```

Deve retornar:
```json
{
    "status": "ok",
    "message": "Backend PHP NFC-e está funcionando",
    "backend": "php",
    "library": "sped-nfe",
    "version": "5.0"
}
```

## ✅ Pronto!

O backend está funcionando. Agora configure o Flutter para usar esta URL:
```
http://localhost:8000
```











