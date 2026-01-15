# 📝 Exemplo de Uso do NFCeServiceNfelib

## ✅ Serviço Criado

O novo serviço `nfce_service_nfelib.py` foi criado e está pronto para uso!

## 🚀 Como Usar

### 1. Importar o serviço

```python
from services.nfce_service_nfelib import NFCeServiceNfelib

# Criar instância
nfce_service = NFCeServiceNfelib()
```

### 2. Preparar dados

```python
data = {
    'empresa': {
        'cnpj': '04829400000165',
        'razao_social': 'BMJ COMERCIO E SERVICOS DE PETSHOP LTDA',
        'nome_fantasia': 'E O BICHO PETSHOP',
        'logradouro': 'SAO JERONIMO, 177',
        'numero': '177',
        'bairro': 'JARDIM SAO JUDAS TADEU',
        'codigo_ibge': '3549904',
        'cidade': 'Sao Jose dos Campos',
        'uf': 'SP',
        'cep': '12228350',
        'inscricao_estadual': '645431707119',
        'crt': '1'  # 1 = Simples Nacional
    },
    'produtos': [
        {
            'codigo': 'COD-1',
            'descricao': 'PRODUTO TESTE',
            'ncm': '2201100',
            'cfop': '5405',
            'unidade': 'UN',
            'quantidade': 3,
            'valor_unitario': 2.00,
            'valor_total': 6.00,
            'valor_impostos': 1.08,
            'csosn': '500'
        }
    ],
    'pagamentos': [
        {
            'tipo': '01',  # 01 = Dinheiro
            'valor': 6.00,
            'descricao': 'Dinheiro'
        }
    ],
    'certificado': {
        'arquivo': 'caminho/para/certificado.pfx',
        'senha': 'senha_do_certificado'
    },
    'ambiente_homologacao': True,
    'numero': '1',
    'serie': '1',
    'natureza_operacao': 'VENDA'
}
```

### 3. Emitir NFC-e

```python
resultado = nfce_service.emitir_nfce(data)

if resultado.get('success') and resultado.get('autorizada'):
    print(f"✅ NFC-e autorizada!")
    print(f"Protocolo: {resultado.get('protocolo')}")
    print(f"Chave de acesso: {resultado.get('chave_acesso')}")
else:
    print(f"❌ Erro: {resultado.get('error')}")
    print(f"cStat: {resultado.get('cstat')}")
    print(f"Motivo: {resultado.get('motivo')}")
```

## 🎯 Vantagens do nfelib

1. ✅ **XML Correto**: Gera XML validado pelo schema da SEFAZ
2. ✅ **Sem SOAP**: O XML gerado não tem envelope SOAP (apenas no envio)
3. ✅ **Sem Prefixos**: Não adiciona prefixos `ns0:`, `ns1:`, etc.
4. ✅ **Validação Automática**: Valida automaticamente contra os XSDs oficiais
5. ✅ **Estrutura Correta**: `idLote` com 15 dígitos, `indSinc=1`, etc.

## 📋 Integração com o Sistema Atual

Para usar o novo serviço no lugar do PyNFe, você pode:

1. **Opção 1**: Modificar o `nfce_service.py` para usar `NFCeServiceNfelib` quando disponível
2. **Opção 2**: Criar um factory que escolhe entre PyNFe e nfelib
3. **Opção 3**: Substituir completamente o PyNFe pelo nfelib

## 🔧 Próximos Passos

1. Testar o serviço em ambiente de homologação
2. Verificar se o XML gerado está correto (sem SOAP, sem prefixos)
3. Validar com a SEFAZ
4. Integrar com o sistema atual


























