# 📋 Instruções Completas - Backend PHP NFC-e com SPED-NFe

## ✅ O Que Foi Criado

Backend PHP completo usando a biblioteca oficial **SPED-NFe** (nfephp-org/sped-nfe) para emissão de NFC-e.

## 🚀 Passo a Passo para Começar

### 1. Instalar PHP

**Windows:**
- Baixe em: https://windows.php.net/download/
- Adicione ao PATH do sistema
- Verifique: `php -v` (deve ser 7.4+)

**Linux:**
```bash
sudo apt-get install php php-cli php-xml php-curl php-mbstring php-openssl php-soap php-zip
```

### 2. Instalar Composer

**Windows:**
- Baixe em: https://getcomposer.org/download/
- Execute o instalador

**Linux/Mac:**
```bash
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
```

Verifique: `composer --version`

### 3. Instalar Dependências

```bash
cd backend_php
composer install
```

Isso instalará:
- ✅ nfephp-org/sped-nfe (v5.0)
- ✅ monolog/monolog (logs)
- ✅ vlucas/phpdotenv (configurações)

### 4. Configurar (Opcional)

```bash
cp .env.example .env
```

Edite o `.env` se necessário (geralmente não precisa para desenvolvimento).

### 5. Iniciar Servidor

**Windows:**
```bash
iniciar.bat
```

**Linux/Mac:**
```bash
php -S localhost:8000 -t .
```

### 6. Testar

Abra no navegador:
```
http://localhost:8000/health
```

Ou use curl:
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

## 🔧 Integrar com Flutter

### Opção 1: Modificar URL no Código

No arquivo `lib/services/nfce_backend_service.dart`, linha ~51:

```dart
return 'http://localhost:8000';  // Alterar de 5000 para 8000
```

### Opção 2: Passar URL ao Criar Serviço

```dart
final nfceService = NFCeBackendService(baseUrl: 'http://localhost:8000');
```

## 📡 Endpoint de Emissão

```
POST http://localhost:8000/api/nfce/emitir
Content-Type: application/json
```

**Formato de requisição:** Mesmo do backend Python (compatível)

**Formato de resposta:** Mesmo do backend Python (compatível)

## 🎯 Vantagens do Backend PHP

1. ✅ **Biblioteca Oficial**: SPED-NFe é a biblioteca mais usada e mantida no Brasil
2. ✅ **Atualizações**: Sempre atualizado com as últimas notas técnicas da SEFAZ
3. ✅ **Documentação**: Excelente documentação e comunidade ativa
4. ✅ **Estabilidade**: Biblioteca madura e testada
5. ✅ **Suporte**: Suporte a todos os estados brasileiros

## 📚 Recursos

- **Documentação SPED-NFe**: https://github.com/nfephp-org/sped-nfe
- **README local**: `backend_php/README.md`
- **Guia de instalação**: `backend_php/INSTALAR.md`

## ⚠️ Observações Importantes

1. **Certificado Digital**: Deve estar em formato PFX/PKCS12 e codificado em base64
2. **Ambiente Homologação**: Configure `ambienteHomologacao: true` para testes
3. **UF e Código IBGE**: Configure corretamente a UF e código IBGE do município
4. **Série NFC-e**: Use série configurada na empresa (geralmente "1")

## 🐛 Troubleshooting

### Erro: "Class not found"
```bash
composer install
composer dump-autoload
```

### Erro: "Certificate read error"
- Verifique se o certificado está em base64 válido
- Verifique se a senha está correta
- Certificado deve estar em formato PFX/PKCS12

### Erro: "CORS"
O CORS já está configurado no código. Se houver problemas, verifique:
- Headers no `.htaccess` (Apache)
- Headers no `index.php` (todos os servidores)

## ✅ Status

- ✅ Estrutura criada
- ✅ Código implementado
- ✅ Documentação completa
- ✅ Scripts de instalação
- ✅ Compatível com Flutter existente

## 🎉 Pronto para Usar!

O backend PHP está configurado e pronto para emitir NFC-e usando a biblioteca oficial SPED-NFe!











