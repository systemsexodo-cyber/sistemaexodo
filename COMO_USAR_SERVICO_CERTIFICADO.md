# 🚀 COMO USAR O SERVIÇO DE CONVERSÃO DE CERTIFICADO

## 📋 PRÉ-REQUISITOS:

1. **Node.js instalado** (versão 14 ou superior)
   - Baixar em: https://nodejs.org/
   - Verificar instalação: `node --version`

## 🔧 INSTALAÇÃO:

### 1. Instalar dependências:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12"
npm install
```

### 2. Iniciar o servidor:

```powershell
npm start
```

Ou:

```powershell
node conversor_certificado_server.js
```

Você verá:
```
========================================
  SERVIDOR DE CONVERSÃO DE CERTIFICADO
========================================
Servidor rodando em: http://localhost:3000
```

## ✅ TESTE RÁPIDO:

Abra outro terminal e teste:

```powershell
curl http://localhost:3000/health
```

Deve retornar: `{"status":"ok","servico":"Conversor de Certificado"}`

## 📱 USO NO FLUTTER:

O Flutter vai chamar automaticamente:
- `POST http://localhost:3000/processar-certificado`
- Envia: arquivo PFX + senha
- Recebe: chave privada e certificado já processados

## 🔄 PRÓXIMOS PASSOS:

1. **Iniciar o servidor** (deixe rodando em segundo plano)
2. **Modificar o Flutter** para usar o serviço
3. **Testar** com seu certificado

## ⚠️ IMPORTANTE:

- O servidor deve estar rodando sempre que você usar o app
- Você pode adicionar ao startup do Windows para iniciar automaticamente
- O servidor processa localmente (não envia dados para internet)

## 🛠️ TROUBLESHOOTING:

**Erro: "Cannot find module 'express'"**
- Execute: `npm install`

**Erro: "Port 3000 already in use"**
- Altere a porta no arquivo `conversor_certificado_server.js` (linha final)

**Servidor não inicia**
- Verifique se Node.js está instalado: `node --version`
- Verifique se as dependências foram instaladas: `npm list`




