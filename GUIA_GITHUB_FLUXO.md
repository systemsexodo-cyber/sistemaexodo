# Guia de Fluxo de Trabalho GitHub (Sistema Êxodo)

Este guia explica como usar as automações que configuramos para o seu projeto.

## 1. O Robô Analista (CI)
Toda vez que você envia código (`push`) para o GitHub, o workflow **"Verificação de Código (CI)"** entra em ação.
- **O que ele faz?** Ele baixa o seu código, instala as dependências e verifica se existem erros óbvios ou se os testes automáticos passam.
- **Onde vejo?** Na aba **Actions** do seu repositório no GitHub.

## 2. Deploy Automático (Firebase)
Ao enviar código para as branches `master`, `main` ou `modo-dev`:
- **O que ele faz?** Gera a versão Web do seu sistema e envia automaticamente para o Firebase Hosting.
- **URL:** [https://exodosystems-1541d.web.app](https://exodosystems-1541d.web.app)

## 3. Como criar uma Nova Versão (Release) e Gerar APK
Sempre que você atingir um marco importante (ex: "Sistema de Agendamento Finalizado"), você deve criar uma Versão:

1. Vá no site do GitHub do seu projeto.
2. No menu à direita, clique em **Releases**.
3. Clique em **Draft a new release**.
4. **Tag:** Digite algo como `v1.0.1`.
5. **Título:** "Versão 1.0.1 - Ajustes de Agendamento".
6. Clique em **Publish release**.

**O que acontece depois?**
- O robô **"Gerar APK de Versão"** vai começar a trabalhar sozinho.
- Ele vai gerar o arquivo `.apk` (para instalar no Android) e vai **anexar automaticamente** na página dessa versão que você acabou de criar.

## 4. Fluxo de Trabalho Seguro (Recomendado)

Para evitar erros em produção, agora configuramos o seguinte fluxo:

1. **Trabalhe na branch `master`**: Faça suas alterações, testes locais e commits aqui.
2. **Push para `master`**: Ao dar o push, o robô **CI** vai verificar se seu código tem erros ou se quebra os testes.
   - Isso **NÃO** altera o site que está no ar.
3. **Pull Request (PR)**: Quando terminar uma tarefa na `master`, vá ao GitHub e abra um "Pull Request" da branch `master` para a `main`.
4. **Revisão e Merge**: Verifique se o GitHub diz "All checks passed". Se sim, clique em **Merge**.
5. **Deploy Automático**: No momento em que você aceita o Merge na `main`, o robô de **Deploy** entra em ação e atualiza o site automaticamente.

## 5. Dicas de Segurança
- **Nunca trabalhe direto na `main`**: Deixe-a apenas para código que já está validado e pronto para os clientes.
- **Não apague a branch master**: Ela é sua base de desenvolvimento.

## 6. Próximos Passos
Para aplicar essas mudanças no GitHub agora:
1. No terminal:
   ```powershell
   git add .github/workflows/firebase-deploy.yml GUIA_GITHUB_FLUXO.md
   git commit -m "fix: Ajustando fluxo de deploy seguro (apenas via main)"
   .\push_para_github.ps1
   ```
