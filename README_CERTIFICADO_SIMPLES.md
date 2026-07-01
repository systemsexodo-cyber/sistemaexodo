# SOLUÇÃO SIMPLES - Certificado NFC-e

## O Problema
O certificado digital não está sendo enviado corretamente para o Bridge, causando erro HTTP 400 na SEFAZ.

## Solução Mais Simples

### Opção 1: Usar Certificado do Windows (RECOMENDADO)

1. **No app Flutter**, vá em: **Empresas** → **Editar** → **Certificado Digital**

2. **Clique em:** "Usar certificado instalado no Windows (Recomendado)"

3. **Selecione o certificado** da BMJ Petshop

4. **Digite a senha** do certificado

5. **Salve** a empresa

6. **Teste a emissão**

---

### Opção 2: Arquivo Local (Fallback)

Se a Opção 1 não funcionar:

1. **Exporte o certificado** do Windows:
   - Abra o `e-CPF/e-CNPJ Manager` ou `Certmgr.msc`
   - Encontre o certificado da empresa
   - Clique direito → **Exportar**
   - **Formato:** PFX (Personal Information Exchange)
   - **Incluir chave privada:** SIM ✅
   - **Senha:** Use uma senha simples (ex: `123456`)
   - **Salvar em:** `C:\ExodoNFCe\certificado.pfx`

2. **Configure o Bridge v351:**
   Crie um arquivo `C:\ExodoNFCe\cert_config.json`:
   ```json
   {
     "caminho": "C:/ExodoNFCe/certificado.pfx",
     "senha": "123456"
   }
   ```

3. **Reinicie o Bridge**

4. **Teste a emissão**

---

### Opção 3: Verificar se Certificado está Salvo

Execute no console do Flutter (Debug Console):

```dart
// Verificar se certificado está na empresa atual
final empresa = authService.empresaAtual;
print('Certificado bytes: ${empresa.configuracoes?['certificadoDigitalBytes']?.length}');
print('Certificado URL: ${empresa.certificadoDigitalUrl}');
print('Senha: ${empresa.senhaCertificado?.isNotEmpty}');
```

Se mostrar `null` ou `0`, o certificado **não está salvo**.

---

## Diagnóstico Rápido

Abra o app em modo DEBUG e observe o console:

```
flutter run -v
```

Procure por estas mensagens:
- ✅ `certificadoDigitalBytes: presente (XXXX chars)` → OK
- ❌ `certificadoDigitalBytes: null` → **Problema!**

---

## Qual usar?

| Método | Quando usar |
|--------|-------------|
| **Opção 1** (Windows) | Padrão - mais confiável |
| **Opção 2** (Arquivo) | Se Opção 1 falhar |
| **Opção 3** (Debug) | Para diagnosticar |

---

## Contato
Se nenhuma opção funcionar, verifique:
1. Se o certificado está **expirado**
2. Se a **senha está correta**
3. Se o certificado tem **chave privada** (exportar com "Incluir chave privada")
