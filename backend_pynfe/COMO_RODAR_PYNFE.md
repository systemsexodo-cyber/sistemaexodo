# 🚀 Como Rodar o PyNFe para Emitir NFC-e

## 📋 Pré-requisitos

1. ✅ PyNFe instalado em modo desenvolvimento (já feito)
2. ✅ Certificado digital A1 (.pfx/.p12)
3. ✅ Dados da empresa configurados

## 🔧 Configuração Rápida

### 1. Converter Certificado para Base64

```bash
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("caminho\certificado.pfx"))

# Ou Python
python -c "import base64; print(base64.b64encode(open('certificado.pfx', 'rb').read()).decode('utf-8'))"
```

### 2. Editar `exemplo_rodar_pynfe.py`

Abra o arquivo e configure:

```python
CERTIFICADO_BASE64 = "SEU_CERTIFICADO_EM_BASE64_AQUI"
SENHA_CERTIFICADO = "SUA_SENHA"

EMPRESA_DATA = {
    'cnpj': '12345678000190',
    'razao_social': 'SUA EMPRESA LTDA',
    'uf': 'PR',  # ⚠️ NÃO use SP (use implementação manual)
    # ... outros campos
}
```

### 3. Executar

```bash
python exemplo_rodar_pynfe.py
```

## 📝 Exemplo de Uso Programático

```python
from nfce_pynfe import NFCePyNFe

# Criar instância
nfce = NFCePyNFe()

# Dados da empresa
empresa_data = {
    'cnpj': '12345678000190',
    'razao_social': 'EMPRESA TESTE LTDA',
    'uf': 'PR',
    'certificado_base64': 'SEU_CERTIFICADO_BASE64',
    'senhaCertificado': 'SUA_SENHA',
    'ambiente_homologacao': True,
    # ... outros campos
}

# Produtos
produtos = [
    {
        'codigo': 'PROD001',
        'descricao': 'Produto Teste',
        'ncm': '00000000',
        'cfop': '5102',
        'quantidade': 1.0,
        'valorUnitario': 10.00,
        'valorTotal': 10.00,
        'icms': {
            'origem': 0,
            'cst': '00',
            'modalidade': '00',
            'aliquota': 18.0
        }
    }
]

# Pagamentos
pagamentos = [
    {'tipo': '01', 'valor': 10.00}  # 01=Dinheiro
]

# Emitir
resultado = nfce.emitir(
    empresa_data=empresa_data,
    produtos=produtos,
    pagamentos=pagamentos,
    numero_nfce=1
)

# Verificar resultado
if resultado.get('success'):
    print(f"✅ Autorizada! Chave: {resultado.get('chave_acesso')}")
else:
    print(f"❌ Rejeitada: {resultado.get('error')}")
```

## 🌐 Via API Flask

O `app.py` já está configurado para usar PyNFe automaticamente (exceto para SP):

```bash
# Iniciar servidor
python app.py

# Fazer requisição POST
curl -X POST http://localhost:5000/api/nfce/emitir \
  -H "Content-Type: application/json" \
  -d '{
    "empresa": {
      "cnpj": "12345678000190",
      "razao_social": "EMPRESA TESTE",
      "uf": "PR",
      "certificado_base64": "SEU_CERTIFICADO",
      "senhaCertificado": "SUA_SENHA",
      "ambiente_homologacao": true
    },
    "produtos": [...],
    "pagamentos": [...]
  }'
```

## ⚠️ Importante: Estados Suportados

### ✅ Funciona bem com PyNFe:
- PR (Paraná)
- RS (Rio Grande do Sul)
- SC (Santa Catarina)
- MG (Minas Gerais)
- RJ (Rio de Janeiro)
- E outros estados que usam WSDL

### ❌ NÃO funciona bem com PyNFe:
- **SP (São Paulo)** - Não usa WSDL, usa SVRS
  - **Solução:** Use `nfce_manual_completo.py`

## 🔄 Fallback Automático

O `app.py` já tem lógica de fallback:

1. **Tenta PyNFe primeiro** (se UF ≠ SP e PyNFe disponível)
2. **Usa implementação manual** se:
   - UF = SP
   - PyNFe não disponível
   - Erro no PyNFe

## 🐛 Troubleshooting

### Erro: "PyNFe não está instalado"

```bash
cd pynfe_dev
pip install -e .
```

### Erro: "Certificado digital não fornecido"

- Verifique se `certificado_base64` está preenchido
- Verifique se a senha está correta

### Erro: "There is no default service defined"

- Isso acontece com SP
- Use a implementação manual para SP

### Erro de validação XML

- Verifique se todos os campos obrigatórios estão preenchidos
- Verifique se os valores estão no formato correto
- Consulte os schemas XSD do PyNFe

## 📚 Recursos

- **PyNFe Docs:** `pynfe_dev/README.md`
- **Testes:** `pynfe_dev/tests/test_nfce_serializacao.py`
- **Implementação Manual:** `nfce_manual_completo.py`

## ✅ Checklist Antes de Rodar

- [ ] PyNFe instalado em modo desenvolvimento
- [ ] Certificado digital convertido para base64
- [ ] Senha do certificado configurada
- [ ] Dados da empresa preenchidos
- [ ] UF diferente de SP (ou usar implementação manual)
- [ ] Ambiente de homologação configurado
- [ ] Produtos e pagamentos configurados

---

**Pronto para emitir NFC-e!** 🎉

















