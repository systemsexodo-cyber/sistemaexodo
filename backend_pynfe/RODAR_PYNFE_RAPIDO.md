# ⚡ Como Rodar PyNFe - Guia Rápido

## 🎯 3 Formas de Rodar

### 1️⃣ Script de Exemplo (Mais Simples)

```bash
# 1. Editar exemplo_rodar_pynfe.py com seus dados
# 2. Executar
python exemplo_rodar_pynfe.py
```

### 2️⃣ Via API Flask (Recomendado)

```bash
# 1. Iniciar servidor
python app.py

# 2. Fazer requisição POST
# Use Postman, curl ou seu app Flutter
POST http://localhost:5000/api/nfce/emitir
```

### 3️⃣ Código Python Direto

```python
from nfce_pynfe import NFCePyNFe

nfce = NFCePyNFe()
resultado = nfce.emitir(
    empresa_data={...},
    produtos=[...],
    pagamentos=[...]
)
```

## ⚙️ Configuração Mínima

```python
# 1. Certificado em Base64
CERTIFICADO_BASE64 = "..."  # Convertido do .pfx

# 2. Dados básicos
EMPRESA_DATA = {
    'cnpj': '12345678000190',
    'uf': 'PR',  # ⚠️ NÃO use SP
    'certificado_base64': CERTIFICADO_BASE64,
    'senhaCertificado': 'senha123',
    'ambiente_homologacao': True
}
```

## 🚨 Importante

- ✅ **PR, RS, SC, MG, etc:** Use PyNFe
- ❌ **SP (São Paulo):** Use `nfce_manual_completo.py`

## 📖 Documentação Completa

Veja `COMO_RODAR_PYNFE.md` para detalhes.

















