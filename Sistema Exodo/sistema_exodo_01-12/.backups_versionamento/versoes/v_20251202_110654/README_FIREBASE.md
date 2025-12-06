# 🚀 Guia de Configuração do Firebase - Sistema Êxodo

## 📋 Pré-requisitos

1. **Node.js** instalado (para Firebase CLI)
2. **Firebase CLI** instalado:
   ```bash
   npm install -g firebase-tools
   ```

## 🔧 Configuração Inicial

### 1. Login no Firebase

```bash
firebase login
```

### 2. Verificar Projeto

O projeto está configurado para usar: **exodo-system**

Para alterar, edite o arquivo `.firebaserc`:

```json
{
  "projects": {
    "default": "seu-projeto-id"
  }
}
```

### 3. Inicializar Estrutura

A estrutura é inicializada automaticamente quando o app inicia, mas você pode verificar manualmente:

```dart
await FirebaseInitService.inicializarEstrutura();
```

## 📤 Deploy da Estrutura

### Opção 1: Script PowerShell (Recomendado)

```powershell
.\deploy_firebase.ps1
```

O script oferece um menu interativo:
- Deploy apenas das Regras
- Deploy apenas dos Índices
- Deploy Completo
- Verificar estrutura

### Opção 2: Comandos Manuais

#### Deploy das Regras de Segurança

```bash
firebase deploy --only firestore:rules
```

#### Deploy dos Índices

```bash
firebase deploy --only firestore:indexes
```

#### Deploy Completo

```bash
firebase deploy --only firestore
```

## 📁 Estrutura de Arquivos

```
sistema_exodo_01-12/
├── firebase.json              # Configuração do Firebase
├── .firebaserc                # ID do projeto Firebase
├── firestore.rules            # Regras de segurança
├── firestore.indexes.json     # Índices compostos
├── deploy_firebase.ps1        # Script de deploy
├── ESTRUTURA_FIREBASE.md      # Documentação completa
└── lib/
    └── services/
        └── firebase_init_service.dart  # Serviço de inicialização
```

## 🗂️ Coleções Criadas

A estrutura inclui 13 coleções:

1. **clientes** - Dados dos clientes
2. **produtos** - Catálogo de produtos
3. **servicos** - Tipos de serviços
4. **pedidos** - Pedidos de clientes
5. **ordens_servico** - Ordens de serviço
6. **entregas** - Controle de entregas
7. **vendas_balcao** - Vendas do PDV
8. **trocas_devolucoes** - Trocas e devoluções
9. **estoque_historico** - Histórico de estoque
10. **aberturas_caixa** - Aberturas de caixa
11. **fechamentos_caixa** - Fechamentos de caixa
12. **motoristas** - Motoristas/entregadores
13. **config** - Configurações do sistema

## 🔐 Regras de Segurança

**⚠️ ATENÇÃO**: As regras atuais permitem leitura e escrita para todos (modo desenvolvimento).

Para produção, edite `firestore.rules` e implemente autenticação:

```javascript
match /{document=**} {
  allow read, write: if request.auth != null;
}
```

## 🔍 Índices Compostos

Os seguintes índices são criados automaticamente:

- `pedidos`: dataCriacao (DESC) + status (ASC)
- `vendas_balcao`: dataVenda (DESC) + valorTotal (DESC)
- `entregas`: status (ASC) + dataCriacao (DESC)
- `aberturas_caixa`: dataAbertura (DESC)
- `fechamentos_caixa`: dataFechamento (DESC)

## ✅ Verificação

Após o deploy, verifique no Console do Firebase:

1. Acesse: https://console.firebase.google.com
2. Selecione o projeto **exodo-system**
3. Vá em **Firestore Database**
4. Verifique se as coleções aparecem (serão criadas quando houver dados)

## 🐛 Troubleshooting

### Erro: "Firebase CLI not found"
```bash
npm install -g firebase-tools
```

### Erro: "Not logged in"
```bash
firebase login
```

### Erro: "Project not found"
Verifique o arquivo `.firebaserc` e certifique-se de que o projeto existe no Firebase Console.

### Índices não aparecem
Os índices podem levar alguns minutos para serem criados. Verifique em:
**Firestore > Índices** no Console do Firebase.

## 📞 Suporte

Para mais informações, consulte:
- [Documentação Firebase Firestore](https://firebase.google.com/docs/firestore)
- [Documentação Firebase CLI](https://firebase.google.com/docs/cli)

---

**Última atualização**: Estrutura criada automaticamente na inicialização do app.

