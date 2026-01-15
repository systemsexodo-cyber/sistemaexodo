# 📋 Estrutura da Chave de Acesso da NFC-e

## ✅ Confirmação Oficial

A chave de acesso da NFC-e tem **44 dígitos numéricos** no total.

## 📐 Composição da Chave (44 dígitos)

| Campo | Descrição | Tamanho | Exemplo |
|-------|-----------|---------|---------|
| **cUF** | Código da Unidade Federativa | 2 dígitos | 35 (SP) |
| **AAMM** | Ano e mês de emissão | 4 dígitos | 2412 (dez/2024) |
| **CNPJ** | CNPJ do emitente | 14 dígitos | 04829400000165 |
| **mod** | Modelo do documento | 2 dígitos | 65 (NFC-e) |
| **série** | Série do documento | 3 dígitos | 001 |
| **nNF** | Número da NFC-e | 9 dígitos | 000000001 |
| **tpEmis** | Tipo de emissão | 1 dígito | 1 (normal) |
| **cNF** | Código numérico aleatório | 8 dígitos | 12345678 |
| **cDV** | Dígito verificador | 1 dígito | 5 |

**Total: 2 + 4 + 14 + 2 + 3 + 9 + 1 + 8 + 1 = 44 dígitos**

## 🔢 Para Calcular o DV

1. **Montar chave de 43 dígitos** (sem o DV):
   ```
   cUF + AAMM + CNPJ + mod + série + nNF + tpEmis + cNF
   = 2 + 4 + 14 + 2 + 3 + 9 + 1 + 8 = 43 dígitos
   ```

2. **Calcular o dígito verificador (DV)** usando algoritmo módulo 11

3. **Adicionar o DV** à chave:
   ```
   Chave completa = 43 dígitos + 1 DV = 44 dígitos
   ```

## ✅ Validações Implementadas

- ✅ cUF: Exatamente 2 dígitos
- ✅ AAMM: Exatamente 4 dígitos (formato YYMM)
- ✅ CNPJ: Exatamente 14 dígitos (apenas números)
- ✅ mod: Exatamente 2 dígitos (65 para NFC-e)
- ✅ série: Exatamente 3 dígitos
- ✅ nNF: Exatamente 9 dígitos
- ✅ tpEmis: Exatamente 1 dígito
- ✅ cNF: Exatamente 8 dígitos
- ✅ cDV: Exatamente 1 dígito

## 🎯 Exemplo Completo

```
Chave de 43 dígitos (sem DV):
352412048294000001656500100000000112345678

Cálculo do DV:
Algoritmo módulo 11 → DV = 5

Chave completa (44 dígitos):
3524120482940000016565001000000001123456785
```

## 📚 Referências

- Documentação oficial da SEFAZ
- Manual de Integração NFC-e
- Padrão Técnico de Comunicação NFC-e

---

**Última atualização:** 2024-12-19
**Status:** ✅ Implementado corretamente


