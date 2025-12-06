# Estrutura do Firebase Firestore - Sistema Êxodo

## 📋 Visão Geral

Este documento descreve toda a estrutura de dados do Firebase Firestore para o Sistema Êxodo.

## 🗂️ Coleções

### 1. **clientes**
Armazena informações dos clientes.

**Campos:**
- `id` (string): ID único do cliente
- `nome` (string): Nome completo
- `tipoPessoa` (string): "fisica" ou "juridica"
- `cpfCnpj` (string): CPF ou CNPJ
- `email` (string): Email
- `telefone` (string): Telefone
- `whatsapp` (string): WhatsApp
- `endereco` (string): Endereço
- `numero` (string): Número
- `bairro` (string): Bairro
- `cidade` (string): Cidade
- `estado` (string): Estado
- `cep` (string): CEP
- `limiteCredito` (number): Limite de crédito
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 2. **produtos**
Armazena informações dos produtos.

**Campos:**
- `id` (string): ID único
- `nome` (string): Nome do produto
- `descricao` (string): Descrição
- `preco` (number): Preço
- `custo` (number): Custo
- `estoque` (number): Quantidade em estoque
- `estoqueMinimo` (number): Estoque mínimo
- `unidade` (string): Unidade de medida
- `categoria` (string): Categoria
- `codigoBarras` (string): Código de barras
- `ativo` (boolean): Se está ativo
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 3. **servicos**
Armazena tipos de serviços oferecidos.

**Campos:**
- `id` (string): ID único
- `nome` (string): Nome do serviço
- `descricao` (string): Descrição
- `preco` (number): Preço
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 4. **pedidos**
Armazena pedidos de clientes.

**Campos:**
- `id` (string): ID único
- `numero` (string): Número do pedido (ex: PED-001)
- `clienteId` (string): ID do cliente
- `clienteNome` (string): Nome do cliente
- `dataCriacao` (timestamp): Data de criação
- `dataEntrega` (timestamp): Data de entrega prevista
- `status` (string): Status do pedido
- `itens` (array): Lista de itens do pedido
- `servicos` (array): Lista de serviços do pedido
- `subtotal` (number): Subtotal
- `desconto` (number): Desconto
- `total` (number): Total
- `totalRecebido` (number): Total recebido
- `observacoes` (string): Observações
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 5. **ordens_servico**
Armazena ordens de serviço.

**Campos:**
- `id` (string): ID único
- `numero` (string): Número da ordem
- `clienteId` (string): ID do cliente
- `clienteNome` (string): Nome do cliente
- `servicoId` (string): ID do serviço
- `servicoNome` (string): Nome do serviço
- `descricao` (string): Descrição
- `dataInicio` (timestamp): Data de início
- `dataFim` (timestamp): Data de fim
- `status` (string): Status
- `valor` (number): Valor
- `observacoes` (string): Observações
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 6. **entregas**
Armazena informações de entregas.

**Campos:**
- `id` (string): ID único
- `pedidoId` (string): ID do pedido
- `pedidoNumero` (string): Número do pedido
- `clienteNome` (string): Nome do cliente
- `enderecoEntrega` (string): Endereço
- `status` (string): Status da entrega
- `dataCriacao` (timestamp): Data de criação
- `dataPrevisao` (timestamp): Data prevista
- `dataEntrega` (timestamp): Data de entrega
- `motoristaId` (string): ID do motorista
- `motoristaNome` (string): Nome do motorista
- `veiculoPlaca` (string): Placa do veículo
- `taxaEntrega` (number): Taxa de entrega
- `observacoes` (string): Observações
- `historico` (array): Histórico de eventos
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 7. **vendas_balcao**
Armazena vendas realizadas no balcão (PDV).

**Campos:**
- `id` (string): ID único
- `numero` (string): Número da venda (ex: VND-001)
- `dataVenda` (timestamp): Data da venda
- `itens` (array): Lista de itens vendidos
- `subtotal` (number): Subtotal
- `desconto` (number): Desconto
- `total` (number): Total
- `formaPagamento` (string): Forma de pagamento
- `clienteId` (string): ID do cliente (opcional)
- `vendedor` (string): Nome do vendedor
- `observacoes` (string): Observações
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 8. **trocas_devolucoes**
Armazena trocas e devoluções.

**Campos:**
- `id` (string): ID único
- `tipo` (string): "troca" ou "devolucao"
- `vendaId` (string): ID da venda original
- `vendaNumero` (string): Número da venda
- `dataOperacao` (timestamp): Data da operação
- `itens` (array): Itens trocados/devolvidos
- `valorDevolvido` (number): Valor devolvido
- `motivo` (string): Motivo
- `observacoes` (string): Observações
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 9. **estoque_historico**
Armazena histórico de movimentações de estoque.

**Campos:**
- `id` (string): ID único
- `produtoId` (string): ID do produto
- `data` (timestamp): Data da movimentação
- `quantidade` (number): Quantidade
- `tipo` (string): "entrada", "saida", "ajuste"
- `usuario` (string): Usuário responsável
- `observacao` (string): Observação
- `createdAt` (timestamp): Data de criação

---

### 10. **aberturas_caixa**
Armazena aberturas de caixa.

**Campos:**
- `id` (string): ID único
- `numero` (string): Número do caixa (ex: CAIXA-001)
- `dataAbertura` (timestamp): Data de abertura
- `valorInicial` (number): Valor inicial em dinheiro
- `observacao` (string): Observação
- `responsavel` (string): Responsável pela abertura
- `createdAt` (timestamp): Data de criação

---

### 11. **fechamentos_caixa**
Armazena fechamentos de caixa.

**Campos:**
- `id` (string): ID único
- `aberturaCaixaId` (string): ID da abertura relacionada
- `dataFechamento` (timestamp): Data de fechamento
- `valorEsperado` (number): Valor esperado
- `valorReal` (number): Valor real encontrado
- `diferenca` (number): Diferença (real - esperado)
- `sangrias` (array): Lista de sangrias
- `observacao` (string): Observação
- `responsavel` (string): Responsável pelo fechamento
- `createdAt` (timestamp): Data de criação

---

### 12. **motoristas**
Armazena informações de motoristas/entregadores.

**Campos:**
- `id` (string): ID único
- `nome` (string): Nome completo
- `telefone` (string): Telefone
- `cpf` (string): CPF
- `cnh` (string): CNH
- `veiculoModelo` (string): Modelo do veículo
- `veiculoPlaca` (string): Placa do veículo
- `ativo` (boolean): Se está ativo
- `dataCadastro` (timestamp): Data de cadastro
- `createdAt` (timestamp): Data de criação
- `updatedAt` (timestamp): Data de atualização

---

### 13. **config**
Armazena configurações gerais do sistema.

**Documento: `sistema`**
- `versao` (string): Versão do sistema
- `dataInicializacao` (timestamp): Data de inicialização
- `ultimaSincronizacao` (timestamp): Última sincronização
- `estruturaCriada` (boolean): Se a estrutura foi criada
- `colecoes` (array): Lista de coleções

---

## 🔍 Índices Compostos

Os seguintes índices compostos são recomendados para melhor performance:

1. **pedidos**: `dataCriacao` (DESC) + `status` (ASC)
2. **vendas_balcao**: `dataVenda` (DESC) + `valorTotal` (DESC)
3. **entregas**: `status` (ASC) + `dataCriacao` (DESC)
4. **aberturas_caixa**: `dataAbertura` (DESC)
5. **fechamentos_caixa**: `dataFechamento` (DESC)

---

## 🔐 Regras de Segurança

As regras de segurança estão definidas em `firestore.rules`.

**ATENÇÃO**: As regras atuais permitem leitura e escrita para todos (modo desenvolvimento). Em produção, implemente autenticação adequada!

---

## 📝 Como Usar

### Inicializar Estrutura

```dart
import 'package:sistema_exodo_novo/services/firebase_init_service.dart';

// No main.dart ou onde necessário
await FirebaseInitService.inicializarEstrutura();
```

### Verificar Informações

```dart
final info = await FirebaseInitService.obterInfoEstrutura();
print('Versão: ${info?['versao']}');
```

### Atualizar Sincronização

```dart
await FirebaseInitService.atualizarUltimaSincronizacao();
```

---

## 🚀 Deploy

### 1. Deploy das Regras de Segurança

```bash
firebase deploy --only firestore:rules
```

### 2. Deploy dos Índices

```bash
firebase deploy --only firestore:indexes
```

---

## 📊 Estatísticas

- **Total de Coleções**: 13
- **Documentos Esperados**: Variável (cresce com o uso)
- **Índices Compostos**: 5

---

## 🔄 Sincronização

Todas as operações CRUD são automaticamente sincronizadas com o Firebase:
- ✅ Criar → Salva no Firebase
- ✅ Atualizar → Atualiza no Firebase
- ✅ Deletar → Remove do Firebase
- ✅ Ler → Carrega do Firebase (com fallback para localStorage)

---

## 📞 Suporte

Para dúvidas ou problemas, consulte a documentação do Firebase Firestore:
https://firebase.google.com/docs/firestore





