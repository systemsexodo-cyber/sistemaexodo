# Painel local de licenças Êxodo (offline)

O painel local emite licenças assinadas mesmo quando a Nuvem Êxodo, a VM, o
Supabase e o Tailscale estiverem fora do ar. Ele gera dois tipos:

| Tipo | Para que serve | Empresa |
| --- | --- | --- |
| **Ativar computador** (`instalacao`) | Libera o primeiro boot; é a licença que o sistema exige para abrir. | Opcional |
| **Liberar empresa** (`emergencial`) | Libera uma empresa bloqueada por falta de mensalidade/sem internet. | Obrigatória |

Os dois usam a mesma chave privada e valem no máximo 30 dias.

## Segurança da chave
- A chave privada fica fora do repositório, em:
  `%USERPROFILE%\Documents\ExodoLicencasPrivadas\chave_privada_exodo.pem`
- O aplicativo contém somente a chave pública.
- Nunca envie, publique, coloque no Git ou copie a chave privada para clientes.
- Faça uma cópia de segurança da chave privada em mídia criptografada e guarde-a em local seguro. Sem ela, não será possível emitir novas licenças com esta chave.
- O painel escuta somente em `127.0.0.1` (não fica acessível pela rede).
- Cada licença é vinculada ao ID da empresa e ao ID físico do computador.
- Validades disponíveis: 7, 15 ou 30 dias.

## Abrir o painel
1. No seu computador administrativo, abra a pasta do projeto.
2. Dê dois cliques em `ABRIR_PAINEL_EMERGENCIA.bat`.
3. O painel abre no navegador em `http://127.0.0.1:8797`.
4. Escolha **Ativar computador** (instalação) ou **Liberar empresa** (emergencial), preencha os dados e gere o arquivo.
5. Envie ao cliente somente o JSON baixado.

## Ativar um computador sem internet

Use quando o cliente está fazendo o primeiro acesso e a nuvem de licenças está
fora do ar (o setup não conseguiu ativar sozinho):

1. No cliente, a tela de ativação mostra o **ID deste computador** (64 caracteres). Copie.
2. No painel, escolha **Ativar computador**, cole o ID, o nome do PC e a validade (até 30 dias).
3. Gere e envie o arquivo `EXODO-INSTALACAO-....json`.
4. No cliente, clique em **Sem internet? Aplicar licença offline**.
5. Escolha o arquivo `.json` (ou cole o conteúdo no campo) e clique em **APLICAR LICENÇA**.
6. O app confere assinatura, vínculo com o computador e vencimento, grava a licença e abre o sistema.

A licença offline **não** consulta mensalidade nem código de venda: é a chave
privada do suporte autorizando. Use só na contingência; a renovação normal
continua sendo pela nuvem.

## Código curto de liberação offline (EXO-OFF-XXXXXX-XXXXXX)

Quando a nuvem de licenças não responde e não dá para mandar arquivo, gere um
código curto. Ele é preso ao ID do computador e vale no máximo 30 dias:

```bash
node tools/licencas/gerar_codigo_offline.js <ID_DO_COMPUTADOR> 30
```

1. O cliente copia o **ID deste computador** da tela de ativação e envia ao suporte.
2. O suporte roda o comando e recebe algo como `EXO-OFF-02F9NR-H3HWV8`.
3. O cliente cola o código no campo **Código de ativação** e toca em **ATIVAR ESTE COMPUTADOR**.

O código não consulta a nuvem e também funciona em *Sem internet? Aplicar
licença offline*. O app confere o MAC, o computador e o vencimento; o código
fica gravado nas preferências e o gate de boot o aceita até a data impressa.

> **Atenção:** o segredo do MAC está embutido no aplicativo. Quem extrair esse
> segredo do executável consegue gerar códigos para qualquer computador. Use o
> código curto apenas na contingência; a licença assinada (seção anterior) é a
> opção que mantém a trava dependente da chave privada.

## Liberar uma empresa bloqueada (emergencial)
1. Na tela de bloqueio do cliente, copie o ID da empresa e o ID da máquina.
2. No painel, escolha **Liberar empresa**, preencha e gere a licença.
3. O cliente cola o conteúdo do arquivo no campo de licença emergencial e valida.

Também é possível iniciar pelo PowerShell:
`node tools/licencas/painel_emergencia.js`

## Gerador de terminal
Também está disponível:
`node tools/licencas/gerar_licenca_emergencia.js`

## Licença de instalação (30 dias, automática)

Além da emergencial, existe a **licença de instalação**, emitida na hora do
setup e renovada depois do pagamento da mensalidade. Ela usa a MESMA chave
privada desta pasta, mas assina com `type: "instalacao"` e fica presa ao
computador (`MachineGuid`):

- Função da nuvem: `supabase/functions/licenca-instalacao` (veja o README dela);
- Gravação no cliente: `scripts/ativar_instalacao.ps1` (roda no fim do setup);
- Validação no app: `lib/services/licenca_instalacao_service.dart`;
- Sem licença válida o app não passa da tela de ativação;
- Sem internet no primeiro boot: use a licença de instalação offline do painel
  (seção "Ativar um computador sem internet").

A chave privada vai para o Supabase como segredo (`EXODO_LICENSE_PRIVATE_KEY`),
nunca para o instalador.

## Código de ativação por venda

Cada venda recebe um código de uso único (`EXO-XXXX-XXXX-XXXX`), gerado com:

```bash
node tools/licencas/gerar_codigos_ativacao.js --quantidade 1 --empresa <uuid>
```

O código é gravado na tabela `licencas_ativacao` da nuvem (ou impresso como SQL
com `--sql`). Sem ele o setup não ativa um computador novo, então copiar a
pasta do sistema para outro PC não libera o uso. A função da nuvem confere o
código, consome antes de emitir a licença e amarra o computador ao `machine_id`.

## Limitação desta etapa
A licença emergencial, a de instalação e o código de ativação por venda estão
implementados e assinados digitalmente. O que ainda falta é o controle da
quantidade de computadores permitidos por empresa no Portal Êxodo; hoje o
suporte revoga um código perdido pelo SQL da tabela `licencas_ativacao`.
