# Firewall NFC-e Bridge - Solução Completa

## Problema Identificado
O Bridge NFC-e v347 está rodando corretamente, mas o Firewall do Windows está bloqueando a porta 8000, impedindo a conexão com o aplicativo Flutter.

## Verificação do Problema
```powershell
# Teste de conexão (deve retornar False se bloqueado)
Test-NetConnection -ComputerName localhost -Port 8000 -InformationLevel Quiet

# Verificar se o bridge está rodando
tasklist | findstr "ExodoNfceBridge"
```

## Soluções

### Opção 1: Configurar Firewall (Recomendado)

#### Passo 1: Abrir Firewall
1. Pressione `Windows + R`
2. Digite `firewall.cpl` e pressione Enter
3. Clique em "Configurações Avançadas" (à esquerda)

#### Passo 2: Criar Regra de Entrada
1. No painel esquerdo, clique em "Regras de Entrada"
2. Clique em "Nova Regra..." (à direita)
3. Selecione "Porta" e clique em Avançar
4. Marque "TCP" e "Portas locais específicas"
5. Digite `8000` no campo
6. Clique em Avançar
7. Selecione "Permitir a conexão"
8. Clique em Avançar
9. Marque "Rede Privada" (desmarque as outras)
10. Clique em Avançar
11. Nome: `Exodo NFC-e Bridge`
12. Descrição: `Permitir conexões do Bridge NFC-e na porta 8000`
13. Clique em Concluir

#### Passo 3: Testar
1. Reinicie o bridge NFC-e
2. Teste a conexão:
```powershell
curl http://localhost:8000/
# Deve retornar: {"status":"online","message":"Emissor NFC-e Exodo rodando!"}
```

### Opção 2: Executar como Administrador

1. Feche todos os processos do bridge
2. Clique com o botão direito em `ExodoNfceBridge_v347.exe`
3. Selecione "Executar como administrador"
4. Aceite o prompt do UAC
5. Tente emitir NFC-e novamente

### Opção 3: Configurar via PowerShell (como Administrador)

```powershell
# Abrir PowerShell como Administrador
# Criar regra de firewall
New-NetFirewallRule -DisplayName "Exodo NFC-e Bridge" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow -Profile Private

# Verificar se a regra foi criada
Get-NetFirewallRule -DisplayName "Exodo NFC-e Bridge"
```

### Opção 4: Desativar Firewall (Apenas para Teste)

**AVISO:** Não recomendado para uso prolongado!

1. Painel de Controle > Firewall do Windows Defender
2. "Ativar ou desativar o Firewall do Windows Defender"
3. Desativar para "Rede privada"
4. Testar emissão NFC-e
5. **Reativar** após o teste

## Verificação Antivírus

Alguns antivírus também bloqueiam conexões locais:

### Windows Defender
1. Abrir "Segurança do Windows"
2. "Proteção contra vírus e ameaças"
3. "Gerenciar configurações"
4. "Adicionar ou remover exclusões"
5. Adicionar:
   - `ExodoNfceBridge_v347.exe`
   - `C:\ExodoNFCe\`

### Outros Antivírus
- Adicionar exceção para o executável do bridge
- Adicionar exceção para a pasta de instalação

## Troubleshooting

### Se a porta 8000 estiver ocupada:
```powershell
# Verificar qual processo está usando a porta 8000
netstat -ano | findstr ":8000"

# Matar o processo (substitua PID pelo número retornado)
taskkill /PID <PID> /F
```

### Se o bridge não iniciar:
1. Verifique se o .NET Framework 4.8 está instalado
2. Execute como administrador
3. Verifique os logs em `backend_nfce\bridge_log.txt`

### Teste Completo:
```powershell
# 1. Verificar se o bridge está rodando
tasklist | findstr "ExodoNfceBridge"

# 2. Testar conexão HTTP
curl http://localhost:8000/

# 3. Testar endpoint de emissão
curl -X POST http://localhost:8000/api/nfce/emitir -H "Content-Type: application/json" -d "{\"test\": true}"
```

## Resultado Esperado

Após configurar o firewall corretamente, o aplicativo Flutter deverá:
- Detectar automaticamente o bridge em `localhost:8000`
- Conectar-se sem erros
- Permitir emissão NFC-e 100% local

## Suporte

Se o problema persistir após todas as tentativas:
1. Reinicie o computador
2. Verifique se há outros programas usando a porta 8000
3. Contate o suporte técnico

---
**Importante:** A configuração do firewall é essencial para o funcionamento do sistema NFC-e local.
