# Como gerar e publicar uma versão

## O caminho fácil (dentro do sistema)

Menu **Gerenciar Empresas** → card **🚀 GERAR VERSÃO**:

1. **Que tipo de versão é esta?** — o número é calculado sozinho a partir do que
   está no código:

   | Tipo | Exemplo |
   |---|---|
   | Correção (ajuste pequeno) | 1.0.36 → **1.0.37** |
   | Versão nova (novidade) | 1.0.36 → **1.1.0** |
   | Versão grande (mudança grande) | 1.0.36 → **2.0.0** |

2. **Detalhes desta atualização** — escreva o que mudou. Esse texto vai para a
   nuvem junto da versão e **aparece para o cliente na tela de atualização**
   ("O que mudou nesta versão").

3. **Gerar e compilar** — o sistema grava o número novo no código e roda o
   `flutter build windows --release`, mostrando a compilação ao vivo.

4. **Publicar agora** — escolhe o destino (TODOS os clientes ou uma/mais
   empresas), confirma o pacote e envia. Ao publicar, a entrada é anotada
   automaticamente no **HISTORICO_VERSOES.md** do projeto.

Para acompanhar o que está no ar: card **📤 PUBLICAR ATUALIZAÇÃO** →
**Ver versões publicadas** (mostra a versão global, as direcionadas por empresa —
com a marca **📦 pacote na nuvem** quando o arquivo daquela versão ainda existe —
e permite remover o direcionamento).

## Escolhendo a versão na hora de publicar

Ao publicar, o **destino** é escolhido primeiro e a **versão** depois. São quatro
opções, e nenhuma delas exige saber o número de cor:

| Opção | O que faz | Quando usar |
|---|---|---|
| **A que acabei de gerar — 1.0.37** | usa o pacote compilado agora nesta máquina e sobe ele | fluxo normal, depois do assistente "Gerar versão" |
| **Numeração automática — 1.0.38** | calcula o próximo número, **grava no código e compila antes de publicar** | publicar sem ter passado pelo assistente |
| **Pacote que já está na nuvem** | não compila e **não envia arquivo nenhum**: só aponta a versão escolhida para o destino | voltar uma empresa para uma versão anterior, repetir a mesma versão em outra empresa |
| **Pacote pronto nesta máquina** | usa o programa já compilado aqui, com o número que estiver no campo | quando você compilou por fora e só quer publicar |

A opção de numeração automática mostra as três variações antes de você escolher
(correção `1.0.36 → 1.0.37`, versão nova `1.0.36 → 1.1.0`, versão grande
`1.0.36 → 2.0.0`) e parte sempre da **maior versão conhecida** — o que está no
código × o que já está na nuvem — então **nunca repete um número já publicado**,
mesmo que o código esteja atrás do que subiu.

Quando o pacote vem da nuvem, a publicação **não envia nada**: o arquivo já
está lá, com a versão no nome, e só o registro do destino (`app_latest` ou
`app_update_<empresa>`) passa a apontar para ele. É o caminho mais rápido para
desfazer uma atualização que deu problema.

O mesmo caminho está em **Ver versões publicadas** → *📦 Pacotes na nuvem*:
cada pacote com tamanho, data de envio e o botão **Direcionar**.

> Se você escolher uma versão que **não** tem pacote na nuvem, a publicação é
> recusada com o motivo — em vez de gravar um link quebrado nos clientes.

## O que viaja na atualização

Um pacote `.zip` com o programa de verdade:

```
sistema_exodo_novo.exe      (o "runner" do Flutter — ~85 KB, igual em toda versão)
data/app.so                 (o código compilado — é o que muda o sistema)
data/flutter_assets/        (telas, fontes, imagens)
```

> Publicar **só o `.exe`** não atualiza nada: ele é igual em todas as versões e
> não carrega o código. O sistema agora recusa pacote que não traga o
> `data/app.so`.

Os detalhes ("o que mudou") vão num arquivo ao lado, com a versão no nome:
`sistema_exodo_novo_<versao>.notas.txt`.

### Onde ficam na nuvem

| O que | Onde |
|---|---|
| Pacote da versão | Storage `atualizacoes/sistema_exodo_novo_<versao>.zip` |
| Detalhes da versão | Storage `atualizacoes/sistema_exodo_novo_<versao>.notas.txt` |
| Versão de TODOS os clientes | tabela `bridge_config`, registro `app_latest` |
| Versão de uma empresa | tabela `bridge_config`, registro `app_update_<id da empresa>` |

Cada versão tem seu próprio arquivo (o nome leva a versão), então publicar para
uma empresa não troca o arquivo que outra já baixou e não existe cache servindo
versão velha.

## No computador do cliente

1. O sistema abre e procura atualização (empresa primeiro, depois geral).
2. Baixa o pacote com barra de progresso, mostrando **o que mudou nesta versão**.
3. **Confere o pacote** antes de encostar na instalação: recusa arquivo que não é
   `.zip`, download cortado e pacote sem `data/app.so`.
4. Extrai para uma pasta de espera, fecha o sistema, copia os arquivos por cima
   (guardando cópia em `_backup_atualizacao`) e reabre.

Se algo for recusado, aparece avisando **o motivo** e o sistema continua
funcionando na versão atual.

## Pela linha de comando (alternativa)

```bat
:: Publica para TODOS, com o número calculado e detalhes
PUBLICAR_NOVA_VERSAO_APP.bat

:: Publica para uma empresa (ou global) um pacote já compilado
python publicar_para_empresa.py global 1.0.37 --notas "corrige o fechamento do caixa"
python publicar_para_empresa.py 22ae2c16-a730-43f3-a4f9-19f105eb0d13 1.0.37 --notas "teste na BMJ"
```

## Regras que valem a pena lembrar

- **A versão que o cliente compara é a que está compilada no programa**
  (`currentAppVersion`, em `lib/services/app_update_service.dart`). Publicar um
  número novo sem compilar de novo faz o cliente baixar e continuar na mesma
  versão — por isso o assistente grava a versão **antes** de compilar.
- **Forçar** (na tela de publicação) baixa a versão mesmo em quem já está numa
  mais nova: é assim que se volta atrás de uma versão com problema.
- A nuvem nunca é apagada sozinha: publicar só escreve o registro do destino.
