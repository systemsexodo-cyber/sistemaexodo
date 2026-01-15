# Como Usar Arquivo PFX Direto para Emitir NFC-e

## Visão Geral

O sistema agora suporta **duas formas** de fornecer o certificado digital:

1. **Arquivo PFX direto** (recomendado) - Mais simples e direto
2. **Certificado em Base64** - Para integração com sistemas que já usam base64

## Forma 1: Arquivo PFX Direto (Recomendado)

### Como Usar

Forneça o caminho do arquivo PFX e a senha nos dados da empresa:

```python
empresa_data = {
    # ... outros dados da empresa ...
    
    # Opção 1: Campos diretos
    'certificado_path': '/caminho/para/certificado.pfx',  # ou .p12
    'senha_certificado': 'sua_senha_aqui',
    
    # OU Opção 2: Em configuracoes
    'configuracoes': {
        'certificado_path': '/caminho/para/certificado.pfx',
        'senha_certificado': 'sua_senha_aqui',
    }
}
```

### Campos Aceitos

O sistema procura o arquivo PFX nos seguintes campos (em ordem de prioridade):

1. `certificado_path` ou `certificadoPath`
2. `certificado_file` ou `certificadoFile`
3. `certificado_pfx` ou `certificadoPfx`
4. `certificado_p12` ou `certificadoP12`

E a senha nos seguintes campos:

1. `senha_certificado` ou `senhaCertificado`
2. `senha_cert` ou `senhaCert`
3. Dentro de `configuracoes`: `senhaCertificado`, `senha_certificado`, `senhaCert`, `senha_cert`

### Requisitos

- O arquivo deve existir no caminho especificado
- O arquivo deve ter extensão `.pfx` ou `.p12`
- A senha deve estar correta
- O arquivo não pode estar vazio

### Exemplo Completo

```python
from nfce_pynfe_completo import NFCePyNFe

nfce = NFCePyNFe()

resultado = nfce.emitir(
    empresa_data={
        'cnpj': '12345678000190',
        'razao_social': 'Minha Empresa LTDA',
        # ... outros dados ...
        
        # Certificado PFX direto
        'certificado_path': 'C:/certificados/minha_empresa.pfx',
        'senha_certificado': 'minha_senha_123',
    },
    produtos=[...],
    pagamentos=[...],
    consumidor={...}
)
```

### Vantagens

- ✅ Mais simples - não precisa converter para base64
- ✅ Mais rápido - não precisa decodificar base64
- ✅ Mais seguro - arquivo fica no sistema de arquivos
- ✅ Mais fácil de debugar - pode verificar o arquivo diretamente

## Forma 2: Certificado em Base64

### Como Usar

Forneça o certificado em base64 e a senha:

```python
empresa_data = {
    # ... outros dados da empresa ...
    
    # Opção 1: Campo direto
    'certificado_base64': 'MIIKpAIBAzCCCl4GCSqGSIb3DQEHAaCC...',
    'senha_certificado': 'sua_senha_aqui',
    
    # OU Opção 2: Em configuracoes (mais comum no Flutter)
    'configuracoes': {
        'certificadoDigitalBytes': 'MIIKpAIBAzCCCl4GCSqGSIb3DQEHAaCC...',
        'senhaCertificado': 'sua_senha_aqui',
    }
}
```

### Campos Aceitos (em ordem de prioridade)

1. `configuracoes['certificadoDigitalBytes']`
2. `certificado_base64`
3. `certificadoDigitalUrl` (se não for URL HTTP)
4. `certificado` ou `certificado_digital`

## Ordem de Prioridade

O sistema procura o certificado na seguinte ordem:

### Para Arquivo PFX:
1. Campos diretos: `certificado_path`, `certificadoPath`, `certificado_file`, etc.
2. Campos em `configuracoes`: `configuracoes['certificado_path']`, etc.

### Para Base64:
1. `configuracoes['certificadoDigitalBytes']`
2. `certificado_base64`
3. `certificadoDigitalUrl` (se não for URL)
4. `certificado` ou `certificado_digital`

## Validações Automáticas

O sistema valida automaticamente:

### Para Arquivo PFX:
- ✅ Arquivo existe
- ✅ Arquivo não está vazio
- ✅ Extensão é .pfx ou .p12
- ✅ Senha está correta
- ✅ Certificado pode ser carregado

### Para Base64:
- ✅ Base64 é válido
- ✅ Pode ser decodificado
- ✅ Formato é PFX/P12 válido
- ✅ Senha está correta
- ✅ Certificado pode ser carregado

## Logs de Diagnóstico

O sistema exibe logs detalhados:

### Quando encontra arquivo PFX:
```
🔍 Buscando certificado digital...
   ✅ Arquivo PFX encontrado em 'certificado_path': C:/certificados/cert.pfx
   📋 Usando arquivo PFX diretamente: C:/certificados/cert.pfx
   ✅ Arquivo PFX válido: 8192 bytes
   ✅ Senha do certificado encontrada
   ✅ Arquivo PFX será usado diretamente (sem conversão para base64)
   ✅ Certificado PFX carregado e validado com sucesso
```

### Quando encontra base64:
```
🔍 Buscando certificado digital...
   ✅ Certificado encontrado em certificado_base64
      Tamanho após limpeza: 12345 caracteres
   📋 Certificado encontrado: 12345 caracteres
```

## Resolução de Problemas

### Erro: "Arquivo de certificado não encontrado"

**Causa:** O caminho do arquivo está incorreto ou o arquivo não existe.

**Solução:**
1. Verifique se o caminho está correto
2. Use caminho absoluto (completo)
3. Verifique se o arquivo existe no caminho especificado
4. No Windows, use barras `/` ou `\\` (ex: `C:/certificados/cert.pfx` ou `C:\\certificados\\cert.pfx`)

### Erro: "Senha do certificado não fornecida"

**Causa:** A senha não foi fornecida ou está em um campo não reconhecido.

**Solução:**
1. Forneça a senha em um dos campos aceitos:
   - `senha_certificado` ou `senhaCertificado`
   - `senha_cert` ou `senhaCert`
   - Dentro de `configuracoes`
2. Verifique se a senha não está vazia

### Erro: "SENHA DO CERTIFICADO INCORRETA"

**Causa:** A senha fornecida não corresponde ao certificado.

**Solução:**
1. Verifique se a senha está correta
2. Tente digitar a senha novamente
3. Verifique se não há espaços antes ou depois da senha
4. Se o certificado foi exportado recentemente, verifique se a senha está correta

### Erro: "Certificado digital não fornecido"

**Causa:** Nenhum certificado foi encontrado nos campos esperados.

**Solução:**
1. Verifique se o certificado está em um dos campos aceitos
2. Para arquivo PFX, verifique se o campo está correto (ex: `certificado_path`)
3. Para base64, verifique se está em `certificado_base64` ou `configuracoes['certificadoDigitalBytes']`
4. Verifique os logs de diagnóstico para ver quais campos foram verificados

## Exemplo de Integração

### Python

```python
from nfce_pynfe_completo import NFCePyNFe

nfce = NFCePyNFe()

# Usando arquivo PFX direto
resultado = nfce.emitir(
    empresa_data={
        'cnpj': '12345678000190',
        'razao_social': 'Minha Empresa LTDA',
        'certificado_path': '/caminho/para/certificado.pfx',
        'senha_certificado': 'senha123',
        # ... outros dados ...
    },
    produtos=[...],
    pagamentos=[...]
)
```

### Flutter/Dart (via API)

```dart
final empresaData = {
  'cnpj': '12345678000190',
  'razao_social': 'Minha Empresa LTDA',
  
  // Arquivo PFX direto
  'certificado_path': '/caminho/para/certificado.pfx',
  'senha_certificado': 'senha123',
  
  // OU Base64 (como antes)
  // 'configuracoes': {
  //   'certificadoDigitalBytes': 'MIIKpAIBAzCC...',
  //   'senhaCertificado': 'senha123',
  // },
  
  // ... outros dados ...
};

final resultado = await nfce.emitir(
  empresaData: empresaData,
  produtos: [...],
  pagamentos: [...],
);
```

## Conclusão

O suporte para arquivo PFX direto torna o uso do certificado mais simples e direto. Use esta forma quando possível, especialmente se você já tem o arquivo PFX no sistema de arquivos.

Para sistemas que já usam base64 (como Flutter), continue usando base64 normalmente - o sistema suporta ambas as formas.












