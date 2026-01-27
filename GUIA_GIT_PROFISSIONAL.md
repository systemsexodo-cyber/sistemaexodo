# 🚀 Gestão Git Profissional - Sistema Êxodo

Para tornar seu fluxo de trabalho mais profissional e seguro, criamos o **Git Manager (git_exodo.ps1)**. Este script centraliza todas as operações git que você precisa, garantindo que o histórico do projeto seja preservado e que o código passe por verificações antes de ir para o GitHub.

## 🛠️ Como Usar (O Único Comando que Você Precisa)

Sempre que terminar uma alteração, abra o PowerShell na pasta do projeto e digite:

```powershell
.\git_exodo.ps1
```

### O que ele faz por você:
1.  **[AUTO] Salvar e Enviar**: Faz o `add .`, pergunta o tipo de alteração (feat, fix, chore), executa o `flutter analyze` para garantir que não há erros graves, e faz o `push` para a branch atual.
2.  **Sincronizar**: Traz as mudanças do GitHub para o seu computador com segurança.
3.  **Preparar Deploy**: Automatiza o processo de levar o código da branch de desenvolvimento para a `main`, iniciando o deploy no Firebase.

---

## 🏛️ Estrutura de Branches Profissional

Agora seguimos este padrão (o script gerencia isso para você):

1.  **`modo-dev`**: Onde toda a mágica acontece. Você faz suas alterações e testes aqui.
2.  **`main`**: A branch sagrada. Ela só recebe código que já foi testado no `modo-dev`. O que cai aqui vai direto para o site oficial (Produção).

---

## ❌ O que EVITAR a partir de agora

Para manter o projeto profissional, **NÃO use mais**:
-   `push_para_github.ps1`: Este script apaga o histórico de commits (faz um "reset" total). Isso é perigoso em projetos profissionais pois impede que você veja quem mudou o quê e quando.
-   `push_seguro.ps1`: Foi substituído pelas verificações inteligentes do `git_exodo.ps1`.
-   `salvar_alteracoes.ps1`: O `git_exodo.ps1` já cuida do salvamento e do envio de forma mais integrada.

---

## ✅ Checklist do Desenvolvedor Profissional

1.  **Finalizou um ajuste?** Rode `.\git_exodo.ps1` e escolha a opção **1**.
2.  **Quer atualizar o site?** No `.\git_exodo.ps1`, escolha a opção **6** (Prepare Deploy).
3.  **Começou o dia?** Escolha a opção **2** (Sincronizar) para garantir que tem o código mais recente.

---

**Dica:** Se o script pedir permissão para executar, você pode rodar este comando uma única vez:
`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
