# 🚚 Guia Completo: Sistema Híbrido de Frete e Entrega

## 📋 Visão Geral

O sistema implementa um **cálculo híbrido de frete** com múltiplas opções, priorizando:

1. **Taxa por Bairro** (mais barata e rápida para entregas locais)
2. **Correios PAC** (econômico)
3. **Correios PAC Mini** (econômico para produtos pequenos)
4. **Correios SEDEX** (rápido)
5. **Correios SEDEX 10** (expresso até 10h - requer credenciais)
6. **Correios SEDEX 12** (expresso até 12h - requer credenciais)
7. **Jadlog** (transportadora nacional)
8. **Total Express** (transportadora nacional)
9. **Azul Cargo** (transportadora aérea)
10. **Loggi Express** (entregas rápidas urbanas - até 50km)
11. **Entrega Rápida** (iFood/Rappi - mesmo dia, até 15km)
12. **Cálculo por Distância** (baseado em coordenadas)
13. **Cálculo Manual** (fallback por região)

## 🎯 Funcionalidades

### ✅ Sistema Híbrido Implementado
- ✅ Integração com API dos Correios (PAC, PAC Mini, SEDEX, SEDEX 10, SEDEX 12)
- ✅ Sistema de taxas por bairro
- ✅ Integração com transportadoras modernas (Jadlog, Total Express, Azul Cargo)
- ✅ Entregas rápidas urbanas (Loggi Express)
- ✅ Entregas no mesmo dia (iFood/Rappi - para produtos leves)
- ✅ Cálculo por distância usando BrasilAPI
- ✅ Múltiplas opções de frete no checkout
- ✅ Seleção de opção de frete pelo cliente
- ✅ Fallback automático quando uma opção falha
- ✅ Ordenação automática por preço (mais barato primeiro)

## 🔧 Configuração

### 1. Configurar Credenciais dos Correios (Opcional)

Para usar a API oficial dos Correios, você precisa de:
- **Código da Empresa** (obtido ao contratar serviços dos Correios)
- **Senha** (fornecida pelos Correios)

```dart
// No início da aplicação (ex: main.dart ou initState)
FreteService.configurarCorreios(
  codigoEmpresa: 'SEU_CODIGO_AQUI',
  senha: 'SUA_SENHA_AQUI',
);
```

**Nota:** Se não configurar credenciais, o sistema usará cálculo estimado baseado em distância.

### 2. Cadastrar Taxas por Bairro

1. Acesse **Entregas > Taxas de Entrega**
2. Clique em **Adicionar Taxa**
3. Preencha:
   - **Bairro**: Nome do bairro
   - **Cidade**: (Opcional) Nome da cidade
   - **Valor**: Taxa fixa de entrega
   - **Ativo**: Marque como ativo

**Prioridade:** O sistema sempre verifica primeiro se há taxa cadastrada para o bairro do cliente.

## 📊 Como Funciona

### Prioridade de Cálculo

```
1. Taxa por Bairro
   ↓ (se não encontrar)
2. Correios (PAC, PAC Mini, SEDEX, SEDEX 10, SEDEX 12)
   ↓ (em paralelo)
3. Transportadoras (Jadlog, Total Express, Azul Cargo)
   ↓ (em paralelo)
4. Entregas Rápidas (Loggi, iFood/Rappi - se aplicável)
   ↓ (se falhar)
5. Cálculo por Distância (BrasilAPI)
   ↓ (se falhar)
6. Cálculo Manual (por região) - SEMPRE disponível como fallback
```

### Fluxo no Checkout

1. Cliente preenche **CEP** e **Bairro**
2. Sistema busca automaticamente todas as opções disponíveis
3. Cliente vê todas as opções ordenadas por preço
4. Cliente seleciona a opção desejada
5. Valor e prazo são atualizados automaticamente

## 🎨 Interface no Checkout

O checkout agora exibe:
- ✅ Lista de opções de frete disponíveis
- ✅ Seleção visual (radio button)
- ✅ Informações de cada opção:
  - Nome (Entrega Local, PAC, SEDEX, etc.)
  - Descrição
  - Prazo de entrega
  - Valor
- ✅ Opção mais barata selecionada automaticamente
- ✅ Atualização automática do total

## 🔌 APIs Utilizadas

### 1. ViaCEP
- **Uso**: Buscar endereço por CEP
- **Gratuita**: Sim
- **URL**: `https://viacep.com.br/ws/{cep}/json/`

### 2. BrasilAPI
- **Uso**: Obter coordenadas (lat/lon) por CEP
- **Gratuita**: Sim
- **URL**: `https://brasilapi.com.br/api/cep/v1/{cep}`

### 3. Correios (Oficial)
- **Uso**: Calcular frete PAC e SEDEX
- **Gratuita**: Não (requer contrato)
- **URL**: `https://ws.correios.com.br/calculador/CalcPrecoPrazo.asmx`
- **Método**: SOAP

### 4. Correios (Estimado)
- **Uso**: Cálculo estimado quando não há credenciais
- **Baseado em**: Distância, peso e tabelas de preços dos Correios

## 📝 Exemplo de Uso

### No Código

```dart
// Calcular todas as opções de frete
final opcoes = await FreteService.calcularOpcoesFrete(
  estadoOrigem: 'PR',
  estadoDestino: 'SP',
  pesoTotal: 1000, // em gramas
  valorPedido: 150.0,
  cepOrigem: '80000000',
  cepDestino: '01000000',
  bairroDestino: 'Centro',
  cidadeDestino: 'São Paulo',
  taxasEntrega: dataService.taxasEntrega,
);

// opcoes contém lista de OpcaoFrete ordenada por preço
// Primeira opção é geralmente a mais barata
```

## 🎯 Tipos de Frete

| Tipo | Descrição | Quando Usado |
|------|-----------|--------------|
| `taxa_bairro` | Taxa fixa por bairro | Quando há taxa cadastrada para o bairro |
| `correios_pac` | PAC dos Correios | Entrega econômica |
| `correios_pac_mini` | PAC Mini dos Correios | Entrega econômica para produtos pequenos |
| `correios_sedex` | SEDEX dos Correios | Entrega rápida |
| `correios_sedex_10` | SEDEX 10 dos Correios | Entrega expressa até 10h (requer credenciais) |
| `correios_sedex_12` | SEDEX 12 dos Correios | Entrega expressa até 12h (requer credenciais) |
| `jadlog` | Jadlog | Transportadora nacional |
| `total_express` | Total Express | Transportadora nacional |
| `azul_cargo` | Azul Cargo | Transportadora aérea |
| `loggi` | Loggi Express | Entregas rápidas urbanas (até 50km) |
| `entrega_rapida` | Entrega Rápida | iFood/Rappi (mesmo dia, até 15km, até 5kg) |
| `distancia` | Cálculo por distância | Quando APIs dos Correios falham |
| `manual` | Cálculo por região | Fallback final (sempre disponível) |

## ⚙️ Configurações Avançadas

### Frete Grátis
O sistema oferece frete grátis automaticamente para pedidos acima de **R$ 399,90**.

Para alterar:
```dart
// Em frete_service.dart, linha ~225
if (valorPedido >= 399.90) { // Altere este valor
  return 0.0;
}
```

### Limites de Frete
- **PAC Estimado**: Máximo R$ 120,00
- **SEDEX Estimado**: Máximo R$ 200,00
- **Distância**: Máximo R$ 150,00
- **Manual**: Máximo R$ 80,00

## 🐛 Troubleshooting

### Problema: Nenhuma opção de frete aparece
**Solução**: Verifique se:
- CEP de origem e destino estão preenchidos
- Estado está preenchido
- Há conexão com internet (para APIs)

### Problema: Correios não funciona
**Solução**: 
- Verifique credenciais (se usando API oficial)
- O sistema automaticamente usa cálculo estimado como fallback

### Problema: Taxa por bairro não aparece
**Solução**:
- Verifique se a taxa está cadastrada e ativa
- Verifique se o nome do bairro está exatamente igual (case-insensitive)
- Verifique se a cidade corresponde (se especificada)

## 🚀 Transportadoras Disponíveis

### Correios
- **PAC**: Entrega econômica (3-15 dias úteis)
- **PAC Mini**: Entrega econômica para produtos pequenos
- **SEDEX**: Entrega rápida (1-6 dias úteis)
- **SEDEX 10**: Entrega expressa até 10h (requer credenciais)
- **SEDEX 12**: Entrega expressa até 12h (requer credenciais)

### Transportadoras Nacionais
- **Jadlog**: Transportadora nacional (preços similares ao SEDEX)
- **Total Express**: Transportadora nacional (preços entre PAC e SEDEX)
- **Azul Cargo**: Transportadora aérea (rápida e competitiva)

### Entregas Rápidas Urbanas
- **Loggi Express**: Entregas rápidas urbanas (até 50km, 1-2 dias úteis)
- **Entrega Rápida**: iFood/Rappi (mesmo dia, até 15km, até 5kg)

### Características das Entregas Rápidas

**Loggi Express:**
- Distância máxima: 50km
- Peso máximo: 10kg
- Prazo: 1-2 dias úteis
- Ideal para: Entregas urbanas rápidas

**Entrega Rápida (iFood/Rappi):**
- Distância máxima: 15km
- Peso máximo: 5kg
- Prazo: Mesmo dia (até 2 horas)
- Ideal para: Produtos leves e urgentes

## 📈 Melhorias Futuras

- [x] Integração com outras transportadoras (Jadlog, Total Express, Azul Cargo, Loggi)
- [x] Entregas rápidas (iFood/Rappi)
- [ ] Integração com API oficial das transportadoras (quando disponível)
- [ ] Cálculo de frete por peso e dimensões mais preciso
- [ ] Histórico de entregas
- [ ] Rastreamento de pedidos em tempo real
- [ ] Notificações de status de entrega

## 📞 Suporte

Para dúvidas ou problemas, verifique:
1. Logs do console (debugPrint)
2. Mensagens de erro no checkout
3. Configuração das taxas por bairro

---

**Desenvolvido para Sistema Exodo** 🚀





