# 📦 Dados de E-commerce - Localização e Acesso

## 📍 Onde os Dados Estão Armazenados

### 1. **Em Memória (DataService)**
Os dados ficam em memória durante a execução do app:

```dart
// Acessar via Provider
final dataService = Provider.of<DataService>(context, listen: false);

// Links de vendedores
List<LinkVendedor> links = dataService.linksVendedores;

// Comissões de vendedores
List<ComissaoVendedor> comissoes = dataService.comissoesVendedores;
```

### 2. **Armazenamento Local (LocalStorage)**
Os dados são salvos automaticamente no localStorage (Web) ou shared_preferences (Mobile):

- **Chave Links**: `exodo_links_vendedores_[empresaId]`
- **Chave Comissões**: `exodo_comissoes_vendedores_[empresaId]`

**Localização física:**
- **Web**: `localStorage` do navegador
- **Mobile**: `shared_preferences` do dispositivo

### 3. **Firebase Firestore (se habilitado)**
Os dados são sincronizados automaticamente com o Firebase:

- **Coleção Links**: `empresas/{empresaId}/linksVendedores`
- **Coleção Comissões**: `empresas/{empresaId}/comissoesVendedores`

## 🔍 Como Acessar os Dados

### **Via Interface do Sistema:**

1. **Gerenciar Links**: Menu Principal → "Links Vendedores"
   - Criar novos links
   - Editar links existentes
   - Copiar/compartilhar links
   - Ver estatísticas

2. **Dashboard de Vendedores**: Menu Principal → "Dashboard Vendedores"
   - Ver todas as comissões
   - Filtrar por status e período
   - Ver estatísticas por vendedor
   - Marcar comissões como pagas

3. **Loja Pública**: Acesse via URL com parâmetro `link`
   - Exemplo: `https://seusite.com/?link=ABC123`
   - Funciona sem autenticação
   - Carrega produtos e serviços automaticamente

### **Via Código:**

```dart
// 1. Obter DataService
final dataService = Provider.of<DataService>(context, listen: false);

// 2. Acessar links
final links = dataService.linksVendedores;
final linkAtivo = links.firstWhere((l) => l.codigoLink == 'ABC123' && l.ativo);

// 3. Acessar comissões
final comissoes = dataService.comissoesVendedores;
final comissoesPendentes = comissoes.where((c) => c.status == 'Pendente').toList();

// 4. Criar novo link
final novoLink = LinkVendedor(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  funcionarioId: funcionario.id,
  funcionarioNome: funcionario.nome,
  codigoLink: 'ABC123',
  urlCompleta: 'https://seusite.com/?link=ABC123',
  percentualComissao: 10.0,
  ativo: true,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);
await dataService.addLinkVendedor(novoLink);

// 5. Criar comissão
final comissao = ComissaoVendedor(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  linkVendedorId: link.id,
  funcionarioId: link.funcionarioId,
  funcionarioNome: link.funcionarioNome,
  pedidoId: pedido.id,
  pedidoNumero: pedido.numero,
  valorPedido: pedido.totalGeral,
  percentualComissao: link.percentualComissao,
  valorComissao: pedido.totalGeral * (link.percentualComissao / 100),
  status: 'Pendente',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);
await dataService.addComissaoVendedor(comissao);
```

## 📊 Estrutura dos Dados

### **LinkVendedor**
```dart
{
  id: String,
  funcionarioId: String,
  funcionarioNome: String,
  codigoLink: String,        // Ex: "ABC123"
  urlCompleta: String,       // URL completa do link
  percentualComissao: double, // Ex: 10.0 = 10%
  ativo: bool,
  totalVendas: int,
  totalComissao: double,
  createdAt: DateTime,
  updatedAt: DateTime,
}
```

### **ComissaoVendedor**
```dart
{
  id: String,
  linkVendedorId: String,
  funcionarioId: String,
  funcionarioNome: String,
  pedidoId: String,
  pedidoNumero: String,      // Ex: "PED-0001"
  valorPedido: double,
  percentualComissao: double,
  valorComissao: double,
  status: String,            // "Pendente", "Paga", "Cancelada"
  dataPagamento: DateTime?,
  createdAt: DateTime,
  updatedAt: DateTime,
}
```

## 🔗 Como Criar Links Reais

### **Método 1: Via Interface**
1. Acesse: Menu Principal → "Links Vendedores"
2. Clique no botão "+" (criar novo link)
3. Selecione o vendedor
4. O código será gerado automaticamente
5. Clique em "Criar"
6. Copie o link gerado

### **Método 2: Via Código**
```dart
// Gerar código único
String gerarCodigoLink() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = DateTime.now().millisecondsSinceEpoch;
  String codigo = '';
  for (int i = 0; i < 6; i++) {
    codigo += chars[(random + i) % chars.length];
  }
  return codigo;
}

// Criar link
final codigo = gerarCodigoLink();
final urlBase = kIsWeb ? html.window.location.origin : 'https://seusite.com';
final urlCompleta = '$urlBase/?link=$codigo';

final link = LinkVendedor(
  id: DateTime.now().millisecondsSinceEpoch.toString(),
  funcionarioId: funcionario.id,
  funcionarioNome: funcionario.nome,
  codigoLink: codigo,
  urlCompleta: urlCompleta,
  percentualComissao: 10.0,
  ativo: true,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

await dataService.addLinkVendedor(link);
```

## 📱 URLs de Acesso

### **Loja Pública**
- Formato: `https://seusite.com/?link=CODIGO`
- Exemplo: `https://seusite.com/?link=ABC123`
- Funciona sem autenticação
- Carrega produtos e serviços automaticamente

### **Dashboard de Vendedor**
- Acesso: Menu Principal → "Dashboard Vendedores"
- Requer autenticação
- Mostra todas as comissões ou filtradas por vendedor

### **Gerenciar Links**
- Acesso: Menu Principal → "Links Vendedores"
- Requer autenticação
- Permite criar, editar e excluir links

## 🔄 Sincronização Automática

Os dados são sincronizados automaticamente:
- ✅ **Salvamento Local**: Imediato após cada alteração
- ✅ **Sincronização Firebase**: Em background (se habilitado)
- ✅ **Carregamento**: Automático ao iniciar o app ou trocar de empresa

## 📝 Notas Importantes

1. **Isolamento por Empresa**: Cada empresa tem seus próprios links e comissões
2. **Código Único**: Cada link tem um código único que não pode ser duplicado
3. **Comissão Automática**: Ao finalizar um pedido via link, a comissão é criada automaticamente
4. **Atualização de Estatísticas**: As estatísticas do link são atualizadas automaticamente a cada venda














