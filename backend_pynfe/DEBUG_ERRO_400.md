# 🔍 Debug - Erro 400 Bad Request

## Problema

A API está retornando HTTP 400 ao tentar emitir NFC-e.

## Possíveis Causas

### 1. Dados não fornecidos

**Erro:** `"Dados não fornecidos"`

**Solução:** Verifique se está enviando JSON no body da requisição.

### 2. Campos obrigatórios faltando

**Erros possíveis:**
- `Campo "empresa" é obrigatório`
- `Campo "empresa.cnpj" é obrigatório`
- `Campo "empresa.certificado_base64" é obrigatório`
- `Campo "produtos" é obrigatório e não pode estar vazio`
- `Campo "pagamentos" é obrigatório e não pode estar vazio`

**Solução:** Verifique se todos os campos obrigatórios estão presentes.

### 3. Formato JSON incorreto

**Solução:** Verifique se o JSON está bem formado.

## Estrutura Esperada

```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "razao_social": "Empresa Teste",
    "nome_fantasia": "Empresa",
    "uf": "SP",
    "inscricao_estadual": "123456789012",
    "codigo_municipio_ibge": "3550308",
    "endereco": "Rua Exemplo",
    "numero": "123",
    "bairro": "Centro",
    "cidade": "São Paulo",
    "cep": "01000000",
    "telefone": "11999999999",
    "serie_nfce": "1",
    "certificado_base64": "BASE64_DO_CERTIFICADO",
    "senhaCertificado": "senha123",
    "ambienteHomologacao": true
  },
  "produtos": [
    {
      "codigo": "001",
      "descricao": "Produto 1",
      "ncm": "21069090",
      "cfop": "5102",
      "unidade": "UN",
      "quantidade": 1.0,
      "valor_unitario": 10.00,
      "valor_total": 10.00,
      "codigo_barras": "7891234567890",
      "icms": {
        "origem": "0",
        "cst": "102",
        "aliquota": 18.0
      }
    }
  ],
  "pagamentos": [
    {
      "tipo": "01",
      "valor": 10.00
    }
  ],
  "consumidor": {
    "cpf": "12345678901",
    "nome": "Consumidor Final"
  },
  "observacoes": "",
  "numero_nfce": 1
}
```

## Como Debugar

### 1. Verificar logs do servidor

O servidor agora retorna informações detalhadas sobre o que está faltando:

```json
{
  "success": false,
  "error": "Erros de validação",
  "error_type": "ValidationError",
  "erros": [
    "Campo 'empresa.cnpj' é obrigatório",
    "Campo 'produtos' é obrigatório e não pode estar vazio"
  ],
  "dados_recebidos": {
    "tem_empresa": true,
    "tem_produtos": false,
    "tem_pagamentos": true
  }
}
```

### 2. Testar com curl

```bash
curl -X POST http://localhost:5000/api/nfce/emitir \
  -H "Content-Type: application/json" \
  -d @exemplo_nfce.json
```

### 3. Verificar resposta da API

A resposta agora inclui:
- Lista de erros específicos
- Quais campos foram recebidos
- Tipo de erro

## Solução Rápida

1. **Verifique se está enviando JSON:**
   ```python
   headers = {'Content-Type': 'application/json'}
   ```

2. **Verifique campos obrigatórios:**
   - `empresa.cnpj`
   - `empresa.certificado_base64`
   - `empresa.senhaCertificado`
   - `produtos` (não vazio)
   - `pagamentos` (não vazio)

3. **Teste com dados mínimos:**
   Use o exemplo acima como base.

## Próximos Passos

Se o erro persistir após corrigir os campos obrigatórios:

1. Verifique os logs completos do servidor
2. Verifique se o certificado está em base64 válido
3. Verifique se a senha do certificado está correta
4. Teste em ambiente de homologação primeiro



















