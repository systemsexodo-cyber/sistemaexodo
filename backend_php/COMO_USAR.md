# 🚀 Como Usar o Backend PHP NFC-e

## Instalação Rápida

```bash
# 1. Instalar dependências
cd backend_php
composer install

# 2. Iniciar servidor
php -S localhost:8000 -t .

# 3. Testar
curl http://localhost:8000/health
```

## Integração com Flutter

O backend PHP é **totalmente compatível** com o código Flutter existente!

### Alterar URL no Flutter

**Opção 1:** Editar `lib/services/nfce_backend_service.dart`

Linha ~51, altere:
```dart
return 'http://localhost:8000';  // Era 5000, agora 8000
```

**Opção 2:** Passar URL ao criar serviço

```dart
final nfceService = NFCeBackendService(baseUrl: 'http://localhost:8000');
```

## Estrutura de Dados

O formato de requisição é **exatamente igual** ao backend Python:

```json
{
    "empresa": {
        "cnpj": "...",
        "certificado_base64": "...",
        "senhaCertificado": "..."
    },
    "produtos": [...],
    "pagamentos": [...]
}
```

## Exemplo de Teste

Use o arquivo `exemplo_uso.php` como referência:

```bash
php exemplo_uso.php
```

**Nota:** Lembre-se de preencher o certificado_base64 com um certificado válido!

## Logs

Logs são salvos em: `logs/app.log`

Para ver em tempo real:
```bash
tail -f logs/app.log
```

## XMLs Salvos

XMLs são salvos em: `storage/xml/{empresa_id}/`

Estrutura:
```
storage/xml/
  └── {empresa_id}/
      ├── {chave}-nfe.xml      (XML assinado)
      └── {chave}-retorno.xml  (Resposta SEFAZ)
```

## Próximos Passos

1. ✅ Instalar dependências (`composer install`)
2. ✅ Iniciar servidor (`php -S localhost:8000`)
3. ✅ Testar health check
4. ✅ Configurar Flutter para usar porta 8000
5. ✅ Emitir NFC-e!











