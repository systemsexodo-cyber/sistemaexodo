# 🔧 Correção: Certificado Não Carrega no PDV

## Problema Identificado

O certificado digital não estava sendo carregado quando a empresa era selecionada no PDV porque:

1. **Empresa não estava sendo atualizada após edição**: Quando a empresa era editada e o certificado era adicionado, a empresa atual no `AuthService` não era atualizada.

2. **Logs insuficientes**: Não havia logs suficientes para diagnosticar onde o certificado estava sendo perdido.

3. **Validação incorreta**: A validação no PDV estava verificando apenas `certificadoDigitalUrl`, mas o certificado pode estar em `certificadoDigitalBytes` (base64).

## Correções Implementadas

### 1. Logs Detalhados em `selecionarEmpresa`
- ✅ Logs mostrando se `certificadoDigitalBytes` está presente
- ✅ Logs mostrando se `configuracoes` está sendo salvo corretamente
- ✅ Logs mostrando se o certificado está no `toMap()`

### 2. Logs Detalhados ao Carregar do localStorage
- ✅ Logs mostrando se `configuracoes` está sendo carregado
- ✅ Logs mostrando se `certificadoDigitalBytes` está presente após `fromMap()`

### 3. Atualização da Empresa Atual
- ✅ Quando uma empresa é atualizada, se ela for a empresa atual, ela é atualizada também no `_empresaAtual`
- ✅ A empresa atual é salva novamente no localStorage com os dados atualizados

### 4. Validação Melhorada no PDV
- ✅ Verifica todas as fontes de certificado (Base64, URL, Windows)
- ✅ Mensagem de erro mais informativa mostrando qual fonte está ausente

## Como Verificar

### 1. Ao Selecionar Empresa:
```
>>> [AuthService] Selecionando empresa: Nome da Empresa
>>> [AuthService] certificadoDigitalBytes: presente (5000 chars)
>>> [AuthService] ✓ Empresa salva no localStorage
```

### 2. Ao Carregar do localStorage:
```
>>> [AuthService] Carregando empresa do localStorage...
>>> [AuthService] certificadoDigitalBytes no map: presente (5000 chars)
>>> [AuthService] certificadoDigitalBytes após fromMap: presente (5000 chars)
```

### 3. Ao Atualizar Empresa:
```
>>> [AuthService] Atualizando empresa: Nome da Empresa
>>> [AuthService] Empresa atualizada é a empresa atual, atualizando...
>>> [AuthService] ✓ Empresa atual atualizada no localStorage
```

### 4. Ao Emitir NFC-e no PDV:
```
>>> [VendaDireta] Verificando empresa antes de emitir NFC-e...
>>> [VendaDireta] certificadoDigitalBytes: presente (5000 chars)
>>> [VendaDireta] senhaCertificado: presente (8 chars)
```

## Solução Rápida

Se o certificado ainda não aparecer:

1. **Edite a empresa novamente:**
   - Vá em "Empresas" → Edite a empresa
   - Verifique se o certificado aparece
   - Se não aparecer, selecione o certificado novamente
   - Salve a empresa

2. **Selecione a empresa novamente:**
   - Vá em "Selecionar Empresa"
   - Selecione a empresa novamente
   - Isso força o recarregamento do localStorage

3. **Verifique os logs:**
   - Abra o console do Flutter
   - Procure por `>>> [AuthService]`
   - Veja se o certificado está sendo carregado

## Próximos Passos

Se ainda não funcionar, verifique:

1. Se o certificado está sendo salvo no Firebase corretamente
2. Se o `toMap()` está incluindo o `configuracoes` corretamente
3. Se o `fromMap()` está carregando o `configuracoes` corretamente
4. Se há algum problema de sincronização entre Firebase e localStorage




