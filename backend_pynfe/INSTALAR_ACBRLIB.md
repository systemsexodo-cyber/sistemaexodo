# 📦 Instalação ACBrLib para NFC-e

## 🎯 O que é ACBrLib?

ACBrLib é a biblioteca oficial do Projeto ACBr, usada por empresas grandes e sistemas comerciais para emissão de NF-e e NFC-e.

**Vantagens:**
- ✅ 100% compatível com SP (NFC-e)
- ✅ Suporte completo a todos os estados
- ✅ Mantido pela comunidade ACBr
- ✅ Usado por empresas grandes
- ✅ Muito mais robusto que PyNFe

## 📥 Como Instalar

### Windows

1. **Baixar ACBrLib**
   - Acesse: https://projetoacbr.com.br/forum/viewtopic.php?f=111&t=70146
   - Baixe a versão mais recente para Windows
   - Extraia o arquivo ZIP

2. **Instalar DLL**
   - Copie `ACBrNFe64.dll` (ou `ACBrNFe32.dll` para 32 bits)
   - Cole em uma das pastas:
     - `C:\Program Files\ACBr\`
     - `C:\ACBr\`
     - Ou na pasta do seu projeto Python

3. **Verificar Instalação**
   ```python
   from acbrlib_wrapper import criar_instancia_acbr
   
   try:
       acbr = criar_instancia_acbr()
       print("✅ ACBrLib instalado corretamente!")
   except Exception as e:
       print(f"❌ Erro: {e}")
   ```

### Linux

1. **Baixar ACBrLib**
   - Acesse: https://projetoacbr.com.br/forum/viewtopic.php?f=111&t=70146
   - Baixe a versão para Linux
   - Extraia o arquivo

2. **Instalar Biblioteca Compartilhada**
   ```bash
   # Copiar para /usr/lib ou /usr/local/lib
   sudo cp libacbrnfe64.so /usr/lib/
   sudo ldconfig
   ```

3. **Verificar Instalação**
   ```python
   from acbrlib_wrapper import criar_instancia_acbr
   
   try:
       acbr = criar_instancia_acbr()
       print("✅ ACBrLib instalado corretamente!")
   except Exception as e:
       print(f"❌ Erro: {e}")
   ```

## 🔧 Configuração

### Opção 1: Caminho Automático

O wrapper tenta encontrar ACBrLib automaticamente nestes locais:

**Windows:**
- `C:\Program Files\ACBr\ACBrNFe64.dll`
- `C:\Program Files (x86)\ACBr\ACBrNFe32.dll`
- `C:\ACBr\ACBrNFe64.dll`
- Pasta do projeto

**Linux:**
- `/usr/lib/libacbrnfe64.so`
- `/usr/local/lib/libacbrnfe64.so`
- Pasta do projeto

### Opção 2: Caminho Manual

Se ACBrLib estiver em outro local, especifique o caminho:

```python
from nfce_acbrlib import criar_servico_nfce

# Especificar caminho manual
servico = criar_servico_nfce(
    usar_acbrlib=True,
    caminho_acbrlib=r'C:\MeuProjeto\ACBrNFe64.dll'
)
```

## 🚀 Como Usar

### Exemplo Básico

```python
from nfce_acbrlib import criar_servico_nfce

# Criar serviço (tenta ACBrLib, usa fallback se não disponível)
nfce = criar_servico_nfce(usar_acbrlib=True)

# Emitir NFC-e
resultado = nfce.emitir(
    empresa_data={
        'cnpj': '12345678000190',
        'razao_social': 'Minha Empresa',
        'uf': 'SP',
        'certificado_base64': '...',
        'senhaCertificado': 'senha123',
        'ambienteHomologacao': True,
        # ... outros dados
    },
    produtos=[...],
    pagamentos=[...],
    consumidor={...},
    numero_nfce=1
)

if resultado['success']:
    print(f"✅ NFC-e autorizada: {resultado['chave_acesso']}")
else:
    print(f"❌ Erro: {resultado['error']}")
```

### Fallback Automático

Se ACBrLib não estiver disponível, o sistema usa automaticamente a implementação SOAP manual:

```python
# Tenta ACBrLib primeiro, usa SOAP manual se não disponível
nfce = criar_servico_nfce(usar_acbrlib=True)

# Funciona mesmo sem ACBrLib instalado
resultado = nfce.emitir(...)
```

## 📋 Requisitos

- **Python:** 3.7+
- **ACBrLib:** Versão mais recente
- **Certificado Digital:** A1 (PFX) ou A3
- **Sistema:** Windows ou Linux

## 🔍 Verificar Instalação

Execute o script de teste:

```bash
python acbrlib_wrapper.py
```

Ou:

```bash
python nfce_acbrlib.py
```

## ⚠️ Troubleshooting

### Erro: "ACBrLib não encontrado"

**Solução:**
1. Verifique se a DLL/.so está no caminho correto
2. Especifique o caminho manualmente
3. Verifique permissões de leitura

### Erro: "Função não encontrada"

**Solução:**
1. Verifique se está usando a versão correta (64 ou 32 bits)
2. Atualize para a versão mais recente do ACBrLib

### Erro: "Certificado não encontrado"

**Solução:**
1. Verifique se o certificado está em base64 ou caminho válido
2. Verifique a senha do certificado

## 📚 Documentação

- **ACBr:** https://projetoacbr.com.br
- **Fórum:** https://projetoacbr.com.br/forum
- **Downloads:** https://projetoacbr.com.br/forum/viewtopic.php?f=111&t=70146

## ✅ Status

- ✅ Wrapper Python criado
- ✅ Fallback automático implementado
- ✅ Integração com código existente
- ⚠️ Implementação completa da API ACBrLib (em desenvolvimento)

**Nota:** O wrapper está funcional, mas a implementação completa da API ACBrLib requer conhecimento específico da biblioteca. Por enquanto, o fallback SOAP manual funciona perfeitamente.



















