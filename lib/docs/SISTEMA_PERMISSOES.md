# Sistema de Permissões

Este documento descreve como usar o sistema de permissões implementado no sistema.

## Estrutura

O sistema de permissões é composto por:

1. **Modelo de Permissão** (`lib/models/permissao.dart`)
   - Define todas as permissões disponíveis no sistema
   - Organizadas por categoria (Vendas, Produtos, Clientes, etc.)

2. **Serviço de Permissões** (`lib/services/permission_service.dart`)
   - Gerencia e verifica permissões
   - Define permissões padrão por tipo de usuário
   - Permite verificar permissões de usuários

3. **Widgets de Permissão** (`lib/widgets/permission_widget.dart`)
   - Widgets para controlar exibição na UI baseado em permissões
   - Helpers para verificar permissões em código

4. **Modelo de Usuário Atualizado** (`lib/models/usuario.dart`)
   - Suporta permissões personalizadas
   - Suporta permissões negadas

## Tipos de Permissões

O sistema possui permissões organizadas por categoria:

### Vendas
- `vendas.visualizar` - Visualizar vendas
- `vendas.criar` - Criar vendas
- `vendas.editar` - Editar vendas
- `vendas.cancelar` - Cancelar vendas
- `vendas.excluir` - Excluir vendas
- `vendas.aplicar_desconto` - Aplicar descontos
- `vendas.ver_custo` - Ver custo de produtos

### Produtos
- `produtos.visualizar` - Visualizar produtos
- `produtos.criar` - Criar produtos
- `produtos.editar` - Editar produtos
- `produtos.excluir` - Excluir produtos
- `produtos.alterar_preco` - Alterar preços
- `produtos.gerenciar_estoque` - Gerenciar estoque

### Clientes
- `clientes.visualizar` - Visualizar clientes
- `clientes.criar` - Criar clientes
- `clientes.editar` - Editar clientes
- `clientes.excluir` - Excluir clientes
- `clientes.ver_historico` - Ver histórico

### Relatórios
- `relatorios.visualizar` - Visualizar relatórios
- `relatorios.vendas` - Relatórios de vendas
- `relatorios.financeiro` - Relatórios financeiros
- `relatorios.estoque` - Relatórios de estoque
- `relatorios.exportar` - Exportar relatórios

### Configurações
- `configuracoes.visualizar` - Visualizar configurações
- `configuracoes.empresa` - Configurar empresa
- `configuracoes.usuarios` - Gerenciar usuários
- `configuracoes.permissoes` - Gerenciar permissões
- `configuracoes.sistema` - Configurações do sistema

### NFC-e
- `nfce.emitir` - Emitir NFC-e
- `nfce.visualizar` - Visualizar NFC-e
- `nfce.cancelar` - Cancelar NFC-e
- `nfce.reenviar` - Reenviar NFC-e

### Caixa
- `caixa.abrir` - Abrir caixa
- `caixa.fechar` - Fechar caixa
- `caixa.visualizar` - Visualizar caixa
- `caixa.movimentar` - Movimentar caixa

### Cozinha/Bar
- `cozinha.visualizar` - Visualizar cozinha/bar
- `cozinha.preparar` - Preparar pedidos
- `cozinha.finalizar` - Finalizar pedidos
- `cozinha.cancelar` - Cancelar pedidos

### Financeiro
- `financeiro.visualizar` - Visualizar financeiro
- `financeiro.receber` - Receber valores
- `financeiro.pagar` - Pagar valores
- `financeiro.conciliar` - Conciliar contas

### Estoque
- `estoque.visualizar` - Visualizar estoque
- `estoque.entrada` - Entrada de estoque
- `estoque.saida` - Saída de estoque
- `estoque.ajuste` - Ajuste de estoque
- `estoque.transferencia` - Transferência de estoque

## Permissões Padrão por Tipo de Usuário

### Administrador
- **Todas as permissões** - Acesso total ao sistema

### Gerente
- Maioria das permissões, exceto:
  - Excluir vendas
  - Excluir produtos
  - Excluir clientes
  - Gerenciar usuários
  - Gerenciar permissões
  - Configurações do sistema

### Operador
- Permissões básicas:
  - Visualizar e criar vendas
  - Visualizar produtos
  - Visualizar e criar clientes
  - Emitir e visualizar NFC-e
  - Visualizar caixa
  - Visualizar e preparar pedidos na cozinha
  - Visualizar estoque

### Vendedor
- Permissões mínimas:
  - Visualizar e criar vendas
  - Visualizar produtos
  - Visualizar e criar clientes
  - Emitir e visualizar NFC-e
  - Visualizar cozinha/bar

## Como Usar

### 1. Verificar Permissões em Widgets

```dart
import 'package:seu_app/widgets/permission_widget.dart';
import 'package:seu_app/models/permissao.dart';

// Exibir widget apenas se tiver permissão
PermissionWidget(
  permissao: TipoPermissao.vendasCriar,
  child: ElevatedButton(
    onPressed: () => criarVenda(),
    child: Text('Nova Venda'),
  ),
  fallback: SizedBox.shrink(), // Opcional: widget exibido se não tiver permissão
)

// Verificar múltiplas permissões (qualquer uma)
PermissionAnyWidget(
  permissoes: [
    TipoPermissao.vendasCriar,
    TipoPermissao.vendasEditar,
  ],
  child: Text('Pode criar ou editar vendas'),
)

// Verificar múltiplas permissões (todas)
PermissionAllWidget(
  permissoes: [
    TipoPermissao.vendasCriar,
    TipoPermissao.nfceEmitir,
  ],
  child: Text('Pode criar vendas e emitir NFC-e'),
)
```

### 2. Verificar Permissões em Código

```dart
import 'package:seu_app/widgets/permission_widget.dart';
import 'package:seu_app/models/permissao.dart';
import 'package:seu_app/services/auth_service.dart';
import 'package:provider/provider.dart';

// Em um método
void criarVenda() {
  final authService = Provider.of<AuthService>(context, listen: false);
  final usuario = authService.usuarioAtual;
  
  if (!PermissionHelper.temPermissao(usuario, TipoPermissao.vendasCriar)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Você não tem permissão para criar vendas')),
    );
    return;
  }
  
  // Continuar com a criação da venda
}

// Verificar por código
if (PermissionHelper.temPermissaoPorCodigo(usuario, 'vendas.criar')) {
  // Fazer algo
}

// Verificar múltiplas permissões
if (PermissionHelper.temAlgumaPermissao(usuario, [
  TipoPermissao.vendasCriar,
  TipoPermissao.vendasEditar,
])) {
  // Usuário pode criar OU editar
}

if (PermissionHelper.temTodasPermissoes(usuario, [
  TipoPermissao.vendasCriar,
  TipoPermissao.nfceEmitir,
])) {
  // Usuário pode criar E emitir NFC-e
}
```

### 3. Usar o Serviço de Permissões Diretamente

```dart
import 'package:seu_app/services/permission_service.dart';
import 'package:seu_app/models/permissao.dart';

final permissionService = PermissionService();
final usuario = authService.usuarioAtual;

// Verificar permissão
if (permissionService.temPermissao(usuario, TipoPermissao.vendasCriar)) {
  // Usuário tem permissão
}

// Obter todas as permissões do usuário
final permissoes = permissionService.obterPermissoes(usuario);

// Obter permissões por categoria
final permissoesPorCategoria = permissionService.obterPermissoesPorCategoria();
```

### 4. Ocultar Botões/Ações na UI

```dart
// Exemplo: Ocultar botão de excluir se não tiver permissão
PermissionWidget(
  permissao: TipoPermissao.vendasExcluir,
  child: IconButton(
    icon: Icon(Icons.delete),
    onPressed: () => excluirVenda(),
  ),
)

// Exemplo: Desabilitar botão ao invés de ocultar
ElevatedButton(
  onPressed: PermissionHelper.temPermissao(
    authService.usuarioAtual,
    TipoPermissao.vendasCriar,
  ) ? criarVenda : null,
  child: Text('Nova Venda'),
)
```

### 5. Controlar Navegação

```dart
// Exemplo: Ocultar item do menu
PermissionWidget(
  permissao: TipoPermissao.relatoriosVisualizar,
  child: ListTile(
    leading: Icon(Icons.bar_chart),
    title: Text('Relatórios'),
    onTap: () => Navigator.push(...),
  ),
)
```

## Permissões Personalizadas

Os usuários podem ter permissões personalizadas além das permissões padrão do seu tipo:

```dart
// Adicionar permissão personalizada a um usuário
final usuario = Usuario(
  // ... outros campos
  permissoesPersonalizadas: {
    TipoPermissao.vendasVerCusto.codigo,
    TipoPermissao.relatoriosExportar.codigo,
  },
);

// Remover permissão padrão de um usuário
final usuario = Usuario(
  // ... outros campos
  permissoesNegadas: {
    TipoPermissao.vendasExcluir.codigo,
  },
);
```

## Boas Práticas

1. **Sempre verifique permissões no backend também** - As verificações na UI são apenas para UX
2. **Use permissões específicas** - Evite dar permissões muito amplas
3. **Documente permissões customizadas** - Mantenha registro de permissões personalizadas
4. **Teste diferentes tipos de usuário** - Garanta que as permissões funcionam corretamente
5. **Use fallback widgets** - Forneça feedback visual quando o usuário não tem permissão

## Exemplos Completos

### Exemplo 1: Botão de Nova Venda

```dart
PermissionWidget(
  permissao: TipoPermissao.vendasCriar,
  child: FloatingActionButton(
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NovaVendaPage()),
    ),
    child: Icon(Icons.add),
  ),
  fallback: SizedBox.shrink(),
)
```

### Exemplo 2: Menu com Verificação de Permissões

```dart
List<Widget> buildMenuItems() {
  final items = <Widget>[];
  
  if (PermissionHelper.temPermissao(
    authService.usuarioAtual,
    TipoPermissao.vendasVisualizar,
  )) {
    items.add(ListTile(
      leading: Icon(Icons.shopping_cart),
      title: Text('Vendas'),
      onTap: () => Navigator.push(...),
    ));
  }
  
  if (PermissionHelper.temPermissao(
    authService.usuarioAtual,
    TipoPermissao.produtosVisualizar,
  )) {
    items.add(ListTile(
      leading: Icon(Icons.inventory),
      title: Text('Produtos'),
      onTap: () => Navigator.push(...),
    ));
  }
  
  return items;
}
```

### Exemplo 3: Ação com Verificação

```dart
void onDeletePressed() {
  final usuario = authService.usuarioAtual;
  
  if (!PermissionHelper.temPermissao(usuario, TipoPermissao.vendasExcluir)) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permissão Negada'),
        content: Text('Você não tem permissão para excluir vendas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  
  // Continuar com exclusão
  _excluirVenda();
}
```





