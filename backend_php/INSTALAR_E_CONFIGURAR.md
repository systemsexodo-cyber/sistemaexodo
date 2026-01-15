# ✅ Instalação e Configuração - Backend PHP NFC-e

## 🚀 Passo a Passo Completo

### 1. Instalar PHP (se não tiver)

**Windows:**
- Download: https://windows.php.net/download/
- Instale e adicione ao PATH
- Verifique: `php -v` (precisa ser 7.4+)

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install php php-cli php-xml php-curl php-mbstring php-openssl php-soap php-zip
```

### 2. Instalar Composer

**Windows:**
- Download: https://getcomposer.org/download/
- Execute o instalador .exe

**Linux/Mac:**
```bash
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
```

Verifique: `composer --version`

### 3. Instalar Dependências do Projeto

```bash
cd backend_php
composer install
```

Isso instalará automaticamente:
- ✅ nfephp-org/sped-nfe (v5.0) - Biblioteca de emissão NFC-e
- ✅ monolog/monolog - Sistema de logs
- ✅ vlucas/phpdotenv - Variáveis de ambiente

**Tempo estimado:** 2-5 minutos

### 4. Configurar Ambiente (Opcional)

```bash
cp .env.example .env
```

Edite o `.env` apenas se precisar alterar configurações padrão.

### 5. Iniciar Servidor

**Windows:**
```bash
iniciar.bat
```

**Linux/Mac:**
```bash
php -S localhost:8000 -t .
```

O servidor estará rodando em: **http://localhost:8000**

### 6. Verificar se Está Funcionando

**No navegador:**
```
http://localhost:8000/health
```

**Ou via terminal:**
```bash
curl http://localhost:8000/health
```

**Resposta esperada:**
```json
{
    "status": "ok",
    "message": "Backend PHP NFC-e está funcionando",
    "backend": "php",
    "library": "sped-nfe",
    "version": "5.0"
}
```

## ✅ Instalação Concluída!

Agora você pode:
1. ✅ Usar a API REST
2. ✅ Integrar com Flutter
3. ✅ Emitir NFC-e (após ajustar implementação do SPED-NFe)

## 🔧 Próximo Passo: Ajustar Implementação

Consulte `NOTA_IMPORTANTE.md` para informações sobre como ajustar a implementação do SPED-NFe.

## 📚 Recursos

- **README**: `README.md`
- **Como usar**: `COMO_USAR.md`
- **Nota importante**: `NOTA_IMPORTANTE.md`
- **Documentação SPED-NFe**: https://github.com/nfephp-org/sped-nfe











