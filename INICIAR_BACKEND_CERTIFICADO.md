# 🚀 Guia Rápido - Iniciar Backend para Certificados

## Problema
O certificado de homologação não pode ser processado localmente pelo Flutter devido à estrutura ASN.1 não padrão. A solução é usar o backend Node.js.

## Solução Rápida (5 minutos)

### 1. Abrir Terminal/PowerShell
Navegue até a pasta do backend:
```bash
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12\backend-certificado"
```

### 2. Instalar Dependências (primeira vez apenas)
```bash
npm install
```

### 3. Iniciar o Servidor
```bash
npm start
```

Ou diretamente com Node:
```bash
node server.js
```

### 4. Verificar se Está Rodando
Você deve ver uma mensagem como:
```
Servidor rodando na porta 3001
```

### 5. Manter o Terminal Aberto
⚠️ **IMPORTANTE**: Mantenha o terminal aberto enquanto usar o app. O servidor precisa estar rodando.

## Testar se Está Funcionando

Abra o navegador e acesse:
```
http://localhost:3001/api/health
```

Deve retornar:
```json
{"status": "ok"}
```

## Próximos Passos

1. ✅ Inicie o backend (siga os passos acima)
2. ✅ Mantenha o terminal aberto
3. ✅ Tente emitir a NFC-e novamente no app
4. ✅ O sistema detectará automaticamente que o backend está disponível e usará ele

## Solução Permanente (Opcional)

Se quiser uma solução mais robusta, configure o Firebase Cloud Function seguindo o guia em:
- `functions-certificado/DEPLOY.md`

## Troubleshooting

### Erro: "porta 3001 já está em uso"
Algum processo já está usando a porta. Opções:
1. Feche o processo que está usando a porta
2. Ou altere a porta no arquivo `server.js` (linha que define `const PORT`)

### Erro: "npm não encontrado"
Instale o Node.js: https://nodejs.org/

### Backend inicia mas o app não conecta
1. Verifique se o backend está realmente rodando (teste no navegador)
2. Verifique se não há firewall bloqueando
3. Verifique se a URL no código está correta: `http://localhost:3001`

## Status Atual

- ✅ Código atualizado para detectar automaticamente erros de parsing
- ✅ Sistema tenta Firebase primeiro, depois backend local
- ⚠️ Firebase está com erro interno (precisa ser configurado)
- ⚠️ Backend local não está rodando (precisa ser iniciado)

**Ação necessária**: Iniciar o backend local seguindo os passos acima.





