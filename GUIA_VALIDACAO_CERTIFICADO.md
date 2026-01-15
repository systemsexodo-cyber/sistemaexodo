# 📋 Guia de Validação de Certificado Digital

## 🔍 O que é Validado

O sistema valida automaticamente o certificado digital antes de emitir NFC-e, verificando:

### ✅ Validações Realizadas

1. **Data de Validade**
   - Verifica se o certificado está dentro do prazo de validade
   - Alerta se expira em menos de 30 dias
   - Bloqueia se já expirou

2. **Formato (PKCS#12)**
   - Verifica se o certificado está em formato PKCS#12 padrão (.pfx)
   - Detecta se é PEM ou outro formato

3. **Senha Correta**
   - Testa se a senha consegue descriptografar o certificado
   - Verifica se a chave privada pode ser extraída

4. **Chave Privada**
   - Verifica se a chave privada está presente no certificado
   - Necessária para assinar a NFC-e

5. **CNPJ**
   - Compara o CNPJ do certificado com o CNPJ da empresa
   - Alerta se não corresponder

6. **Ambiente (Homologação/Produção)**
   - Verifica se o certificado corresponde ao ambiente configurado
   - Certificado de homologação não funciona em produção e vice-versa

7. **Tamanho e Integridade**
   - Verifica se o certificado não está corrompido
   - Valida tamanho mínimo

## 🚀 Como Usar a Validação

### Validação Automática

A validação é feita automaticamente quando você tenta emitir uma NFC-e. Se houver problemas, o sistema exibirá mensagens claras com orientações.

### Validação Manual (Programática)

```dart
import 'package:sistema_exodo/services/certificado_validacao_service.dart';

// Validar certificado
final resultado = await CertificadoValidacaoService.validarCertificado(
  certificadoDigitalBytes: empresa.configuracoes?['certificadoDigitalBytes'],
  certificadoUrl: empresa.certificadoDigitalUrl,
  senha: empresa.senhaCertificado ?? '',
  cnpjEmpresa: empresa.cnpj,
  ambienteHomologacao: true, // ou false para produção
);

// Verificar resultado
if (resultado.valido) {
  print('✓ Certificado válido!');
} else {
  print('✗ Certificado inválido:');
  for (var erro in resultado.erros) {
    print('  - $erro');
  }
  
  // Obter mensagem formatada com orientações
  final mensagem = CertificadoValidacaoService.gerarMensagemOrientacao(resultado);
  print(mensagem);
}
```

## 📊 Estrutura do Resultado

```dart
class ResultadoValidacaoCertificado {
  final bool valido;              // true se certificado está OK
  final List<String> erros;       // Lista de erros encontrados
  final List<String> avisos;      // Lista de avisos (não bloqueiam)
  final Map<String, dynamic> informacoes; // Informações detalhadas
}
```

### Informações Disponíveis

O mapa `informacoes` contém:

- `certificadoCarregado`: bool - Se o certificado foi carregado com sucesso
- `formato`: String - Formato detectado (ex: "PKCS#12")
- `validade`: String - Data de validade (ISO 8601)
- `diasRestantes`: int - Dias até expirar
- `chavePrivada`: bool - Se chave privada está presente
- `tamanhoChave`: int - Tamanho da chave em bits
- `cnpjCertificado`: String - CNPJ extraído do certificado
- `cnpjEmpresa`: String - CNPJ da empresa
- `cnpjCorresponde`: bool - Se CNPJs correspondem
- `ambiente`: String - "homologacao" ou "producao"
- `tamanhoBytes`: int - Tamanho do certificado em bytes

## 🔧 Soluções para Problemas Comuns

### Erro: "Senha do certificado incorreta"

**Solução:**
1. Verifique se a senha está correta
2. A senha é case-sensitive (diferencia maiúsculas/minúsculas)
3. Teste a senha abrindo o certificado diretamente
4. Se necessário, redefina a senha do certificado

### Erro: "Chave privada não encontrada"

**Solução:**
1. Re-exporte o certificado INCLUINDO a chave privada
2. No Windows: `certmgr.msc` → Exportar → Marque "Incluir chave privada"
3. Use formato PKCS#12 (.pfx)
4. Não marque "Exportar chave privada estendida"

### Erro: "Certificado expirado"

**Solução:**
1. Renove o certificado na autoridade certificadora
2. Importe o novo certificado no sistema
3. Configure o novo certificado na empresa

### Erro: "Formato incorreto"

**Solução:**
1. Re-exporte o certificado em formato PKCS#12 (.pfx)
2. Use senha simples (apenas letras e números)
3. Não marque "Habilitar proteção forte"
4. Não use opções avançadas na exportação

### Erro: "CNPJ não corresponde"

**Solução:**
1. Use o certificado correto para esta empresa
2. Verifique se o CNPJ do certificado corresponde ao CNPJ da empresa
3. Se necessário, configure o certificado correto

## 📝 Exemplo de Uso Completo

```dart
// Validar certificado antes de emitir NFC-e
final resultado = await CertificadoValidacaoService.validarCertificado(
  certificadoDigitalBytes: empresa.configuracoes?['certificadoDigitalBytes'],
  certificadoUrl: empresa.certificadoDigitalUrl,
  senha: empresa.senhaCertificado ?? '',
  cnpjEmpresa: empresa.cnpj,
  ambienteHomologacao: ambienteHomologacao,
);

if (!resultado.valido) {
  // Exibir mensagem de erro com orientações
  final mensagem = CertificadoValidacaoService.gerarMensagemOrientacao(resultado);
  
  // Mostrar diálogo de erro
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Certificado Inválido'),
      content: Text(mensagem),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('OK'),
        ),
      ],
    ),
  );
  
  return; // Não continuar com a emissão
}

// Se chegou aqui, certificado está válido
// Continuar com a emissão da NFC-e...
```

## ⚠️ Importante

- A validação é feita automaticamente antes de cada emissão
- Erros bloqueiam a emissão, avisos apenas alertam
- Sempre verifique os avisos, mesmo que o certificado esteja válido
- Mantenha o certificado atualizado e válido

## 🔄 Próximos Passos

Após validar o certificado:

1. Se válido: Pode emitir NFC-e normalmente
2. Se inválido: Corrija os problemas indicados e valide novamente
3. Se houver avisos: Considere corrigir para evitar problemas futuros











